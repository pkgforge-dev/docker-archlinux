#!/usr/bin/env bash
#
# Check the shape of every workflow, and the behaviour of ci.yml.
#
# Each workflow:
#   - permissions: {} at the top, and permissions on each job
#   - timeout-minutes on each job (a job that calls a reusable workflow
#     cannot have one)
#   - each action pinned by a 40 hex commit, with a version comment
#   - each checkout sets persist-credentials: false, unless its job has
#     contents: write
#   - no ${{ inputs, matrix, needs, github.event or github.head_ref }} in a
#     run: block; pass the value through env:
#   - no pull_request_target; workflow_run only in bot-merge.yml
#   - runs-on is a pinned label, never *-latest
#   - shell: bash by default, so each run: block has -eo pipefail
#   - no unquoted if: !, which YAML reads as a tag
#   - a job that writes packages, contents or pages never runs under a
#     concurrency group that cancels in progress
#   - upload-artifact sets overwrite: true, and the Pages artifact name holds
#     github.run_attempt, so a re-run does not stop on a name it made before
#   - a job named watch* has no needs, and no job needs it
# No script or workflow deletes a package version or a manifest.
#
# ci.yml:
#   - the concurrency group: per pull request with cancel, per run elsewhere
#   - the check job judges every needed job; a skipped image job passes
#   - each job runs its suite or linter, with the tools of
#     scripts/install-tools; the image job runs its steps in build order
#   - the changes job picks the ports from the diff
#   - tests/policy/image-inputs names the inputs of the image
#
# The workflows are read as data with yq (tests/lib/harness.sh yaml_json).
# All rules of one workflow run in one jq call.
# shellcheck disable=SC2016 # the jq programs are single-quoted, and expand in jq
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

cd "$REPO_ROOT"
work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

if ! need_tool yq jq; then
  rc=0
  summary || rc=$?
  exit "$rc"
fi

