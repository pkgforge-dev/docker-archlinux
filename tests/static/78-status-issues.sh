#!/usr/bin/env bash
#
# The decisions of scripts/check-status-record and scripts/check-status-site,
# against a stand-in for gh (tests/fixtures/status/fake-gh) that records
# each issue scripts/track-issue would open, update or close.
#
#   check-status-record  status-down when the build of status.yml did not
#                        succeed or its record is old; registry-drift from a
#                        fresh record, at parity below 1 in 2 runs in a row
#   check-status-site    status-down when the record on the branch status is
#                        old or missing; pages-stale when the copy on Pages
#                        trails it or does not answer
#
# The Pages copy is a file:// URL, so nothing goes to the network.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

FIX="$REPO_ROOT/tests/fixtures/status"
work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

expect() {
  if [ "$2" = "$3" ]; then
    ok "$1"
  else
    fail "$1" "expected: $2" "got:      $3" "reproduce: $4"
  fi
}

if ! need_tool jq curl; then
  summary
  exit $?
fi

bin="$work/bin"
mkdir -p "$bin"
cp "$FIX/fake-gh" "$bin/gh"
chmod +x "$bin/gh"
NOW="$(jq -n '"2026-10-16T12:00:00Z" | fromdateiso8601')"
PAGES="$work/pages/status.json"
mkdir -p "$work/pages"

# gh_dir NAME [KEY=NUMBER ...]: a fresh FAKE_GH_DIR with an open issue for
# each KEY, as scripts/track-issue writes them with the token of a workflow.
# Sets gh.
gh_dir() {
  local kv
  gh="$work/gh-$1"
  shift
  mkdir -p "$gh"
  : > "$gh/calls.log"
  for kv in "$@"; do
    jq -n --arg k "${kv%%=*}" --argjson n "${kv#*=}" \
      '{number: $n, state: "open", user: {login: "github-actions[bot]"}, labels: [{name: "automation"}],
        body: "<!-- track: \($k) -->\nbody"}'
  done | jq -s . > "$gh/open.json"
}

# record FILE AGE [PARITY DRIFT_RUNS]: a status.json measured AGE seconds
# before NOW
record() {
  jq -n --argjson t "$((NOW - $2))" --argjson p "${3:-1}" --argjson dr "${4:-0}" \
    '{schema: 1, generated: ($t | todate), generated_epoch: $t,
      registries: {parity: $p, drift_runs: $dr,
                   ghcr: {image: "ghcr.io/test-owner/archlinux", tags: 60},
                   hub: {image: "docker.io/test/archlinux", tags: 59},
                   rolling: {differs: ["arm64"]},
                   pinned: {missing: 1, missing_names: ["armv7h-v2026.10.15"]}}}' > "$1"
}

# events: the calls of fake-gh that changed something, on one line
events() {
  tr '\n' ';' < "$gh/calls.log" | sed 's/;$//'
}

# has EVENT: the calls hold EVENT. raised KEY: an open or an update of
# KEY. touched N: any call on issue N.
has() {
  case ";$(events);" in *";$1;"*) echo yes ;; *) echo no ;; esac
}
raised() {
  case ";$(events);" in *";open $1;"* | *";update "*" $1;"*) echo yes ;; *) echo no ;; esac
}
touched() {
  case ";$(events);" in *" $1;"* | *" $1 "*) echo yes ;; *) echo no ;; esac
}

run() {
  local rc=0
  PATH="$bin:$PATH" FAKE_GH_DIR="$gh" GH_TOKEN=stub GITHUB_REPOSITORY=test-owner/docker-archlinux \
    GITHUB_RUN_ID=77 STATUS_NOW="$NOW" STATUS_PAGES_URL="file://$PAGES" \
    "$@" > "$work/out" 2>&1 || rc=$?
  return "$rc"
}

#---------------------------------------------------------------------------#
# check-status-record: the check job of status.yml, after each build
#---------------------------------------------------------------------------#
CR="PATH=<fake-gh>:\$PATH FAKE_GH_DIR=DIR STATUS_NOW=$NOW GITHUB_REPOSITORY=o/n scripts/check-status-record BUILD STATUS_JSON"
REC="$REPO_ROOT/scripts/check-status-record"
record "$work/fresh.json" 1800 1 0

gh_dir failed registry-drift=12
rc=0
run "$REC" failure "$work/fresh.json" || rc=$?
expect "record: a build that failed raises status-down; the fresh record still clears registry-drift" "0 yes yes" \
  "$rc $(raised status-down) $(has 'close 12')" "$CR; $(events)"
if grep -q 'actions/runs/77' "$gh/body-status-down.md"; then
  ok "record: the status-down body names the run"
else
  fail "record: the status-down body names the run" "$(awk 'NR <= 10' "$gh/body-status-down.md")" "reproduce: $CR"
fi

gh_dir ok status-down=11
rc=0
run "$REC" success "$work/fresh.json" || rc=$?
expect "record: a build that succeeded with a fresh record closes status-down" "0 yes no" \
  "$rc $(has 'close 11') $(raised status-down)" "$CR; $(events)"

record "$work/old.json" 14400 0.9 5
gh_dir old status-down=11 registry-drift=12
rc=0
run "$REC" success "$work/old.json" || rc=$?
expect "record: a record 4 h old raises status-down, judges no drift, and fails" "1 yes no" \
  "$rc $(raised status-down) $(touched 12)" "$CR; $(events)"

