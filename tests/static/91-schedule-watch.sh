#!/usr/bin/env bash
#
# The schedule watch, against a stand-in for gh (tests/fixtures/issues/fake-gh)
# that records each change it would make. No network.
#
#   scripts/watch-schedules        schedules-stopped and failing-<stem>
#   scripts/check-schedules-fired  stopped, failing, passing, mixed, and a
#                                  workflow that GitHub has no record of (404)
#   scripts/dispatch-overdue       starts a workflow only when its newest run
#                                  is older than the limit and no run is busy
#
# The workflows are fixtures (tests/fixtures/91-schedule-watch/workflows) in a
# copy of the scripts, so the check reads them and not the real tree.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

if ! need_tool jq; then
  summary
  exit $?
fi

FIX="$(fixture_dir)"
work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

# A tree with the scripts and the fixture workflows.
tree="$work/tree"
mkdir -p "$tree/scripts" "$tree/.github/workflows" "$work/bin"
for s in watch-schedules keep-schedules-enabled check-schedules-fired cron-tolerance date-age track-issue dispatch-overdue lib.sh; do
  cp "$REPO_ROOT/scripts/$s" "$tree/scripts/$s"
done
cp "$FIX"/workflows/*.yml "$tree/.github/workflows/"
cp "$REPO_ROOT/tests/fixtures/issues/fake-gh" "$work/bin/gh"
chmod +x "$work/bin/gh" "$tree/scripts/"*

TODAY=2026-10-16

# expect DESC WANT GOT REPRODUCE
expect() {
  if [ "$2" = "$3" ]; then
    ok "$1"
  else
    fail "$1" "expected: $2" "got:      $3" "reproduce: $4"
  fi
}

# gh_dir NAME [KEY=NUMBER ...]: a fresh FAKE_GH_DIR, with an open issue for
# each KEY, as scripts/track-issue writes it. Sets gh.
gh_dir() {
  local kv
  gh="$work/gh-$1"
  shift
  mkdir -p "$gh"
  : > "$gh/calls.log"
  for kv in "$@"; do
    jq -n --arg k "${kv%%=*}" --argjson n "${kv#*=}" \
      '{number: $n, user: {login: "github-actions[bot]"}, body: "<!-- track: \($k) -->\nbody", labels: [{name: "automation"}]}'
  done | jq -s . > "$gh/open.json"
  workflows active active active
}

# workflows DAILY WEEKLY PUSH: the states of the fixture workflows. gone.yml
# has a record and no file in the tree.
workflows() {
  jq -n --arg d "$1" --arg w "$2" --arg p "$3" '{workflows: [
    {id: 11, state: $d, path: ".github/workflows/daily.yml"},
    {id: 12, state: $w, path: ".github/workflows/weekly.yml"},
    {id: 13, state: $p, path: ".github/workflows/push.yml"},
    {id: 14, state: "active", path: ".github/workflows/gone.yml"}]}' > "$gh/workflows.json"
}

# runs FILE DATE:CONCLUSION ...: the scheduled runs of FILE, newest first
runs() {
  local f="$1" r
  shift
  for r in "$@"; do
    jq -n --arg d "${r%%:*}" --arg c "${r#*:}" \
      '{event: "schedule", status: "completed", conclusion: $c, created_at: "\($d)T07:41:00Z", html_url: "https://github.test/run/\($d)"}'
  done | jq -s '{workflow_runs: .}' > "$gh/runs-$f.json"
}

events() {
  tr '\n' ';' < "$gh/calls.log" | sed 's/;$//'
}

run_watch() {
  local rc=0
  PATH="$work/bin:$PATH" FAKE_GH_DIR="$gh" GH_TOKEN=stub GITHUB_REPOSITORY=test/repo GITHUB_RUN_ID=77 \
    SCHEDULES_TODAY="$TODAY" "$tree/scripts/watch-schedules" > "$work/out" 2>&1 || rc=$?
  printf '%s\n' "$rc"
}

ENABLED="enable 11;enable 12;enable 13"
W="FAKE_GH_DIR=DIR SCHEDULES_TODAY=$TODAY scripts/watch-schedules"

#---------------------------------------------------------------------------#
# watch-schedules
#---------------------------------------------------------------------------#
gh_dir healthy schedules-stopped=5 failing-daily=6 failing-weekly=7
runs daily.yml 2026-10-16:success 2026-10-15:success 2026-10-14:failure
runs weekly.yml 2026-10-12:success 2026-10-05:success 2026-09-28:success
rc="$(run_watch)"
expect "every schedule fires and passes: exit 0, each open issue closes" \
  "0 $ENABLED;comment 5;close 5;comment 6;close 6;comment 7;close 7" "$rc $(events)" "$W"

gh_dir stopped
runs daily.yml 2026-10-01:success 2026-09-30:success 2026-09-29:success
runs weekly.yml 2026-10-12:success 2026-10-05:success 2026-09-28:success
rc="$(run_watch)"
expect "a daily schedule silent for 15 days: exit 3, schedules-stopped opens" \
  "3 $ENABLED;open schedules-stopped" "$rc $(events)" "$W"

gh_dir failing
runs daily.yml 2026-10-16:success 2026-10-15:success 2026-10-14:success
runs weekly.yml 2026-10-12:failure 2026-10-05:failure 2026-09-28:timed_out
rc="$(run_watch)"
expect "3 failed scheduled runs in a row: failing-weekly opens, and the watch passes" \
  "0 $ENABLED;open failing-weekly" "$rc $(events)" "$W"
if [ -f "$gh/body-failing-weekly.md" ] && grep -q 'https://github.test/run/2026-10-12' "$gh/body-failing-weekly.md"; then
  ok "the body of failing-weekly links the newest failed run"
else
  fail "the body of failing-weekly links the newest failed run" \
    "events: $(events)" "reproduce: $W"
fi

gh_dir mixed failing-weekly=7
runs daily.yml 2026-10-16:success 2026-10-15:success 2026-10-14:success
runs weekly.yml 2026-10-12:failure 2026-10-05:success 2026-09-28:failure
rc="$(run_watch)"
expect "failure, success, failure: failing-weekly stays as it is" \
  "0 $ENABLED" "$rc $(events)" "$W"

gh_dir two
runs daily.yml 2026-10-16:success 2026-10-15:success 2026-10-14:success
runs weekly.yml 2026-10-12:failure 2026-10-05:failure
rc="$(run_watch)"
expect "2 failed scheduled runs are not yet failing" \
  "0 $ENABLED" "$rc $(events)" "$W"

gh_dir manual
workflows active disabled_manually active
runs daily.yml 2026-10-16:success 2026-10-15:success 2026-10-14:success
runs weekly.yml 2026-10-12:success 2026-10-05:success 2026-09-28:success
rc="$(run_watch)"
expect "a workflow that a person disabled: schedules-stopped opens, exit 0" \
  "0 enable 11;enable 13;open schedules-stopped" "$rc $(events)" "$W"

gh_dir couldnot schedules-stopped=5
runs weekly.yml 2026-10-12:success 2026-10-05:success 2026-09-28:success
rc=0
PATH="$work/bin:$PATH" FAKE_GH_DIR="$gh" GH_TOKEN=stub GITHUB_REPOSITORY=test/repo \
  FAKE_GH_FAIL='repos/*/actions/workflows/daily.yml/runs*' SCHEDULES_TODAY="$TODAY" \
  "$tree/scripts/watch-schedules" > "$work/out" 2>&1 || rc=$?
