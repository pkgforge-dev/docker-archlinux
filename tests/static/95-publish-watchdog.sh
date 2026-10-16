#!/usr/bin/env bash
#
# The watchdog: the checks that see a stopped publish or a stopped schedule,
# and the wiring that runs them.
#
#   1. scripts/date-age against dates worked out by hand
#   2. scripts/cron-tolerance against cron shapes worked out by hand
#   3. a cron that cannot be read, or whose tolerance is above 60 days, is
#      refused, not given a tolerance
#   4. every cron of the tree can be read, with a tolerance of 60 days or less
#   5. scripts/check-publish-recency per port, on GHCR and Docker Hub, with
#      tag files and a date as test seams (fixture ports and workflow in
#      tests/fixtures/95-publish-watchdog)
#   6. no workflow sets a test seam
#   7. the wiring, read with yq: watchdog.yml runs the checks and raises the
#      issues in steps that run after a failure; build-deploy.yml job watch
#      needs nothing and nothing needs it; freshness.yml reads its keyring
#      matrix from a job output
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

TOL="$REPO_ROOT/scripts/cron-tolerance"
AGE="$REPO_ROOT/scripts/date-age"
RECENCY="$REPO_ROOT/scripts/check-publish-recency"
FIRED="$REPO_ROOT/scripts/check-schedules-fired"
WF_DIR="$REPO_ROOT/.github/workflows"
FIX="$(fixture_dir)"

work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

# expect DESC WANT GOT REPRODUCE
expect() {
  if [ "$2" = "$3" ]; then
    ok "$1"
  else
    fail "$1" "expected: $2" "got:      $3" "reproduce: $4"
  fi
}

#---------------------------------------------------------------------------#
# 1. The calendar. ⛔ Each expectation is worked out by hand.
#---------------------------------------------------------------------------#
age_case() {
  local got rc=0
  got="$("$AGE" "$1" "$2" 2>&1)" || rc=$?
  expect "date-age $1 $2 is $3" "0 $3" "$rc $got" "scripts/date-age $1 $2"
}

age_case 2026-07-13 2026-08-27 45
age_case 2026-08-28 2026-08-28 0
age_case 2026-08-28 2026-09-01 4
age_case 2024-02-28 2024-03-01 2      # 2024 is a leap year
age_case 2023-02-28 2023-03-01 1      # 2023 is not
age_case 2000-02-28 2000-03-01 2      # divisible by 400: a leap year
age_case 1900-02-28 1900-03-01 1      # divisible by 100 and not by 400: not one
age_case 2026-01-01 2027-01-01 365
age_case 2027-01-01 2026-01-01 -365   # backwards is negative, not an error
age_case 2026-07-13T08:32:37Z 2026-08-27T16:36:52Z 45   # the runs API shape

for bad in "notadate" "2026-13-01" "2026-01-32"; do
  rc=0
  "$AGE" "$bad" 2026-01-01 > "$work/age.out" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    fail "date-age refuses '$bad'" "it exited 0" "reproduce: scripts/date-age '$bad' 2026-01-01"
  else
    ok "date-age refuses '$bad'"
  fi
done

#---------------------------------------------------------------------------#
# 2. The cron arithmetic. A gap is the number of days from one firing to the
# next; the tolerance is gap + min(gap, 7) + 1. ⛔ Each expectation is worked
# out by hand.
#---------------------------------------------------------------------------#
# tol_case CRON WANT [--minutes]
tol_case() {
  local got rc=0
  printf 'on:\n  schedule:\n    - cron: "%s"\n' "$1" > "$work/case.yml"
  got="$("$TOL" ${3:+"$3"} "$work/case.yml" 2>&1)" || rc=$?
  expect "cron '$1'${3:+ $3} gives '$2'" "0 $2" "$rc $got" \
    "printf 'on:\\n  schedule:\\n    - cron: \"%s\"\\n' '$1' > /tmp/w.yml; scripts/cron-tolerance ${3:-} /tmp/w.yml"
}