workflows=()
for wf in .github/workflows/*.yml .github/workflows/*.yaml; do
  [ -e "$wf" ] || continue
  workflows+=("$wf")
done
if [ "${#workflows[@]}" -eq 0 ]; then
  fail "there are workflows" "no .github/workflows/*.yml" "reproduce: ls .github/workflows"
  summary
  exit 1
fi

# rule DESC JQ_FILTER WHY: one rule. The filter reads the workflow as JSON
# and prints one line per fault. No line is a pass.
R_DESC=()
R_PROG=()
R_WHY=()
rule() {
  R_DESC+=("$1")
  R_PROG+=("$2")
  R_WHY+=("$3")
}

rule "top-level permissions: {}" \
  'if .permissions == {} then empty else "permissions: \(.permissions | tojson)" end' \
  "each job asks for its own permissions; the top level grants nothing"

rule "each job has permissions" \
  '.jobs | to_entries[] | select(.value | has("permissions") | not) | .key' \
  "a job with no permissions key gets the repository default token"

rule "each job has timeout-minutes" \
  '.jobs | to_entries[] | select((.value | has("timeout-minutes") | not) and (.value | has("uses") | not)) | .key' \
  "with no timeout, a hung step holds the runner for 6 hours"

rule "each action is pinned by commit" \
  '[.jobs[] | (.uses // empty), (.steps[]? | .uses // empty)] | .[]
    | select(test("^\\./") | not)
    | select(test("^docker://[^@]+@sha256:[0-9a-f]{64}$") | not)
    | select(test("^[^@]+@[0-9a-f]{40}$") | not)' \
  "a tag can move; resolve one with: gh api repos/OWNER/REPO/git/ref/tags/TAG --jq .object.sha"

rule "each checkout keeps no token, unless its job has contents: write" \
  '.jobs | to_entries[] | .key as $j
    | select(((.value.permissions // {}) | if type == "object" then .contents else . end) as $c
      | ($c != "write" and $c != "write-all"))
    | .value.steps[]? | select((.uses // "") | startswith("actions/checkout@"))
    | select(((.with // {})["persist-credentials"]) != false)
    | "\($j): \(.name // "checkout")"' \
  "set persist-credentials: false; a job that pushes has contents: write"

rule "no untrusted value is expanded inside a run: block" \
  '.jobs | to_entries[] | .key as $j | .value.steps[]? | select(.run != null)
    | (.run | tostring | [match("\\$\\{\\{[^}]*(inputs\\.|matrix\\.|needs\\.|github\\.event\\.|github\\.head_ref)[^}]*\\}\\}"; "g") | .string]) as $m
    | select($m | length > 0) | "\($j): \($m | join(" "))"' \
  "a value expanded there becomes shell code; pass it through env:"

rule "no pull_request_target trigger, and workflow_run only in bot-merge.yml" \
  '(input_filename | split("/") | last | rtrimstr(".json")) as $file
    | .on | (if type == "object" then keys[] elif type == "array" then .[] else . end)
    | select(. == "pull_request_target" or (. == "workflow_run" and $file != "bot-merge.yml"))' \
  "these triggers run with a write token after code from elsewhere"

rule "runs-on is a pinned label, never *-latest" \
  '.jobs | to_entries[] | .key as $j | (.value["runs-on"] // empty)
    | (if type == "array" then .[] elif type == "object" then ((.labels // empty) | if type == "array" then .[] else . end) else . end)
    | tostring | select(test("-latest$")) | "\($j): \(.)"' \
  "a *-latest label moves to a new image with no commit here; name the version"

rule "each run: block runs under shell: bash" \
  'if (.defaults.run.shell // "") == "bash" then empty else
    .jobs | to_entries[] | .key as $j | select((.value.defaults.run.shell // "") != "bash")
    | .value.steps[]? | select(.run != null and (.shell // "") == "")
    | "\($j): \(.name // .id // "a step")" end' \
  "with no shell named, a run: block runs without pipefail"

rule "a job that writes never runs under a group that cancels in progress" \
  '((.concurrency // null) | if type == "object" then (.["cancel-in-progress"] // false) else false end) as $wc
    | .jobs | to_entries[] | select(.value | writes)
    | ((.value.concurrency // null) | if type == "object" then (.["cancel-in-progress"] // false) else false end) as $jc
    | select($wc != false or $jc != false)
    | "\(.key): cancel-in-progress workflow \($wc), job \($jc)"' \
  "a publish cut off part way leaves a half-written result; set cancel-in-progress: false"

rule "upload-artifact overwrites, and the Pages artifact name holds github.run_attempt" \
  '.jobs | to_entries[] | .key as $j | .value.steps[]?
    | ((.uses // "") | split("@")[0]) as $a
    | if $a == "actions/upload-artifact" and ((.with // {}).overwrite != true) then "\($j): upload-artifact with no overwrite: true"
      elif $a == "actions/upload-pages-artifact" and (((.with // {}).name // "") | test("github\\.run_attempt") | not) then "\($j): Pages artifact name \((.with // {}).name // "")"
      else empty end' \
  "a re-run uploads each artifact again into the same run"

rule "a watch job has no needs, and nothing needs it" \
  '.jobs | to_entries as $all
    | ($all[] | select((.key | startswith("watch")) and (.value.needs != null)) | "\(.key) has needs"),
      ($all[] | .key as $j | (.value.needs // []) | (if type == "string" then [.] else . end)[]
        | select(startswith("watch")) | "\($j) needs \(.)")' \
  "a watch job must run when the jobs it watches fail"

# One jq program for all rules: each fault line is "<rule index><TAB><text>".
# writes: the job asks for packages, contents or pages write.
program='def writes: (.permissions // {}) as $p
  | if ($p | type) == "string" then ($p == "write-all")
    else ([$p.packages, $p.contents, $p.pages] | any(. == "write")) end;
. as $root | '
for i in "${!R_PROG[@]}"; do
  [ "$i" -eq 0 ] || program="$program, "
  program="$program(\$root | ${R_PROG[$i]} | \"$i\\t\\(.)\")"
done

for wf in "${workflows[@]}"; do
  base="$(basename "$wf")"
  json="$work/$base.json"
  rc=0
  yaml_json "$wf" > "$json" 2> "$work/$base.err" || rc=$?
  if [ "$rc" -ne 0 ] || ! jq -e 'type == "object"' "$json" > "$work/type.out"; then
    fail "$wf: reads as YAML" "yq exited $rc: $(tr '\n' ' ' < "$work/$base.err")" "reproduce: yq . $wf"
    continue
  fi
  rc=0
  out="$(jq -r "$program" "$json" 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "$wf: the workflow rules run" "jq exited $rc: $out" "reproduce: this file's rules, then yq -o=json . $wf | jq -r RULE"
    continue
  fi
  hits=()
  while IFS=$'\t' read -r i text; do
    [ -n "$i" ] || continue
    hits[i]="${hits[i]:-}$text; "
  done <<< "$out"
  for i in "${!R_DESC[@]}"; do
    if [ -z "${hits[i]:-}" ]; then
      ok "$wf: ${R_DESC[$i]}"
    else
      fail "$wf: ${R_DESC[$i]}" "${hits[i]}" "${R_WHY[$i]}" \
        "reproduce: yq -o=json . $wf | jq -r '$(printf '%s' "${R_PROG[$i]}" | tr -s '\n ' '  ')'"
    fi
  done

  # Two rules read the text: an if: that YAML reads as a tag, and the
  # version comment of a pinned action.
  bad="$(awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*if:[[:space:]]*!/ { print "if " FILENAME ":" NR ": " $0 }
    /^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*[^#[:space:]]+@[0-9a-f]{40}/ {
      if ($0 !~ /#[[:space:]]*v?[0-9]/) print "uses " FILENAME ":" NR ": " $0
    }' "$wf")"
  bad_if=""
  bad_uses=""
  while IFS= read -r line; do
    case "$line" in
      'if '*) bad_if="$bad_if${line#if }; " ;;
      'uses '*) bad_uses="$bad_uses${line#uses }; " ;;
    esac
  done <<< "$bad"
  if [ -z "$bad_if" ]; then
    ok "$wf: no unquoted if: !"
  else
    fail "$wf: no unquoted if: !" "$bad_if" "YAML reads !x as a tag; write if: \${{ !x }}" "reproduce: grep -n 'if: !' $wf"
  fi
  if [ -z "$bad_uses" ]; then
    ok "$wf: each pinned action names its version in a comment"
  else
    fail "$wf: each pinned action names its version in a comment" "$bad_uses" \
      "write: uses: owner/repo@<sha> # v1.2.3" "reproduce: grep -n 'uses:' $wf"
  fi
done

#---------------------------------------------------------------------------#
# Nothing deletes a published tag, version or manifest.
#---------------------------------------------------------------------------#
deleters=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  hits="$(awk '
    /^[[:space:]]*#/ { next }
    /delete-package-versions/ || (/DELETE/ && /(packages\/|\/versions|\/manifests\/)/) || /(crane|regctl|skopeo)[^#]*[[:space:]]delete/ || /oras[^#]*(manifest|blob)[[:space:]]+delete/ {
      print FILENAME ":" NR ": " $0
    }' "$f")"
  [ -z "$hits" ] || deleters="$deleters$hits;"
done <<< "$(find scripts .github/workflows -type f | sort)"
if [ -z "$deleters" ]; then
  ok "no script or workflow deletes a package version or a manifest"
else
  fail "no script or workflow deletes a package version or a manifest" "$deleters" \
    "a published tag or version is never deleted" "reproduce: grep -rnE 'DELETE|delete' scripts .github/workflows"
fi

#---------------------------------------------------------------------------#
# ci.yml
#---------------------------------------------------------------------------#
ci=.github/workflows/ci.yml
cij="$work/ci.yml.json"
if [ ! -s "$cij" ]; then
  fail "$ci reads as YAML" "the ci.yml checks need it" "reproduce: yq . $ci"
  summary
  exit 1
fi

#---------------------------------------------------------------------------#
# The concurrency group of ci.yml, evaluated for each kind of run. A group
# holds one pending run, and a newer run in the group cancels it.
#---------------------------------------------------------------------------#
if need_tool python3; then
  cat > "$work/expr.py" << 'EOF'
# Evaluate a GitHub Actions template ("text ${{ expr }} text") for each run
# in a JSON list of {"name", "ctx": {"github.x": value}}. Print
# "name<TAB>value" per run. Knows literals, github.* contexts, ==, !=, !,
# &&, ||, parentheses and format(). Any other token stops with a message.
import json
import re
import sys

TOKEN = re.compile(r"\s*(?:('(?:[^']|'')*')|(\d+)|([A-Za-z_][A-Za-z0-9_.-]*)|(==|!=|&&|\|\||!|\(|\)|,))")


def text(v):
    if v is None:
        return ""
    if v is True:
        return "true"
    if v is False:
        return "false"
    return str(v)


def truthy(v):
    return v not in (None, False, 0, "")


def fmt(f, *args):
    return re.sub(r"\{(\d+)\}", lambda m: text(args[int(m.group(1))]), f)


def expr(src, ctx):
    src = src.strip()
    toks = []
    pos = 0
    while pos < len(src):
        m = TOKEN.match(src, pos)
        if not m or m.end() == pos:
            sys.exit("expr.py: cannot read the expression at: %s" % src[pos:])
        pos = m.end()
        s, n, name, op = m.groups()
        if s is not None:
            toks.append(("v", s[1:-1].replace("''", "'")))
        elif n is not None:
            toks.append(("v", int(n)))
        elif name is not None:
            if name in ("true", "false", "null"):
                toks.append(("v", {"true": True, "false": False, "null": None}[name]))
            elif name == "format":
                toks.append(("f", name))
            elif not name.startswith("github."):
                sys.exit("expr.py: unknown name %s" % name)
            else:
                toks.append(("v", ctx.get(name)))
        else:
            toks.append(("o", op))
    i = [0]

    def peek():
        return toks[i[0]] if i[0] < len(toks) else ("end", None)

    def take(want=None):
        t = peek()
        if want is not None and t != ("o", want):
            sys.exit("expr.py: expected %s, found %r in %s" % (want, t, src))
        i[0] += 1
        return t

    def p_or():
        v = p_and()
        while peek() == ("o", "||"):
            take()
            r = p_and()
            v = v if truthy(v) else r
        return v

    def p_and():
        v = p_eq()
        while peek() == ("o", "&&"):
            take()
            r = p_eq()
            v = r if truthy(v) else v
        return v

    def p_eq():
        v = p_not()
        while peek() in (("o", "=="), ("o", "!=")):
            op = take()[1]
            r = p_not()
            same = (v.lower() == r.lower()) if isinstance(v, str) and isinstance(r, str) else v == r
            v = same if op == "==" else not same
        return v

    def p_not():
        if peek() == ("o", "!"):
            take()
            return not truthy(p_not())
        return p_primary()

    def p_primary():
        t = take()
        if t == ("o", "("):
            v = p_or()
            take(")")
            return v
        if t[0] == "f":
            take("(")
            args = [p_or()]
            while peek() == ("o", ","):
                take()
                args.append(p_or())
            take(")")
            return fmt(*args)
        if t[0] == "v":
            return t[1]
        sys.exit("expr.py: unexpected %r in %s" % (t, src))

    v = p_or()
    if peek() != ("end", None):
        sys.exit("expr.py: unread tokens in %s" % src)
    return v


def template(t, ctx):
    if not isinstance(t, str):
        return text(t)
    out, pos = "", 0
    for m in re.finditer(r"\$\{\{(.*?)\}\}", t):
        out += t[pos:m.start()] + text(expr(m.group(1), ctx))
        pos = m.end()
    return out + t[pos:]


tpl = json.loads(sys.argv[1])
for run in json.loads(sys.argv[2]):
    print("%s\t%s" % (run["name"], template(tpl, run["ctx"])))
EOF
  runs='[
    {"name": "push1", "ctx": {"github.event_name": "push", "github.ref": "refs/heads/main", "github.run_id": 101}},
    {"name": "push2", "ctx": {"github.event_name": "push", "github.ref": "refs/heads/main", "github.run_id": 102}},
    {"name": "dispatch", "ctx": {"github.event_name": "workflow_dispatch", "github.ref": "refs/heads/main", "github.run_id": 103}},
    {"name": "push7", "ctx": {"github.event_name": "push", "github.ref": "refs/heads/main", "github.run_id": 7}},
    {"name": "pr7a", "ctx": {"github.event_name": "pull_request", "github.event.pull_request.number": 7, "github.ref": "refs/pull/7/merge", "github.run_id": 201}},
    {"name": "pr7b", "ctx": {"github.event_name": "pull_request", "github.event.pull_request.number": 7, "github.ref": "refs/pull/7/merge", "github.run_id": 202}},
    {"name": "pr8", "ctx": {"github.event_name": "pull_request", "github.event.pull_request.number": 8, "github.ref": "refs/pull/8/merge", "github.run_id": 203}}]'
  group_tpl="$(jq -c '.concurrency.group // ""' "$cij")"
  cancel_tpl="$(jq -c '.concurrency["cancel-in-progress"] // false' "$cij")"
  rc=0
  python3 -I "$work/expr.py" "$group_tpl" "$runs" > "$work/groups.tsv" 2> "$work/expr.err" || rc=$?
  python3 -I "$work/expr.py" "$cancel_tpl" "$runs" > "$work/cancels.tsv" 2>> "$work/expr.err" || rc=$?
  RC="evaluate the concurrency block of $ci for each kind of run (this file's expr.py)"
  if [ "$rc" -ne 0 ] || [ "$group_tpl" = '""' ]; then
    fail "$ci: the concurrency group and cancel-in-progress evaluate" \
      "group $group_tpl, cancel-in-progress $cancel_tpl" "$(tr '\n' ' ' < "$work/expr.err")" \
      "reproduce: yq .concurrency $ci"
  else
    g() { awk -F '\t' -v n="$1" '$1 == n { print $2 }' "$work/groups.tsv"; }
    c() { awk -F '\t' -v n="$1" '$1 == n { print $2 }' "$work/cancels.tsv"; }
    if [ "$(g push1)" != "$(g push2)" ] && [ "$(g push1)" != "$(g dispatch)" ] && [ "$(g push2)" != "$(g dispatch)" ]; then
      ok "$ci: two pushes to main and a dispatch get three concurrency groups"
    else
      fail "$ci: two pushes to main and a dispatch get three concurrency groups" \
        "push 101: '$(g push1)', push 102: '$(g push2)', dispatch 103: '$(g dispatch)'" \
        "a newer run in a group cancels the pending one, so a commit gets no verdict" "reproduce: $RC"
    fi
    check_eq "$ci: a run on main never cancels a run in progress" "false false" "$(c push1) $(c dispatch)" "$RC"
    if [ "$(g pr7a)" = "$(g pr7b)" ] && [ "$(c pr7a)" = true ]; then
      ok "$ci: a newer push to a pull request cancels the run of the older one"
    else
      fail "$ci: a newer push to a pull request cancels the run of the older one" \
        "PR 7 run 201: '$(g pr7a)', run 202: '$(g pr7b)', cancel-in-progress '$(c pr7a)'" "reproduce: $RC"
    fi
    if [ "$(g pr7a)" != "$(g push7)" ] && [ "$(g pr7a)" != "$(g pr8)" ]; then
      ok "$ci: the group of a pull request is never the group of another run"
    else
      fail "$ci: the group of a pull request is never the group of another run" \
        "PR 7: '$(g pr7a)', push with run id 7: '$(g push7)', PR 8: '$(g pr8)'" "reproduce: $RC"
    fi
  fi
fi

#---------------------------------------------------------------------------#
# The check job of ci.yml: what it needs, and its verdict.
#---------------------------------------------------------------------------#
check_id="$(jq -r '.jobs | to_entries[] | select(.value.name == "Static suite and linters") | .key' "$cij")"
if [ -z "$check_id" ]; then
  fail "$ci: a job is named Static suite and linters" "jobs: $(jq -r '[.jobs | keys[]] | join(" ")' "$cij")" \
    "reproduce: yq '.jobs[].name' $ci"
else
  needs="$(jq -r --arg j "$check_id" '.jobs[$j].needs // [] | if type == "string" then [.] else . end | sort | join(" ")' "$cij")"
  missing="$(jq -r --arg j "$check_id" '(.jobs[$j].needs // [] | if type == "string" then [.] else . end) as $n
    | ["static", "lint", "image"] - $n | join(" ")' "$cij")"
  check_eq "$ci: $check_id needs static, lint and image" "" "$missing" "yq '.jobs.$check_id.needs' $ci"
  has_network="$(jq -r --arg j "$check_id" '.jobs[$j].needs // [] | if type == "string" then [.] else . end | index("network") != null' "$cij")"
  check_eq "$ci: $check_id does not need network, so a mirror outage blocks no merge" false "$has_network" \
    "yq '.jobs.$check_id.needs' $ci"
  cond="$(jq -r --arg j "$check_id" '.jobs[$j].if // ""' "$cij")"
  case "$cond" in
    *'always()'*) ok "$ci: $check_id runs when a needed job fails" ;;
    *) fail "$ci: $check_id runs when a needed job fails" "if: '$cond'" \
      "without always(), a failed need skips the check, and a skipped required check reads as passed" \
      "reproduce: yq '.jobs.$check_id.if' $ci" ;;
  esac

  # The verdict step: the jobs it reads are the jobs it needs.
  jq -r --arg j "$check_id" '.jobs[$j].steps[] | select(.env.RESULTS != null) | .run' "$cij" > "$work/verdict.sh"
  results_tpl="$(jq -r --arg j "$check_id" '.jobs[$j].steps[] | select(.env.RESULTS != null) | .env.RESULTS' "$cij")"
  may_skip="$(jq -r --arg j "$check_id" '.jobs[$j].steps[] | select(.env.RESULTS != null) | .env.MAY_SKIP // ""' "$cij")"
  read_jobs="$(printf '%s\n' "$results_tpl" | awk '{
      s = $0
      while (match(s, /[A-Za-z0-9_-]+=[$][{][{][[:space:]]*needs[.][A-Za-z0-9_-]+[.]result[[:space:]]*[}][}]/)) {
        t = substr(s, RSTART, RLENGTH)
        s = substr(s, RSTART + RLENGTH)
        n = t; sub(/=.*/, "", n)
        j = t; sub(/.*needs[.]/, "", j); sub(/[.]result.*/, "", j)
        if (n == j) print j
      }
    }' | sort | tr '\n' ' ' | sed 's/ $//')"
  check_eq "$ci: the verdict reads the result of each needed job, as NAME=\${{ needs.NAME.result }}" \
    "$needs" "$read_jobs" "yq '.jobs.$check_id.steps[].env.RESULTS' $ci"

  # verdict RESULTS: run the step as GitHub runs it; print its exit status.
  verdict() {
    local rc=0
    RESULTS="$1" MAY_SKIP="$may_skip" bash --noprofile --norc -eo pipefail "$work/verdict.sh" > "$work/verdict.out" 2>&1 || rc=$?
    printf '%s\n' "$rc"
  }
  all_ok=""
  for j in $needs; do all_ok="$all_ok $j=success"; done
  RV="yq '.jobs.$check_id.steps[0].run' $ci > v.sh; RESULTS='...' MAY_SKIP='$may_skip' bash -eo pipefail v.sh"
  check_eq "$ci: the verdict passes when every needed job passed" 0 "$(verdict "$all_ok")" "$RV"
  check_eq "$ci: the verdict passes when the image job was skipped" 0 \
    "$(verdict "$(printf '%s' "$all_ok" | sed 's/image=success/image=skipped/')")" "$RV"
  for j in $needs; do
    check_eq "$ci: the verdict fails when $j failed" 1 \
      "$(verdict "$(printf '%s' "$all_ok" | sed "s/$j=success/$j=failure/")")" "$RV"
    check_eq "$ci: the verdict fails when $j was cancelled" 1 \
      "$(verdict "$(printf '%s' "$all_ok" | sed "s/$j=success/$j=cancelled/")")" "$RV"
  done
  check_eq "$ci: the verdict fails when static was skipped" 1 \
    "$(verdict "$(printf '%s' "$all_ok" | sed 's/static=success/static=skipped/')")" "$RV"
  check_eq "$ci: the verdict fails when it reads no result" 1 "$(verdict "")" "$RV"