expect "a run list that cannot be read: exit 1, and schedules-stopped is not closed" \
  "1 $ENABLED" "$rc $(events)" "FAKE_GH_FAIL='repos/*/runs*' $W"

#---------------------------------------------------------------------------#
# check-schedules-fired: the result files, and the workflow with no record
#---------------------------------------------------------------------------#
gh_dir results
runs daily.yml 2026-10-16:success 2026-10-15:failure 2026-10-14:failure
runs weekly.yml 2026-10-12:failure 2026-10-05:failure 2026-09-28:startup_failure
rc=0
PATH="$work/bin:$PATH" FAKE_GH_DIR="$gh" GITHUB_REPOSITORY=test/repo SCHEDULES_TODAY="$TODAY" \
  "$tree/scripts/check-schedules-fired" "$work/results" > "$work/out" 2>&1 || rc=$?
got="$rc daily=$(cat "$work/results/daily.result") weekly=$(cat "$work/results/weekly.result") fresh=$(cat "$work/results/fresh.result")"
expect "check-schedules-fired: passing, failing, and none for a workflow with no record (HTTP 404)" \
  "0 daily=passing weekly=failing fresh=none" "$got" \
  "FAKE_GH_DIR=DIR SCHEDULES_TODAY=$TODAY scripts/check-schedules-fired OUT_DIR"
expect "check-schedules-fired: the runs file holds the newest 3 completed scheduled runs" \
  "2026-10-12T07:41:00Z failure 3" \
  "$(awk 'NR == 1 { print $1, $2 }' "$work/results/weekly.runs") $(awk 'END { print NR }' "$work/results/weekly.runs")" \
  "cat OUT_DIR/weekly.runs"

# A workflow with no scheduled run: new while its record or its file is
# younger than the tolerance, stopped after that.
# fired NAME CHANGED_DATE: run check-schedules-fired; prints "<exit> <weekly line kind>"
fired() {
  local rc=0
  gh_dir "$1"
  runs daily.yml 2026-10-16:success 2026-10-15:success 2026-10-14:success
  printf '{"workflow_runs":[]}\n' > "$gh/runs-weekly.yml.json"
  printf '{"created_at":"2026-01-01T00:00:00Z"}\n' > "$gh/workflow-weekly.yml.json"
  jq -n --arg d "$2" '[{commit: {committer: {date: $d}}}]' > "$gh/commits.json"
  PATH="$work/bin:$PATH" FAKE_GH_DIR="$gh" GITHUB_REPOSITORY=test/repo SCHEDULES_TODAY="$TODAY" \
    "$tree/scripts/check-schedules-fired" > "$work/out" 2>&1 || rc=$?
  printf '%s %s\n' "$rc" "$(awk '$2 == "weekly.yml" { print $1 }' "$work/out")"
}
expect "no scheduled run, an old record, and a file changed 2 days ago: new, not stopped" \
  "0 new" "$(fired cron-added 2026-10-14T09:00:00Z)" "FAKE_GH_DIR=DIR scripts/check-schedules-fired"