tol_case "30 5 * * *"   "1 3"      # every day
tol_case "0 0 * * 1"    "7 15"     # Mondays
tol_case "0 0 * * MON"  "7 15"     # Mondays, with a name
tol_case "0 0 * * 0"    "7 15"     # Sundays, as 0
tol_case "0 0 * * 7"    "7 15"     # Sundays, as 7
tol_case "0 0 * * 1,4"  "4 9"      # Monday and Thursday: Thursday to Monday is 4 days
tol_case "0 0 1 * *"    "31 39"    # the 1st: January to February is 31 days, then 7 + 1
tol_case "0 0 1,15 * *" "17 25"    # the 15th to the 1st of a 31-day month is 17 days
tol_case "0 0 */2 * *"  "2 5"      # odd days: the 29th to the 31st is 2 days
tol_case "0 0 * * 1-7"  "1 3"      # each day of the week
tol_case "0 0 1 * 1"    "7 15"     # ⛔ day of month OR day of week, not AND
tol_case "17 */3 * * *" "180" --minutes
tol_case "41 7 * * *"   "1440" --minutes

printf 'on:\n  schedule:\n    - cron: "0 0 * * 1"\n    - cron: "0 0 * * 4"\n' > "$work/two.yml"
rc=0
got="$("$TOL" "$work/two.yml" 2>&1)" || rc=$?
expect "two crons in one workflow are read together" "0 4 9" "$rc $got" "scripts/cron-tolerance <a workflow with two cron lines>"

#---------------------------------------------------------------------------#
# 3. A cron that cannot be read is refused.
#---------------------------------------------------------------------------#
bad_case() {
  local rc=0
  printf 'on:\n  schedule:\n    - cron: "%s"\n' "$1" > "$work/bad.yml"
  "$TOL" "$work/bad.yml" > "$work/bad.out" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    fail "cron '$1' is refused" "it exited 0 and printed: $(awk 'NR == 1' "$work/bad.out")" \
      "reproduce: printf 'on:\\n  schedule:\\n    - cron: \"%s\"\\n' '$1' > /tmp/w.yml; scripts/cron-tolerance /tmp/w.yml"
  else
    ok "cron '$1' is refused"
  fi
}

bad_case "bogus"          # not five fields
bad_case "0 0 32 * *"     # no month has a 32nd day
bad_case "0 0 * 13 *"     # no 13th month
bad_case "0 0 * * 9"      # no 9th day of the week
bad_case "0 0 1 1 *"      # one time a year: a gap of 366 days, tolerance 374
bad_case "0 0 1 */2 *"    # odd months: November to January is 61 days, tolerance 69
printf 'on:\n  push:\n    branches: [main]\n' > "$work/none.yml"
rc=0
"$TOL" "$work/none.yml" > "$work/none.out" 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then
  fail "a workflow with no cron is refused" "it exited 0" "reproduce: scripts/cron-tolerance .github/workflows/ci.yml"
else
  ok "a workflow with no cron is refused"
fi