fi

#---------------------------------------------------------------------------#
# What each job of ci.yml runs. A step is found by the command in its run:
# block, so a step can change its name.
#---------------------------------------------------------------------------#
# step_of JOB REGEX: the index of the first step of JOB whose run: block
# matches REGEX, or -1.
step_of() {
  jq -r --arg j "$1" --arg re "$2" '[.jobs[$j].steps[]? | (.run // "") | tostring | test($re)] | index(true) // -1' "$cij"
}
# runs JOB REGEX...: "yes" when each REGEX matches a run: block of JOB, else
# the regexes that match none.
runs() {
  local j="$1" re out=""
  shift
  for re in "$@"; do
    [ "$(step_of "$j" "$re")" -ge 0 ] || out="$out [$re]"
  done
  printf '%s\n' "${out:-yes}"
}
RJ="yq '.jobs.JOB.steps[].run' $ci"
for j in static lint network changes image; do
  t="$(step_of "$j" 'scripts/install-tools ')"
  k="$(jq -r --arg j "$j" '[.jobs[$j].steps[]? | select((.uses // "") | startswith("actions/cache@")) | .with.key // ""
    | select(contains("hashFiles('"'"'scripts/install-tools'"'"')"))] | length' "$cij")"
  if [ "$t" -ge 0 ] && [ "$k" -ge 1 ]; then
    ok "$ci: $j installs its tools with scripts/install-tools, cached under the hash of the script"
  else
    fail "$ci: $j installs its tools with scripts/install-tools, cached under the hash of the script" \
      "install step index $t, cache steps keyed on the script $k" "reproduce: ${RJ/JOB/$j}"
  fi
