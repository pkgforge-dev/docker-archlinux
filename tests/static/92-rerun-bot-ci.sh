#!/usr/bin/env bash
#
# scripts/rerun-bot-ci re-runs the failed CI of an open Renovate pull request,
# at most RERUN_MAX times for one head commit, and nothing else.
#
# A stand-in for gh (tests/fixtures/issues/fake-gh) answers the pull request
# list and the CI runs of each head commit, and records each re-run. No
# network.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

if ! need_tool jq; then
  summary
  exit $?
fi

work="$(work_dir)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
cp "$REPO_ROOT/tests/fixtures/issues/fake-gh" "$work/bin/gh"
chmod +x "$work/bin/gh"
gh="$work/gh"
mkdir -p "$gh"

# expect DESC WANT GOT REPRODUCE
expect() {
  if [ "$2" = "$3" ]; then
    ok "$1"
  else
    fail "$1" "expected: $2" "got:      $3" "reproduce: $4"
  fi
}

# pr NUMBER BRANCH SHA [REPO]: one open pull request
pr() {
  jq -n --argjson n "$1" --arg b "$2" --arg s "$3" --arg r "${4:-test/repo}" \
    '{number: $n, head: {ref: $b, sha: $s, repo: {full_name: $r}}}'
}

# ci SHA ID:STATUS:CONCLUSION:ATTEMPT ...: the CI runs of one head commit,
# oldest first
ci() {
  local sha="$1" r id status conclusion attempt n=0
  shift
  for r in "$@"; do
    n=$((n + 1))
    IFS=: read -r id status conclusion attempt <<< "$r"
    jq -n --argjson id "$id" --arg st "$status" --arg c "$conclusion" --argjson a "$attempt" --argjson n "$n" \
      '{id: $id, status: $st, conclusion: (if $c == "-" then null else $c end), run_attempt: $a,
        created_at: "2026-10-16T0\($n):00:00Z"}'
  done | jq -s '{workflow_runs: .}' > "$gh/runs-ci.yml-$sha.json"
}

{
  pr 1 renovate/a sha1
  pr 2 renovate/b sha2
  pr 3 renovate/c sha3
  pr 4 feature/x sha4
  pr 5 renovate/d sha5 someone/fork
  pr 6 renovate/e sha6
  pr 7 renovate/f sha7
  pr 8 renovate/g sha8
  pr 9 renovate/h sha9
  pr 10 renovate/i sha10
} | jq -s . > "$gh/pulls.json"
ci sha1 101:completed:failure:1
ci sha2 102:completed:failure:4
ci sha3 103:completed:success:1
ci sha4 104:completed:failure:1
ci sha5 105:completed:failure:1
ci sha6 106:in_progress:-:1
printf '{"workflow_runs":[]}\n' > "$gh/runs-ci.yml-sha7.json"
ci sha8 181:completed:failure:2 108:completed:failure:1
ci sha9 191:completed:failure:3 109:completed:failure:1
ci sha10 110:completed:cancelled:1

run() {
  local rc=0
  : > "$gh/calls.log"
  PATH="$work/bin:$PATH" FAKE_GH_DIR="$gh" GH_TOKEN=stub GITHUB_REPOSITORY=test/repo \
    "$REPO_ROOT/scripts/rerun-bot-ci" > "$work/out" 2>&1 || rc=$?
  printf '%s %s\n' "$rc" "$(tr '\n' ';' < "$gh/calls.log" | sed 's/;$//')"
}

R="FAKE_GH_DIR=DIR scripts/rerun-bot-ci"

# #1: attempt 1 failed: re-run. #2: 4 attempts: the limit. #3: green.
# #4: not a renovate/ branch. #5: from a fork. #6: busy. #7: no run.
# #8: 2 + 1 attempts, the newest run (108) failed: re-run 108.
# #9: 3 + 1 attempts: the limit. #10: cancelled by a person: left.
expect "only the failed runs of renovate/ branches under the limit are re-run" \
  "0 rerun 101;rerun 108" "$(run)" "$R"

expect "each pull request gets one line, first word: its result" \
  "rerun limit green busy none rerun limit other" \
  "$(awk '$1 ~ /^(rerun|limit|green|busy|none|other)$/ { printf "%s%s", sep, $1; sep = " " }' "$work/out")" \
  "$R"

rc=0
: > "$gh/calls.log"
PATH="$work/bin:$PATH" FAKE_GH_DIR="$gh" GH_TOKEN=stub GITHUB_REPOSITORY=test/repo RERUN_MAX=0 \
  "$REPO_ROOT/scripts/rerun-bot-ci" > "$work/out" 2>&1 || rc=$?
expect "RERUN_MAX=0 re-runs nothing" "0 " "$rc $(tr '\n' ';' < "$gh/calls.log")" "RERUN_MAX=0 $R"

rc=0
: > "$gh/calls.log"
PATH="$work/bin:$PATH" FAKE_GH_DIR="$gh" GH_TOKEN=stub GITHUB_REPOSITORY=test/repo \
  FAKE_GH_FAIL='repos/*/pulls*' "$REPO_ROOT/scripts/rerun-bot-ci" > "$work/out" 2>&1 || rc=$?
expect "a pull request list that cannot be read: exit 1, nothing re-run" "1 " "$rc $(tr '\n' ';' < "$gh/calls.log")" \
  "FAKE_GH_FAIL='repos/*/pulls*' $R"

rc=0
PATH="$work/bin:$PATH" FAKE_GH_DIR="$gh" GH_TOKEN=stub GITHUB_REPOSITORY=test/repo \
  "$REPO_ROOT/scripts/rerun-bot-ci" extra > "$work/out" 2>&1 || rc=$?
expect "an argument is a usage error" 2 "$rc" "$R extra"

summary