#---------------------------------------------------------------------------#
# 4. Every cron of the tree can be read, with a tolerance of 60 days or less.
# A cron that cannot be read takes its workflow out of
# scripts/check-schedules-fired.
#---------------------------------------------------------------------------#
scheduled=0
unreadable=""
for wf in "$WF_DIR"/*.yml "$WF_DIR"/*.yaml; do
  [ -e "$wf" ] || continue
  grep -q '^[[:space:]]*-[[:space:]]*cron:' "$wf" || continue
  scheduled=$((scheduled + 1))
  if ! out="$("$TOL" "$wf" 2>&1)"; then
    unreadable="$unreadable ${wf#"$WF_DIR/"}"
  else
    diag "${wf#"$WF_DIR/"} gap and tolerance: $out"
  fi
done
if [ "$scheduled" -eq 0 ]; then
  fail "a workflow of the tree has a cron" "none found" "reproduce: grep -l 'cron:' .github/workflows/*"
elif [ -n "$unreadable" ]; then
  fail "every cron of the tree can be read, with a tolerance of 60 days or less" "these cannot:$unreadable" \
    "reproduce: for w in .github/workflows/*.yml; do scripts/cron-tolerance \$w; done"
else
  ok "the crons of all $scheduled scheduled workflows can be read, each with a tolerance of 60 days or less"
fi

#---------------------------------------------------------------------------#
# 5. check-publish-recency, per port, on both registries.
#
# The fixture ports are amd64 (first alias x86_64) and ppc (first alias ppc),
# and the fixture workflow has a tolerance of 3 days. RECENCY_GHCR_TAGS and
# RECENCY_HUB_TAGS replace the registries, RECENCY_TODAY the clock.
#---------------------------------------------------------------------------#
# recency NAME TODAY: run the check on $work/NAME.ghcr and $work/NAME.hub;
# prints "<exit> amd64=<state> ppc=<state> index=<state>"
recency() {
  local rc=0 d="$work/rec-$1"
  rm -rf "$d"
  PORTS_DIR="$FIX/ports" PUBLISH_WORKFLOW="$FIX/publish.yml" RECENCY_TODAY="$2" \
    RECENCY_GHCR_TAGS="$work/$1.ghcr" RECENCY_HUB_TAGS="$work/$1.hub" \
    "$RECENCY" "$d" > "$work/rec.out" 2>&1 || rc=$?
  printf '%s amd64=%s ppc=%s index=%s\n' "$rc" \
    "$(cat "$d/amd64.state" 2> "$work/rec.err")" "$(cat "$d/ppc.state" 2>> "$work/rec.err")" "$(cat "$d/index.state" 2>> "$work/rec.err")"
}
RR="RECENCY_GHCR_TAGS=F RECENCY_HUB_TAGS=F RECENCY_TODAY=D PORTS_DIR=$FIX/ports PUBLISH_WORKFLOW=$FIX/publish.yml scripts/check-publish-recency OUT"

# The decoys of a real registry: rolling tags, an anchor tag, a date that is
# not zero padded, and a date of another family.
cat > "$work/ok.ghcr" <<'TAGS'
latest
x86_64
amd64-v2030.01.01
x86_64-v2029.12.31
x86_64-v2030.01.01
x86_64-v2030.1.5
ppc-v2030.01.01
ppc-7.1.0.r9.g54d9411-2
powerpc-v2030.06.01
v2029.12.31
v2030.01.01
TAGS
cp "$work/ok.ghcr" "$work/ok.hub"

expect "the newest dated tag of each port is found across a year boundary: all current" \
  "0 amd64=current ppc=current index=current" "$(recency ok 2030-01-01)" "$RR"
expect "3 days after the newest tags is within the tolerance" \
  "0 amd64=current ppc=current index=current" "$(recency ok 2030-01-04)" "$RR"
expect "4 days after the newest tags is a stop for every key" \
  "3 amd64=stale ppc=stale index=stale" "$(recency ok 2030-01-05)" "$RR"
expect "a run in 2087 still reads the 2030 tags as a stop" \
  "3 amd64=stale ppc=stale index=stale" "$(recency ok 2087-06-01)" "$RR"

# One port stops on GHCR while the other publishes and the index moves.
sed 's/^ppc-v2030\.01\.01$/ppc-v2029.12.20/' "$work/ok.ghcr" > "$work/oneport.ghcr"
cp "$work/ok.hub" "$work/oneport.hub"
expect "one port stops on GHCR and the index moves: only that port is stale" \
  "3 amd64=current ppc=stale index=current" "$(recency oneport 2030-01-02)" "$RR"

# The copy to Docker Hub stops for one port.
cp "$work/ok.ghcr" "$work/hubbehind.ghcr"
awk '$0 != "x86_64-v2030.01.01"' "$work/ok.hub" > "$work/hubbehind.hub"
expect "Docker Hub lacks the newest tag of a port: that port is stale" \
  "3 amd64=stale ppc=current index=current" "$(recency hubbehind 2030-01-04)" "$RR"

# A port with no dated tag at all.
awk '$0 !~ /^ppc-v/' "$work/ok.ghcr" > "$work/nodate.ghcr"
cp "$work/ok.hub" "$work/nodate.hub"
expect "a port with no dated tag on a registry is stale, not passed" \
  "3 amd64=current ppc=stale index=current" "$(recency nodate 2030-01-02)" "$RR"

# An empty tag list is a registry that could not be read: unknown, exit 1.
cp "$work/ok.ghcr" "$work/unread.ghcr"
: > "$work/unread.hub"
expect "a tag list that is empty makes every key unknown, and the exit status 1" \
  "1 amd64=unknown ppc=unknown index=unknown" "$(recency unread 2030-01-02)" "$RR"
cp "$work/oneport.ghcr" "$work/unreadstale.ghcr"
: > "$work/unreadstale.hub"
expect "stale on one registry wins over unknown on the other" \
  "3 amd64=unknown ppc=stale index=unknown" "$(recency unreadstale 2030-01-02)" "$RR"

# ⭐ The image names come from the top level env of the publish workflow, so
# they have one place. A workflow with no such env stops the check.
# names WORKFLOW -> "<exit> <image of each registry row of amd64.md>"
names() {
  local rc=0 d="$work/rec-names"
  rm -rf "$d"
  env -u PUBLISH_IMAGE -u HUB_IMAGE GITHUB_REPOSITORY=fixture-owner/fixture \
    PORTS_DIR="$FIX/ports" PUBLISH_WORKFLOW="$1" RECENCY_TODAY=2030-01-05 \
    RECENCY_GHCR_TAGS="$work/ok.ghcr" RECENCY_HUB_TAGS="$work/ok.hub" \
    "$RECENCY" "$d" > "$work/names.out" 2>&1 || rc=$?
  printf '%s' "$rc"
  if [ -f "$d/amd64.md" ]; then
    awk -F'|' '$2 ~ /^ (ghcr|hub) $/ { v = $3; gsub(/[ `]/, "", v); printf " %s", v }' "$d/amd64.md"
  fi
  printf '\n'
}
expect "the GHCR and Docker Hub images are the env GHCR_IMAGE and HUB_IMAGE of the publish workflow" \
  "3 ghcr.io/fixture-owner/fixture-image docker.io/fixture-org/fixture-image" "$(names "$FIX/publish.yml")" \
  "GITHUB_REPOSITORY=fixture-owner/fixture $RR"
awk '$0 !~ /^env:|_IMAGE:/' "$FIX/publish.yml" > "$work/no-env.yml"
expect "a publish workflow with no image env stops the check with exit 1" \
  "1" "$(names "$work/no-env.yml")" \
  "PUBLISH_WORKFLOW=<a workflow with no env> $RR"

#---------------------------------------------------------------------------#
# 6. No workflow sets a test seam. A seam that CI sets makes a check pass
# without a read.
#---------------------------------------------------------------------------#
seams='RECENCY_TODAY|RECENCY_GHCR_TAGS|RECENCY_HUB_TAGS|SCHEDULES_TODAY|KEYRING_TODAY'
hits=""
for wf in "$WF_DIR"/*.yml "$WF_DIR"/*.yaml; do
  [ -e "$wf" ] || continue
  hit="$(grep_matches "$seams" "$wf")"
  [ -z "$hit" ] || hits="$hits ${wf#"$REPO_ROOT/"}:$(printf '%s' "$hit" | awk -F: '{ printf "%s,", $1 }')"
done
if [ -z "$hits" ]; then
  ok "no workflow names a test seam ($seams)"
else
  fail "no workflow names a test seam" "found at:$hits" \
    "reproduce: grep -nE '$seams' .github/workflows/*.yml"
fi

# The list of workflows is found in .github/workflows, never written.
listed="$(grep_matches '[a-z-]+\.ya?ml' "$FIRED")"
if [ -z "$listed" ]; then
  ok "scripts/check-schedules-fired names no workflow file"
else
  fail "scripts/check-schedules-fired names no workflow file" "found: $(printf '%s' "$listed" | tr '\n' ' ')" \
    "reproduce: grep -nE '[a-z-]+\\.ya?ml' scripts/check-schedules-fired"
fi

#---------------------------------------------------------------------------#
# 7. The wiring, read with yq.
#---------------------------------------------------------------------------#

if need_tool yq jq; then
  WATCH="$WF_DIR/watchdog.yml"
  BUILD="$WF_DIR/build-deploy.yml"
  FRESH="$WF_DIR/freshness.yml"
  for f in "$WATCH" "$BUILD" "$FRESH"; do
    if [ -f "$f" ]; then
      yaml_json "$f" > "$work/$(basename "$f" .yml).json"
    else
      printf '{}\n' > "$work/$(basename "$f" .yml).json"
    fi
  done

  # after SCRIPT_A SCRIPT_B FILE -> the job ids in which a step runs SCRIPT_A
  # and a later step runs SCRIPT_B with if: !cancelled() or always()
  after() {
    jq -r --arg a "$1" --arg b "$2" '
      (.jobs // {}) | to_entries[] | .key as $id | (.value.steps // []) as $s
      | [range(0; $s | length) | select(($s[.].run // "") | contains($a))] as $ia
      | [range(0; $s | length) | select(($s[.].run // "") | contains($b))
          | select(($s[.]["if"] // "" | tostring) | test("!cancelled\\(\\)|always\\(\\)"))] as $ib
      | select(($ia | length) > 0 and ($ib | length) > 0 and ($ib | max) > ($ia | min)) | $id' "$3"
  }

  w="$(after scripts/check-publish-recency scripts/track-issue "$work/watchdog.json")"
  expect "watchdog.yml measures each port, then raises or clears stale-<arch> in a step that runs after a failure" \
    "yes" "$([ -n "$w" ] && echo yes || echo no)" "yq '.jobs[].steps[] | {if, run}' .github/workflows/watchdog.yml"

  w="$(after scripts/watch-schedules scripts/dispatch-overdue "$work/watchdog.json")"
  expect "watchdog.yml watches the schedules, then starts an overdue run in a step that runs after a failure" \
    "yes" "$([ -n "$w" ] && echo yes || echo no)" "yq '.jobs[].steps[] | {if, run}' .github/workflows/watchdog.yml"

  # The step that runs scripts/watch-schedules, run with a stand-in. Exit 3
  # is a stopped schedule, and schedules-stopped names it, so the step stays
  # green. A red step would raise failing-watchdog too.
  jq -r '[.jobs // {} | .[] | .steps // [] | .[] | .run // "" | select(test("scripts/watch-schedules"))] | first // ""' \
    "$work/watchdog.json" > "$work/watch-step.sh"
  mkdir -p "$work/watch/scripts"
  # shellcheck disable=SC2016 # the stand-in expands $WATCH_RC, not this shell
  printf '#!/usr/bin/env bash\nexit "$WATCH_RC"\n' > "$work/watch/scripts/watch-schedules"
  chmod +x "$work/watch/scripts/watch-schedules"
  got=""
  for want_rc in 0 3 1; do
    rc=0
    (cd "$work/watch" && WATCH_RC="$want_rc" bash --noprofile --norc -eo pipefail "$work/watch-step.sh") \
      > "$work/watch/out-$want_rc" 2>&1 || rc=$?
    got="$got $want_rc:$rc"
  done
  expect "the watchdog.yml step passes when watch-schedules exits 0 or 3, and fails when it exits 1" \
    " 0:0 3:0 1:1" "$got" "yq '.jobs[].steps[] | select(.run | test(\"watch-schedules\")) | .run' .github/workflows/watchdog.yml"

  for s in scripts/check-status-site scripts/rerun-bot-ci; do
    n="$(jq --arg s "$s" '[.jobs // {} | .[] | .steps // [] | .[] | select((.run // "") | contains($s))] | length' "$work/watchdog.json")"
    expect "watchdog.yml runs $s" "yes" "$([ "$n" -gt 0 ] && echo yes || echo no)" "yq '.jobs[].steps[].run' .github/workflows/watchdog.yml"
  done

  crons="$(jq '[(.on // .["true"] // {}).schedule // [] | .[] | .cron] | length' "$work/watchdog.json")"
  expect "watchdog.yml has a schedule" "yes" "$([ "$crons" -gt 0 ] && echo yes || echo no)" "yq '.on.schedule' .github/workflows/watchdog.yml"

  # ⛔ build-deploy.yml job watch witnesses the schedule of watchdog.yml. It
  # gates nothing and nothing gates it.
  watch="$(jq -r '.jobs.watch // empty | [(.needs // "none" | tostring), ([.steps // [] | .[] | .run // "" | select(contains("scripts/watch-schedules"))] | length | tostring)] | join(" ")' "$work/build-deploy.json")"
  expect "build-deploy.yml has a job watch that runs scripts/watch-schedules and needs nothing" \
    "none 1" "$watch" "yq '.jobs.watch' .github/workflows/build-deploy.yml"
  gates="$(jq -r '.jobs // {} | to_entries[] | select((.value.needs // []) | if type == "string" then [.] else . end | index("watch")) | .key' "$work/build-deploy.json")"
  expect "no job of build-deploy.yml needs the job watch" "" "$gates" "yq '.jobs[].needs' .github/workflows/build-deploy.yml"

  # ⭐ The keyring matrix comes from the pin files, through a job output.
  inc="$(jq -r '.jobs.keyring.strategy.matrix.include // "" | tostring' "$work/freshness.json")"
  case "$inc" in
    *fromJSON\(needs.*) ok "freshness.yml reads the keyring matrix from a job output, not from a list" ;;
    *) fail "freshness.yml reads the keyring matrix from a job output, not from a list" "include: ${inc:-none}" \
      "reproduce: yq '.jobs.keyring.strategy.matrix' .github/workflows/freshness.yml" ;;
  esac
fi

summary