done
check_eq "$ci: TESTS_REQUIRE_TOOLS is 1 for every job" 1 \
  "$(jq -r '.env.TESTS_REQUIRE_TOOLS // "" | tostring' "$cij")" "yq .env $ci"
check_eq "$ci: static runs tests/run.sh static" yes \
  "$(runs static 'tests/run[.]sh( -j ?[0-9]+)? static( |$)')" "${RJ/JOB/static}"
check_eq "$ci: network runs tests/run.sh network" yes \
  "$(runs network 'tests/run[.]sh( -j ?[0-9]+)? network( |$)')" "${RJ/JOB/network}"
check_eq "$ci: lint runs shellcheck for bash and sh, actionlint and py_compile" yes \
  "$(runs lint 'shellcheck [^\n]*--shell=bash' 'shellcheck [^\n]*--shell=sh' '(^|\n) *actionlint "' 'python3 -I [^\n]*-m py_compile')" \
  "${RJ/JOB/lint}"

# The image job: matrix from the changes job, then the steps in build order.
img_needs="$(jq -r '.jobs.image.needs // [] | if type == "string" then [.] else . end | index("changes") != null' "$cij")"
img_matrix="$(jq -r '.jobs.image.strategy.matrix.include // "" | tostring' "$cij")"
img_if="$(jq -r '.jobs.image.if // ""' "$cij")"
case "$img_needs|$img_matrix|$img_if" in
  'true|${{ fromJSON(needs.changes.outputs.matrix) }}|'*needs.changes.outputs.build*) ok "$ci: image builds the matrix of the changes job, and only when it says build" ;;
  *) fail "$ci: image builds the matrix of the changes job, and only when it says build" \
    "needs changes: $img_needs; matrix.include: '$img_matrix'; if: '$img_if'" "reproduce: yq '.jobs.image' $ci" ;;
