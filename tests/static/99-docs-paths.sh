#!/usr/bin/env bash
#
# Check the names and paths that files cite.
#
#   - each docs/... and tests/... path cited in a text file exists
#   - no file names the removed history directory
#   - each check in tests/policy/required-checks is the name of one job of
#     ci.yml, with no matrix
#   - bot-merge.yml starts on the workflow name of ci.yml
#   - each workflow that a script or workflow starts with gh workflow run
#     exists and has a workflow_dispatch trigger
#
# The files are the tracked files and the new files git does not ignore.
# tests/fixtures holds data, and tests/policy/vendored names the files of
# other repositories, so neither is read.
#
# ⚠ A cited path is text that starts with docs/ or tests/ after a character
# that cannot be part of a path. A path followed by *, [, <, $, { or ?, or
# with an upper case segment such as SUITE, is a pattern and is not checked.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

cd "$REPO_ROOT"
work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

if ! need_tool git; then
  rc=0
  summary || rc=$?
  exit "$rc"
fi

#---------------------------------------------------------------------------#
# The files to read
#---------------------------------------------------------------------------#
vendored=" "
absent_vendored=""
while IFS= read -r line; do
  case "$line" in '' | '#'*) continue ;; esac
  vendored="$vendored$line "
  [ -f "$line" ] || absent_vendored="$absent_vendored $line"
done < tests/policy/vendored
check_eq "tests/policy/vendored names files in the tree" "" "$absent_vendored" "grep -v '^#' tests/policy/vendored"

rc=0
git ls-files -co --exclude-standard -z > "$work/all" || rc=$?
if [ "$rc" -ne 0 ]; then
  fail "git lists the files of the tree" "git ls-files exited $rc" "reproduce: git ls-files -co --exclude-standard"
  summary
  exit 1