expect "no scheduled run, an old record, and a file changed 200 days ago: stopped (exit 3)" \
  "3 NEVER" "$(fired cron-dead 2026-03-30T09:00:00Z)" "FAKE_GH_DIR=DIR scripts/check-schedules-fired"

#---------------------------------------------------------------------------#
# dispatch-overdue
#---------------------------------------------------------------------------#
# iso MINUTES_AGO -> an ISO 8601 UTC time that many minutes ago
iso() {
  jq -nr --argjson m "$1" 'now - ($m * 60) | floor | todate'
}

# case_dispatch DESC RUNS_JSON WANT_RC WANT_EVENTS ARGS...
case_dispatch() {
  local desc="$1" want_rc="$3" want_events="$4" rc=0
  gh_dir dispatch
  printf '%s\n' "$2" > "$gh/runs-build.yml.json"
  printf '{"state":"%s"}\n' "${STATE:-active}" > "$gh/workflow-build.yml.json"
  printf '{"default_branch":"trunk"}\n' > "$gh/repo.json"
  shift 4
  PATH="$work/bin:$PATH" FAKE_GH_DIR="$gh" GH_TOKEN=stub GITHUB_REPOSITORY=test/repo \
    "$tree/scripts/dispatch-overdue" "$@" > "$work/out" 2>&1 || rc=$?
  expect "dispatch-overdue: $desc" "$want_rc $want_events" "$rc $(events)" "FAKE_GH_DIR=DIR scripts/dispatch-overdue $*"
}

# a_run STATUS MINUTES_AGO [REPOSITORY [EVENT]]: one run of the run list, on
# the branch trunk. The defaults are test/repo and schedule.
a_run() {
  jq -nc --arg s "$1" --arg t "$(iso "$2")" --arg r "${3:-test/repo}" --arg e "${4:-schedule}" \
    '{status: $s, created_at: $t, event: $e, head_branch: "trunk", head_repository: {full_name: $r}}'
}
# runs RUN...: the run list of the runs
runs() {
  local IFS=,
  printf '{"workflow_runs":[%s]}\n' "$*"
}

case_dispatch "a run 30 min old, limit 240" \
  "$(runs "$(a_run completed 30)")" 0 "" build.yml 240
case_dispatch "a newest run 300 min old, limit 240: started on the default branch" \
  "$(runs "$(a_run completed 300)" "$(a_run completed 500)")" \
  0 "dispatch build.yml trunk" build.yml 240
case_dispatch "an old run and a run 10 min old" \
  "$(runs "$(a_run completed 900)" "$(a_run completed 10)")" 0 "" build.yml 240
case_dispatch "an old run that is in progress" \
  "$(runs "$(a_run in_progress 600)")" 0 "" build.yml 240
case_dispatch "a run 10 min old from a fork, with the head branch trunk, does not count: started" \
  "$(runs "$(a_run completed 10 someone/fork pull_request)" "$(a_run completed 900)")" \
  0 "dispatch build.yml trunk" build.yml 240
case_dispatch "a run in progress from a fork does not hold the start" \
  "$(runs "$(a_run in_progress 5 someone/fork pull_request)" "$(a_run completed 900)")" \
  0 "dispatch build.yml trunk" build.yml 240
case_dispatch "a pull_request run of this repository does not count" \
  "$(runs "$(a_run completed 10 test/repo pull_request)" "$(a_run completed 900)")" \
  0 "dispatch build.yml trunk" build.yml 240
case_dispatch "a scheduled run whose head is another repository does not count" \
  "$(runs "$(a_run completed 10 someone/fork schedule)" "$(a_run completed 900)")" \
  0 "dispatch build.yml trunk" build.yml 240
case_dispatch "no run at all: started" '{"workflow_runs":[]}' 0 "dispatch build.yml trunk" build.yml 120
case_dispatch "a workflow name that is not a file name" '{"workflow_runs":[]}' 2 "" 'build yml' 240
case_dispatch "a limit that is not a number" '{"workflow_runs":[]}' 2 "" build.yml soon
STATE=disabled_manually case_dispatch "a workflow that a person disabled is not started" '{"workflow_runs":[]}' 0 "" build.yml 240
DEFAULT_BRANCH=release case_dispatch "DEFAULT_BRANCH names the branch" '{"workflow_runs":[]}' 0 "dispatch build.yml release" build.yml 240
FAKE_GH_FAIL='repos/*/runs*' case_dispatch "a run list that cannot be read: exit 1, nothing started" \
  '{"workflow_runs":[]}' 1 "" build.yml 240

summary