esac
order=()
for re in 'scripts/binfmt-register "\$ARCH"' 'scripts/pick-base-image' 'docker buildx build [^\n]*--load' 'scripts/gen-evidence ' 'tests/run[.]sh( -j ?[0-9]+)? image'; do
  order+=("$(step_of image "$re")")
done
r=ordered
prev=-1
for i in "${order[@]}"; do
  if [ "$i" -lt 0 ]; then
    r="a step is missing, step indexes: ${order[*]}"
    break
  elif [ "$i" -lt "$prev" ]; then
    r="out of order, step indexes: ${order[*]}"
  fi
  prev="$i"
done
check_eq "$ci: image registers the emulator, picks the base image, builds with --load, writes the evidence, then runs the image suite" \
  ordered "$r" "${RJ/JOB/image}"

#---------------------------------------------------------------------------#
# tests/policy/image-inputs: each line is a path; it covers each COPY source
# of the Dockerfile and each script the image job runs.
#---------------------------------------------------------------------------#
inputs_file=tests/policy/image-inputs
inputs=()
while IFS= read -r line; do
  case "$line" in '' | '#'*) continue ;; esac
  inputs+=("$line")
done < "$inputs_file"
covered() {
  local p
  for p in "${inputs[@]}"; do
    case "$p" in
      */) [ "${1#"$p"}" = "$1" ] || return 0 ;;
      *) [ "$1" != "$p" ] || return 0 ;;
    esac
  done
  return 1
}
absent=""
for p in "${inputs[@]}"; do
  case "$p" in
    */) [ -d "$p" ] || absent="$absent $p" ;;
    *) [ -f "$p" ] || absent="$absent $p" ;;
  esac