fi
files=()
while IFS= read -r -d '' f; do
  case "$f" in
    tests/fixtures/* | HISTORY[/]*) continue ;;
  esac
  case "$vendored" in
    *" $f "*) continue ;;
  esac
  [ -f "$f" ] || continue
  files+=("$f")
done < "$work/all"
if [ "${#files[@]}" -lt 10 ]; then
  fail "there are files to read" "found ${#files[@]}" "reproduce: git ls-files -co --exclude-standard"
fi

# grep_lines PATTERN OUT: the lines of the text files that match, as
# FILE:LINE:TEXT. grep -I passes over a binary file. Returns 1 on a grep error.
grep_lines() {
  local rc=0
  grep -HnIE "$1" -- "${files[@]}" > "$2" || rc=$?
  if [ "$rc" -gt 1 ]; then
    fail "grep reads the files" "grep exited $rc" "reproduce: git grep -nE '$1'"
    return 1
  fi
}

#---------------------------------------------------------------------------#
# Each cited docs/ and tests/ path exists.
#---------------------------------------------------------------------------#
if grep_lines '(docs|tests)/' "$work/lines"; then
  awk '
    {
      if (!match($0, /^[^:]*:[0-9]+:/)) next
      head = substr($0, 1, RLENGTH - 1)
      text = substr($0, RLENGTH + 1)
      s = text
      off = 0
      while (match(s, /(docs|tests)[\/][A-Za-z0-9_.\/-]*/)) {
        start = off + RSTART
        p = substr(s, RSTART, RLENGTH)
        before = (start > 1) ? substr(text, start - 1, 1) : ""
        after = substr(text, start + RLENGTH, 1)
        off = off + RSTART + RLENGTH - 1
        s = substr(s, RSTART + RLENGTH)
        if (before ~ /[A-Za-z0-9_.\/-]/) continue
        if (after ~ /[*[<${?]/) continue
        sub(/[.-]+$/, "", p)
        n = split(p, seg, "/")
        pattern = 0
        for (i = 1; i <= n; i++) if (seg[i] ~ /^[A-Z][A-Z0-9_]+$/) pattern = 1
        if (pattern) continue
        print head "\t" p
      }
    }' "$work/lines" > "$work/cited"

  missing=""
  count=0
  declare -A seen=()
  while IFS=$'\t' read -r where p; do
    [ -n "$p" ] || continue
    count=$((count + 1))
    if [ -z "${seen[$p]:-}" ]; then
      if [ -e "$p" ]; then seen[$p]=yes; else seen[$p]=no; fi
    fi
    [ "${seen[$p]}" = yes ] || missing="$missing $where:$p"
  done < "$work/cited"
  if [ "$count" -eq 0 ]; then
    fail "the text cites docs/ and tests/ paths" "found none, so this checked nothing" \
      "reproduce: git grep -n 'tests/'"
  elif [ -z "$missing" ]; then
    ok "each of $count cited docs/ and tests/ paths exists"
  else
    fail "each cited docs/ and tests/ path exists" "missing:$missing" \
      "correct the path, or write the file it names" \
      "reproduce: git grep -nE '(docs|tests)/' and ls each path"
  fi
fi

#---------------------------------------------------------------------------#
# No file names the removed history directory. The pattern is written as a
# bracket expression, so this file does not name it.
#---------------------------------------------------------------------------#
if grep_lines 'HISTORY[/]' "$work/history"; then
  if [ ! -s "$work/history" ]; then
    ok "no file names the history directory"
  else
    fail "no file names the history directory" \
      "$(awk -F: '{ printf "%s:%s; ", $1, $2 }' "$work/history")" \
      "it is removed; state the fact in docs/ and remove the reference" \
      "reproduce: git grep -nE 'HISTORY[/]'"
  fi
fi

#---------------------------------------------------------------------------#
# The names that branch protection and bot-merge.yml read.
#---------------------------------------------------------------------------#
ci=.github/workflows/ci.yml
bm=.github/workflows/bot-merge.yml
if need_tool yq jq; then
  rc=0
  yaml_json "$ci" > "$work/ci.json" 2> "$work/ci.err" || rc=$?
  yaml_json "$bm" > "$work/bm.json" 2> "$work/bm.err" || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "ci.yml and bot-merge.yml read as YAML" "$(cat "$work/ci.err" "$work/bm.err" | tr '\n' ' ')" \
      "reproduce: yq . $ci; yq . $bm"
  else
    while IFS= read -r name; do
      case "$name" in '' | '#'*) continue ;; esac
      jobs="$(jq -r --arg n "$name" '[.jobs | to_entries[] | select(.value.name == $n)
        | .key + (if .value.strategy.matrix != null then "(matrix)" else "" end)] | join(" ")' "$work/ci.json")"
      case "$jobs" in
        '' | *' '* | *'(matrix)'*)
          fail "the required check '$name' is the name of one job of $ci, with no matrix" \
            "jobs with that name: '${jobs}'" \
            "branch protection waits for a check of exactly this name; a matrix job adds a suffix" \
            "reproduce: yq '.jobs[].name' $ci"
          ;;
        *) ok "the required check '$name' is the name of job $jobs of $ci" ;;
      esac
    done < tests/policy/required-checks

    ci_name="$(jq -r '.name // ""' "$work/ci.json")"
    listens="$(jq -r --arg n "$ci_name" '(.on.workflow_run.workflows // []) | index($n) != null' "$work/bm.json")"
    if [ -n "$ci_name" ] && [ "$listens" = true ]; then
      ok "bot-merge.yml starts on the workflow name of ci.yml ($ci_name)"
    else
      fail "bot-merge.yml starts on the workflow name of ci.yml" \
        "ci.yml name: '$ci_name'; bot-merge.yml workflow_run workflows: $(jq -c '.on.workflow_run.workflows' "$work/bm.json")" \
        "workflow_run matches the workflow name; a rename stops every merge with no error" \
        "reproduce: yq .name $ci; yq .on.workflow_run $bm"
    fi
  fi

  # Each workflow a script or a workflow starts by file name.
  mapfile -t sources < <(find scripts .github/workflows -type f | sort)
  started="$(awk '
    /^[[:space:]]*#/ { next }
    {
      s = $0
      while (match(s, /gh workflow run [A-Za-z0-9_.-]+[.]ya?ml/)) {
        w = substr(s, RSTART, RLENGTH)
        sub(/^gh workflow run /, "", w)
        print FILENAME "\t" w
        s = substr(s, RSTART + RLENGTH)
      }
    }' "${sources[@]}")"
  n=0
  bad=""
  while IFS=$'\t' read -r from w; do
    [ -n "$w" ] || continue
    n=$((n + 1))
    f=".github/workflows/$w"
    if [ ! -f "$f" ]; then
      bad="$bad $from starts $w, which does not exist;"
      continue
    fi
    rc=0
    has="$(yaml_json "$f" | jq -r '.on | if type == "object" then has("workflow_dispatch") elif type == "array" then index("workflow_dispatch") != null else . == "workflow_dispatch" end')" || rc=$?
    if [ "$rc" -ne 0 ] || [ "$has" != true ]; then
      bad="$bad $from starts $w, which has no workflow_dispatch trigger;"
    fi
  done <<< "$started"
  if [ -z "$bad" ]; then
    ok "each of $n workflows started with gh workflow run exists and has workflow_dispatch"
  else
    fail "each workflow started with gh workflow run exists and has workflow_dispatch" "$bad" \
      "gh workflow run refuses a workflow with no workflow_dispatch trigger" \
      "reproduce: grep -rn 'gh workflow run' scripts .github/workflows"
  fi
fi

summary