gh_dir none
rc=0
run "$REC" skipped "$work/no-such.json" || rc=$?
expect "record: a skipped build and no record raise status-down, and fail" "1 yes" "$rc $(raised status-down)" "$CR; $(events)"

record "$work/drift2.json" 600 0.9 2
gh_dir drift2
rc=0
run "$REC" success "$work/drift2.json" || rc=$?
expect "record: parity below 1 in 2 runs in a row raises registry-drift" "0 yes" "$rc $(raised registry-drift)" "$CR; $(events)"
if grep -q 'armv7h-v2026.10.15' "$gh/body-registry-drift.md" && grep -q 'arm64' "$gh/body-registry-drift.md"; then
  ok "record: the registry-drift body names the missing tag and the tag that differs"
else
  fail "record: the registry-drift body names the missing tag and the tag that differs" \
    "$(awk 'NR <= 12' "$gh/body-registry-drift.md")" "reproduce: $CR"
fi

record "$work/drift1.json" 600 0.9 1
gh_dir drift1
rc=0
run "$REC" success "$work/drift1.json" || rc=$?
expect "record: parity below 1 in 1 run raises nothing yet" "0 no" "$rc $(raised registry-drift)" "$CR; $(events)"

record "$work/unknown.json" 600 null 3
gh_dir unknown registry-drift=12
rc=0
run "$REC" success "$work/unknown.json" || rc=$?
expect "record: parity unknown neither raises nor clears registry-drift" "0 no no" \
  "$rc $(raised registry-drift) $(touched 12)" "$CR; $(events)"

gh_dir back registry-drift=12
rc=0
run "$REC" success "$work/fresh.json" || rc=$?
expect "record: parity 1 closes registry-drift" "0 yes" "$rc $(has 'close 12')" "$CR; $(events)"

gh_dir norepo
rc=0
PATH="$bin:$PATH" FAKE_GH_DIR="$gh" STATUS_NOW="$NOW" env -u GITHUB_REPOSITORY "$REC" success "$work/fresh.json" \
  > "$work/out" 2>&1 || rc=$?
expect "record: no GITHUB_REPOSITORY stops the check with exit 1, and touches no issue" "1 " "$rc $(events)" \
  "env -u GITHUB_REPOSITORY scripts/check-status-record success STATUS_JSON"

#---------------------------------------------------------------------------#
# check-status-site: the watchdog, from outside status.yml
#---------------------------------------------------------------------------#
CS="PATH=<fake-gh>:\$PATH FAKE_GH_DIR=DIR STATUS_PAGES_URL=file://PAGES STATUS_NOW=$NOW GITHUB_REPOSITORY=o/n scripts/check-status-site [STATUS_JSON]"
SITE="$REPO_ROOT/scripts/check-status-site"

record "$PAGES" 1800
gh_dir site-ok pages-stale=13
rc=0
run "$SITE" "$work/fresh.json" || rc=$?
expect "site: a fresh record and its copy on Pages close pages-stale, and leave status-down alone" "0 yes no" \
  "$rc $(has 'close 13') $(raised status-down)" "$CS; $(events)"

record "$work/old7.json" 25200
record "$PAGES" 25200
gh_dir site-old
rc=0
run "$SITE" "$work/old7.json" || rc=$?
expect "site: a record 7 h old raises status-down, exit 3" "3 yes" "$rc $(raised status-down)" "$CS; $(events)"

record "$PAGES" $((1800 + 14400))
gh_dir site-behind
rc=0
run "$SITE" "$work/fresh.json" || rc=$?
expect "site: a copy on Pages 4 h behind the branch raises pages-stale, exit 3" "3 yes no" \
  "$rc $(raised pages-stale) $(raised status-down)" "$CS; $(events)"

rm -f "$PAGES"
gh_dir site-gone
rc=0
run "$SITE" "$work/fresh.json" || rc=$?
expect "site: a copy on Pages that does not answer raises pages-stale, exit 3" "3 yes" "$rc $(raised pages-stale)" "$CS; $(events)"

# No argument: the record comes from the branch status through gh api
record "$PAGES" 1800
gh_dir site-api pages-stale=13
record "$gh/status.json" 1800
rc=0
run "$SITE" || rc=$?
expect "site: with no argument the record is read through gh api; fresh, so nothing is raised" "0 no yes" \
  "$rc $(raised status-down) $(has 'close 13')" "$CS; $(events)"

gh_dir site-api-none
rc=0
run "$SITE" || rc=$?
expect "site: with no argument and no status.json on the branch (HTTP 404), status-down is raised, exit 3" "3 yes" \
  "$rc $(raised status-down)" "$CS; $(events)"

gh_dir site-norepo
rc=0
PATH="$bin:$PATH" FAKE_GH_DIR="$gh" STATUS_NOW="$NOW" STATUS_PAGES_URL="file://$PAGES" env -u GITHUB_REPOSITORY \
  "$SITE" "$work/fresh.json" > "$work/out" 2>&1 || rc=$?
expect "site: no GITHUB_REPOSITORY stops the check with exit 1, and touches no issue" "1 " "$rc $(events)" \
  "env -u GITHUB_REPOSITORY scripts/check-status-site STATUS_JSON"

summary