done
check_eq "$inputs_file: each line names a path in the tree" "" "$absent" "ls -d \$(grep -v '^#' $inputs_file)"

uncovered=""
while IFS= read -r src; do
  [ -n "$src" ] || continue
  src="${src%%\$*}"
  [ -n "$src" ] || continue
  covered "$src" || uncovered="$uncovered $src"
done <<< "$(awk '
  toupper($1) == "COPY" || toupper($1) == "ADD" {
    n = 0
    for (i = 2; i <= NF; i++) { if ($i ~ /^--from=/) next; if ($i !~ /^--/) a[++n] = $i }
    for (i = 1; i < n; i++) print a[i]
  }' Dockerfile)"
check_eq "$inputs_file covers each COPY source of the Dockerfile" "" "$uncovered" "grep -n '^COPY' Dockerfile"

uncovered=""
while IFS= read -r p; do
  [ -n "$p" ] || continue
  covered "$p" || uncovered="$uncovered $p"
done <<< "$(jq -r '.jobs.image.steps[]?.run // empty' "$cij" | awk '{
    s = $0
    while (match(s, /(scripts|tests)[/][A-Za-z0-9_.\/-]+/)) {
      print substr(s, RSTART, RLENGTH)
      s = substr(s, RSTART + RLENGTH)
    }
  }' | sort -u)"
check_eq "$inputs_file covers each script the image job runs" "" "$uncovered" "yq '.jobs.image.steps[].run' $ci"


#---------------------------------------------------------------------------#
# The changes job of ci.yml, run against fixture commits. A stand-in for
# scripts/ports gives list and matrix from the port names, so the step runs
# in milliseconds; the step only reads .arch of the matrix.
#---------------------------------------------------------------------------#
if need_tool git; then
  repo="$work/repo"
  mkdir -p "$repo/scripts" "$repo/ports" "$repo/tests/policy"
  mapfile -t ports < <(scripts/ports list)
  for a in "${ports[@]}"; do
    printf 'arch = %s\n' "$a" > "$repo/ports/$a.conf"
  done
  cat > "$repo/scripts/ports" << 'EOF'
#!/usr/bin/env bash
# A stand-in for scripts/ports: list, and matrix with .arch only.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
list() { for f in "$root"/ports/*.conf; do basename "$f" .conf; done | LC_ALL=C sort; }
case "$1" in
  list) list ;;
  matrix)
    shift
    [ "$#" -gt 0 ] || set -- $(list)
    out=""
    for a in "$@"; do out="${out:+$out,}{\"arch\":\"$a\"}"; done
    printf '[%s]\n' "$out"
    ;;
  *) echo "stand-in scripts/ports: no command $1" >&2; exit 2 ;;
esac
EOF
  chmod 0755 "$repo/scripts/ports"
  cp "$inputs_file" "$repo/tests/policy/"
  printf 'readme\n' > "$repo/README.md"
  jq -r '.jobs.changes.steps[] | select(.id == "decide") | .run' "$cij" > "$work/decide.sh"
  gitf() { git -C "$repo" -c user.name=t -c user.email=t@t.invalid -c commit.gpgsign=false "$@"; }
  gitf init -q
  gitf add -A
  gitf commit -q -m base
  base="$(gitf rev-parse HEAD)"
  first="${ports[0]}"
  second="${ports[1]}"
  all="${ports[*]}"

  # decide EVENT BASE: run the step in the fixture repo. Print
  # "<build> <arch of each matrix entry>", or "exit N: <output>".
  decide() {
    local rc=0
    : > "$work/out"
    (cd "$repo" && EVENT="$1" BASE="$2" GITHUB_OUTPUT="$work/out" RUNNER_TEMP="$work" \
      bash --noprofile --norc -eo pipefail "$work/decide.sh") > "$work/decide.log" 2>&1 || rc=$?
    if [ "$rc" -ne 0 ]; then
      printf 'exit %s: %s\n' "$rc" "$(tr '\n' ' ' < "$work/decide.log")"
      return 0
    fi
    printf '%s %s\n' "$(awk -F= '$1 == "build" { print $2 }' "$work/out")" \
      "$(awk '/^matrix=/ { sub(/^matrix=/, ""); print }' "$work/out" | jq -r '[.[].arch] | join(" ")')"
  }
  # change PATH...: a new commit on top of base that touches each PATH.
  change() {
    local p
    gitf checkout -q --detach "$base"
    for p in "$@"; do
      mkdir -p "$repo/$(dirname "$p")"
      printf 'changed\n' >> "$repo/$p"
    done
    gitf add -A
    gitf commit -q -m change
  }
  RD="yq '.jobs.changes.steps[] | select(.id == \"decide\") | .run' $ci > d.sh; EVENT=pull_request BASE=<sha> GITHUB_OUTPUT=o RUNNER_TEMP=/tmp bash -eo pipefail d.sh"

  change README.md
  check_eq "changes: a diff with no image input builds nothing, with an empty matrix" "false " \
    "$(decide pull_request "$base")" "$RD"
  change "rootfs/$first/etc/x"
  check_eq "changes: a change under rootfs/$first/ builds $first only" "true $first" "$(decide pull_request "$base")" "$RD"
  change "mirrors/$second.anchors" "ports/$first.conf"
  check_eq "changes: changes to two ports build those two, in port order" "true $first $second" \
    "$(decide push "$base")" "$RD"
  change Dockerfile "rootfs/$first/etc/x"
  check_eq "changes: a shared input builds every port" "true $all" "$(decide pull_request "$base")" "$RD"
  change README.md
  check_eq "changes: a dispatch builds every port" "true $all" "$(decide workflow_dispatch "")" "$RD"
  check_eq "changes: a push with no base builds every port" "true $all" \
    "$(decide push 0000000000000000000000000000000000000000)" "$RD"
  check_eq "changes: a base that is not in the clone builds every port" "true $all" \
    "$(decide pull_request 1111111111111111111111111111111111111111)" "$RD"

  # move FROM TO: a commit on top of base that adds FROM, then a commit that
  # moves FROM to TO with git mv. Sets from_base to the first commit.
  move() {
    gitf checkout -q --detach "$base"
    mkdir -p "$repo/$(dirname "$1")" "$repo/$(dirname "$2")"
    printf 'a file that moves\n' > "$repo/$1"
    gitf add -A
    gitf commit -q -m add
    from_base="$(gitf rev-parse HEAD)"
    gitf mv "$1" "$2"
    gitf commit -q -m move
  }
  move "rootfs/$first/etc/hook.conf" notes/hook.conf
  check_eq "changes: a file moved from rootfs/$first/ to a path that is not an input builds $first" \
    "true $first" "$(decide pull_request "$from_base")" "$RD"
  move "rootfs/any/etc/shared.conf" "rootfs/$second/etc/shared.conf"
  check_eq "changes: a file moved out of a shared input builds every port" "true $all" \
    "$(decide pull_request "$from_base")" "$RD"
  move "rootfs/$first/etc/hook.conf" "rootfs/$second/etc/hook.conf"
  check_eq "changes: a file moved from one port to another builds both" "true $first $second" \
    "$(decide pull_request "$from_base")" "$RD"
  move "rootfs/$first/etc/ü.conf" notes/u.conf
  check_eq "changes: a moved path with a non-ASCII name still counts" "true $first" \
    "$(decide pull_request "$from_base")" "$RD"
fi

summary
