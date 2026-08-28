#!/usr/bin/env bash
#
# The two checks that notice when a schedule stops, and the wiring that makes
# them watch each other.
#
# ⛔ A scheduled workflow that stops firing produces no run, so no failure and no
# red mark. 45 days of that went unnoticed here, ending 2026-08-27, with every
# workflow reporting state "active" throughout.
# HISTORY/reviews/19-a-job-that-stops-running.md.
#
# ⚠ This tests the mechanism, not today's answer. Whether the publish is
# currently recent is a question about the registry and needs the network;
# scripts/check-publish-recency answers that and the freshness workflow runs it.
# What is asserted here is that the mechanism cannot quietly stop working:
#
#   1. the calendar is right, against dates worked out by hand
#   2. the cron reading is right, against cron shapes worked out by hand
#   3. a cron it cannot read is refused rather than given a made up threshold
#   4. every cron actually in the tree can be read, so a new one cannot land
#      unparsed and drop that workflow out of the watch
#   5. neither check carries a written-down threshold, a written-down year or a
#      written-down list of what it watches, and no workflow takes a test seam
#   6. the two workflows run the checks, and the watchdog job gates nothing
#
# ⭐ Section 5 runs the recency check against a tag list in a file and a date in
# an environment variable, so which tag it picks is measured rather than
# inferred from reading it, including for a year that has not happened yet.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

TOL="$REPO_ROOT/scripts/cron-tolerance"
AGE="$REPO_ROOT/scripts/date-age"
RECENCY="$REPO_ROOT/scripts/check-publish-recency"
FIRED="$REPO_ROOT/scripts/check-schedules-fired"
WF_DIR="$REPO_ROOT/.github/workflows"
PUBLISH_WF="$WF_DIR/build-deploy.yml"
WATCH_WF="$WF_DIR/freshness-publish.yml"

for f in "$TOL" "$AGE" "$RECENCY" "$FIRED" "$PUBLISH_WF" "$WATCH_WF"; do
  if [ -f "$f" ]; then
    ok "${f#"$REPO_ROOT/"} exists"
  else
    fail "${f#"$REPO_ROOT/"} exists" \
      "reproduce: ls ${f#"$REPO_ROOT/"}"
    summary
    exit 1
  fi
done

work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

#---------------------------------------------------------------------------#
# 1. The calendar, which both checks and nothing else share.
#
# ⛔ Every expectation is worked out by hand. An off by one here shifts every
# threshold in the mechanism by a day, in a direction nothing else would show.
#---------------------------------------------------------------------------#
age_case() {
  local from="$1" to="$2" want="$3" got
  if ! got="$("$AGE" "$from" "$to" 2>&1)"; then
    fail "date-age $from $to is $want" \
      "the script failed: $got" \
      "reproduce: scripts/date-age $from $to"
    return
  fi
  if [ "$got" = "$want" ]; then
    ok "date-age $from $to is $want"
  else
    fail "date-age $from $to is $want" \
      "got $got" \
      "reproduce: scripts/date-age $from $to"
  fi
}

# ⭐ The measured silence this whole mechanism exists for: the last daily
# scheduled run before the gap, and the first one after it.
# HISTORY/reviews/19-a-job-that-stops-running.md.
age_case 2026-07-13 2026-08-27 45
age_case 2026-08-28 2026-08-28 0
age_case 2026-08-28 2026-09-01 4
age_case 2024-02-28 2024-03-01 2      # 2024 is a leap year
age_case 2023-02-28 2023-03-01 1      # 2023 is not
age_case 2000-02-28 2000-03-01 2      # divisible by 400, so a leap year
age_case 1900-02-28 1900-03-01 1      # divisible by 100 and not 400, so not one
age_case 2026-01-01 2027-01-01 365
age_case 2027-01-01 2026-01-01 -365   # backwards is negative, never an error

# An ISO timestamp is accepted, which is the shape the runs API returns.
age_case 2026-07-13T08:32:37Z 2026-08-27T16:36:52Z 45

for bad in "notadate" "2026-13-01" "2026-01-32"; do
  rc=0
  "$AGE" "$bad" 2026-01-01 > /dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    fail "date-age refuses '$bad'" \
      "it exited 0" \
      "reproduce: scripts/date-age '$bad' 2026-01-01"
  else
    ok "date-age refuses '$bad'"
  fi
done

#---------------------------------------------------------------------------#
# 2. The cron arithmetic.
#
# ⛔ Every expectation below is worked out by hand and written next to it. A
# gap is the number of days from one firing to the next, so a daily cron has a
# gap of 1. The tolerance is gap * 2 + 1: one missed firing is a transient, two
# is a stop.
#
# ⚠ An under-reported gap is the dangerous direction. It makes the tolerance too
# small, so the check fails on a schedule that is working, and a check that
# cries wolf is one nobody reads.
#---------------------------------------------------------------------------#
tol_case() {
  local cron="$1" want="$2" got
  printf 'on:\n  schedule:\n    - cron: "%s"\n' "$cron" > "$work/case.yml"
  if ! got="$("$TOL" "$work/case.yml" 2>&1)"; then
    fail "cron '$cron' derives a tolerance" \
      "the script failed: $got" \
      "reproduce: printf 'on:\\n  schedule:\\n    - cron: \"%s\"\\n' '$cron' > /tmp/w.yml; scripts/cron-tolerance /tmp/w.yml"
    return
  fi
  if [ "$got" = "$want" ]; then
    ok "cron '$cron' gives gap and tolerance '$want'"
  else
    fail "cron '$cron' gives gap and tolerance '$want'" \
      "got '$got'" \
      "reproduce: printf 'on:\\n  schedule:\\n    - cron: \"%s\"\\n' '$cron' > /tmp/w.yml; scripts/cron-tolerance /tmp/w.yml"
  fi
}

tol_case "30 5 * * *"   "1 3"      # every day, so one day between firings
tol_case "0 0 * * 1"    "7 15"     # Mondays, seven days apart
tol_case "0 0 * * MON"  "7 15"     # the same, spelled with a name
tol_case "0 0 * * 0"    "7 15"     # Sundays, dow 0
tol_case "0 0 * * 7"    "7 15"     # Sundays, dow 7, which some crons accept
tol_case "0 0 * * 1,4"  "4 9"      # Mon and Thu: Thu to Mon is four days
tol_case "0 0 1 * *"    "31 63"    # the 1st: January to February is 31 days
tol_case "0 0 */2 * *"  "2 5"      # odd days: 29th to 31st is two days
tol_case "0 0 * * 1-7"  "1 3"      # every weekday name, so every day
tol_case "0 0 1 1 *"    "366 733"  # once a year, and 2024 is a leap year

# ⛔ Day of month and day of week are ORed when both are restricted. Read as an
# AND this would be "the 1st, when it is a Monday", roughly seven times a year.
tol_case "0 0 1 * 1"    "7 15"

# Two cron entries in one workflow: either firing counts.
printf 'on:\n  schedule:\n    - cron: "0 0 * * 1"\n    - cron: "0 0 * * 4"\n' > "$work/two.yml"
got="$("$TOL" "$work/two.yml" 2>&1 || true)"
if [ "$got" = "4 9" ]; then
  ok "two crons in one workflow are measured together"
else
  fail "two crons in one workflow are measured together" \
    "Monday plus Thursday is a largest gap of 4, expected '4 9', got '$got'" \
    "reproduce: read the schedule block of any workflow with two cron lines"
fi

#---------------------------------------------------------------------------#
# 3. A cron that cannot be read is a loud failure, never a default.
#
# ⚠ A parser that answers "7 days" for an expression it did not understand puts
# a made up threshold on a real schedule, and nothing would say so.
#---------------------------------------------------------------------------#
bad_case() {
  local cron="$1" rc=0
  printf 'on:\n  schedule:\n    - cron: "%s"\n' "$cron" > "$work/bad.yml"
  "$TOL" "$work/bad.yml" > "$work/bad.out" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    fail "cron '$cron' is refused rather than guessed at" \
      "it exited 0 and printed: $(awk 'NR == 1' "$work/bad.out")" \
      "reproduce: printf 'on:\\n  schedule:\\n    - cron: \"%s\"\\n' '$cron' > /tmp/w.yml; scripts/cron-tolerance /tmp/w.yml"
  else
    ok "cron '$cron' is refused rather than guessed at"
  fi
}

bad_case "bogus"          # not five fields
bad_case "0 0 32 * *"     # no month has a 32nd
bad_case "0 0 * 13 *"     # no thirteenth month
bad_case "0 0 * * 9"      # no ninth day of the week

# A workflow with no schedule is a refusal too, not a tolerance of zero.
printf 'on:\n  push:\n    branches: [main]\n' > "$work/none.yml"
rc=0
"$TOL" "$work/none.yml" > "$work/none.out" 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then
  fail "a workflow with no cron is refused" \
    "it exited 0 and printed: $(awk 'NR == 1' "$work/none.out")" \
    "reproduce: scripts/cron-tolerance .github/workflows/ci.yml"
else
  ok "a workflow with no cron is refused"
fi

#---------------------------------------------------------------------------#
# 4. Every cron in the tree is readable.
#
# ⛔ Discovered, not listed. A workflow added with a cron shape the parser
# cannot read fails here rather than silently dropping out of the watch.
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
  fail "at least one workflow in the tree carries a cron" \
    "none found, so this test asserted nothing about the tree" \
    "reproduce: grep -l 'cron:' .github/workflows/*"
elif [ -n "$unreadable" ]; then
  fail "every cron in the tree can be read" \
    "these could not be:$unreadable" \
    "an unreadable cron drops that workflow out of scripts/check-schedules-fired" \
    "reproduce: for w in .github/workflows/*.yml; do scripts/cron-tolerance \$w; done"
else
  ok "all $scheduled scheduled workflows have a readable cron"
fi

#---------------------------------------------------------------------------#
# 5. Nothing is written down that should be derived.
#
# ⛔ Three specific ways this mechanism rots, each of which has a precedent:
#
#   a hardcoded day threshold      stops being right when a cron changes
#   a hardcoded year in a tag match  matches nothing from 1 January, and
#                                    matching nothing reads exactly like a
#                                    repository that has never published
#   a hardcoded list of workflows  stops watching whatever nobody added to it
#---------------------------------------------------------------------------#
# ⛔ The year, asserted by running the check rather than by reading it. A text
# scan for a literal year reports the years in its own diagnostics and the 1946
# inside the constant 719468, and misses startswith("v2026") because the year
# sits behind a v. Feeding it a tag list settles what it does.
#
# RECENCY_TAGS_FILE stands in for the registry and RECENCY_TODAY for the clock,
# so this runs with no network and can be asked about a year that has not
# happened yet.
recency_case() {
  local desc="$1" today="$2" want_rc="$3" want_tag="$4" rc=0 got
  RECENCY_TODAY="$today" "$RECENCY" > "$work/rec.out" 2> "$work/rec.err" || rc=$?
  # The tag is pulled out by name rather than by field number: the sentence it
  # sits in is a diagnostic and its wording is not a contract.
  got="$(awk '
    /newest dated index tag is/ {
      for (i = 1; i <= NF; i++) if ($i == "is") { t = $(i + 1); sub(/,$/, "", t); print t; exit }
    }' "$work/rec.err")"
  if [ "$rc" = "$want_rc" ] && [ "$got" = "$want_tag" ]; then
    ok "$desc"
  else
    fail "$desc" \
      "on $today expected exit $want_rc picking $want_tag, got exit $rc picking ${got:-<none>}" \
      "stderr: $(awk 'NR <= 6 { printf "%s | ", $0 }' "$work/rec.err")" \
      "reproduce: RECENCY_TAGS_FILE=<file> RECENCY_TODAY=$today scripts/check-publish-recency"
  fi
}

# A list spanning a year boundary, with the decoys a real registry carries: the
# rolling index tag, a per architecture dated tag, and a date that is not zero
# padded and so is not one of ours.
cat > "$work/tags.txt" <<'TAGS'
latest
x86_64
v2029.12.31
v2030.01.01
x86_64-v2030.06.15
v2030.1.2
riscv64-7.1.0.r9.g54d9411-2
TAGS

export RECENCY_TAGS_FILE="$work/tags.txt"

# ⛔ 2030, not this year. A check anchored on the year it was written passes
# today and matches nothing later, and matching nothing is indistinguishable
# from a repository that has never published.
recency_case "the newest dated index tag is picked across a year boundary" \
  2030-01-01 0 v2030.01.01
recency_case "three days after the newest tag is within tolerance" \
  2030-01-04 0 v2030.01.01
recency_case "four days after the newest tag is a stop" \
  2030-01-05 3 v2030.01.01

# The same list far in the future. Nothing about the check may depend on which
# year it is being run in.
recency_case "a run in 2087 still finds the 2030 tag and calls it a stop" \
  2087-06-01 3 v2030.01.01

# A list with no dated index tag is refused, not read as a fresh publish.
printf 'latest\nx86_64\nriscv64\n' > "$work/nodate.txt"
rc=0
RECENCY_TAGS_FILE="$work/nodate.txt" "$RECENCY" > "$work/nd.out" 2> "$work/nd.err" || rc=$?
if [ "$rc" = "1" ]; then
  ok "a tag list with no dated index tag is refused rather than passed"
else
  fail "a tag list with no dated index tag is refused rather than passed" \
    "expected exit 1, got $rc" \
    "reading no dated tag as a pass switches this guard off whenever the tag family moves" \
    "reproduce: printf 'latest\\nx86_64\\n' > /tmp/t; RECENCY_TAGS_FILE=/tmp/t scripts/check-publish-recency"
fi

unset RECENCY_TAGS_FILE RECENCY_TODAY

# ⛔ Neither seam may be set by anything in CI. A workflow that sets the tag file
# makes this check pass without reading a registry.
seam_hits="$(awk '
  { line = $0; sub(/(^|[[:space:]])#.*$/, "", line) }
  line ~ /RECENCY_(TAGS_FILE|TODAY)|SCHEDULES_TODAY/ { printf "%s:%d: %s\n", FILENAME, FNR, line }
' "$WF_DIR"/*.yml)"
if [ -z "$seam_hits" ]; then
  ok "no workflow sets a test seam on either check"
else
  fail "no workflow sets a test seam on either check" \
    "found: $(printf '%s' "$seam_hits" | tr '\n' ' ')" \
    "a seam CI can take is a way for the check to pass without reading anything" \
    "reproduce: grep -n 'RECENCY_\\|SCHEDULES_TODAY' .github/workflows/*.yml"
fi

# Neither check may name a workflow file other than the default it documents.
listed="$(grep_matches '(freshness|ci|pacman-static)[a-z-]*\.ya?ml' "$FIRED")"
if [ -z "$listed" ]; then
  ok "scripts/check-schedules-fired names no workflow file"
else
  fail "scripts/check-schedules-fired names no workflow file" \
    "found: $(printf '%s' "$listed" | tr '\n' ' ')" \
    "the list is discovered from .github/workflows, so naming one means a second list" \
    "reproduce: grep -nE '(freshness|ci|pacman-static)[a-z-]*\\.ya?ml' scripts/check-schedules-fired"
fi

# Both checks must reach their threshold through cron-tolerance.
for pair in "check-publish-recency:$RECENCY" "check-schedules-fired:$FIRED"; do
  nm="${pair%%:*}"
  path="${pair#*:}"
  if grep -q 'cron-tolerance' "$path"; then
    ok "scripts/$nm derives its threshold from scripts/cron-tolerance"
  else
    fail "scripts/$nm derives its threshold from scripts/cron-tolerance" \
      "a threshold written here stops being right the moment a cron changes" \
      "reproduce: grep -n cron-tolerance scripts/$nm"
  fi
done

# The dated tag spelling comes from scripts/tag-names, not from a literal.
if grep -q 'tag-names' "$RECENCY"; then
  ok "scripts/check-publish-recency asks scripts/tag-names for the tag spelling"
else
  fail "scripts/check-publish-recency asks scripts/tag-names for the tag spelling" \
    "reconstructing the name means looking for a tag the publish job never creates" \
    "reproduce: grep -n tag-names scripts/check-publish-recency"
fi

#---------------------------------------------------------------------------#
# 6. The wiring. Each workflow runs the check that sees the other's silence.
#---------------------------------------------------------------------------#
for want in check-publish-recency check-schedules-fired; do
  if grep -q "scripts/$want" "$WATCH_WF"; then
    ok "freshness-publish.yml runs scripts/$want"
  else
    fail "freshness-publish.yml runs scripts/$want" \
      "the watcher must read both the registry and the run list" \
      "reproduce: grep -n scripts/ .github/workflows/freshness-publish.yml"
  fi
done

# ⛔ Running both checks is not the same as acting on them.
#
# Neither check step exits non-zero on a stop: they record an rc and carry on,
# deliberately, because stopping at the first would hide the second and the two
# answer different questions. That makes a later step the only thing that turns
# a stop into a failed run. Without it the workflow runs both checks, prints
# "the publish has stopped" in its own log, and goes green.
#
# ⚠ Found by review 24. The assertion above passed the whole time.
verdict="$(awk '
  /^      - name: Take the verdict$/ { instep = 1; next }
  /^      - name: / { instep = 0 }
  instep { print }
' "$WATCH_WF")"

if [ -z "$verdict" ]; then
  fail "freshness-publish.yml acts on both check results" \
    "there is no step that reads the two outcomes" \
    "⛔ without one the workflow is green while reporting that the publish stopped" \
    "reproduce: grep -n 'Take the verdict' .github/workflows/freshness-publish.yml"
elif printf '%s\n' "$verdict" | grep -q 'steps.recency.outputs.rc' \
  && printf '%s\n' "$verdict" | grep -q 'steps.schedules.outputs.rc' \
  && printf '%s\n' "$verdict" | grep -q 'exit 1'; then
  ok "freshness-publish.yml acts on both check results"
else
  fail "freshness-publish.yml acts on both check results" \
    "the verdict step must read both outputs and exit non-zero" \
    "it reads: $(printf '%s' "$verdict" | tr '\n' ' ' | cut -c1-160)" \
    "reproduce: sed -n '/Take the verdict/,\$p' .github/workflows/freshness-publish.yml"
fi

if grep -q 'scripts/check-schedules-fired' "$PUBLISH_WF"; then
  ok "build-deploy.yml runs scripts/check-schedules-fired"
else
  fail "build-deploy.yml runs scripts/check-schedules-fired" \
    "without it nothing notices when the watcher's own schedule stops" \
    "reproduce: grep -n scripts/check-schedules-fired .github/workflows/build-deploy.yml"
fi

# ⛔ The watchdog job must gate nothing. A broken alarm that blocks a publish is
# worse than the silence it was added to break.
watchdog_block="$(awk '
  /^  watchdog:$/ { injob = 1; next }
  /^  [a-z_-]+:$/ { injob = 0 }
  injob { print }
' "$PUBLISH_WF")"

if [ -z "$watchdog_block" ]; then
  fail "build-deploy.yml has a watchdog job" \
    "reproduce: grep -n 'watchdog:' .github/workflows/build-deploy.yml"
elif printf '%s\n' "$watchdog_block" | grep -q 'needs:'; then
  fail "the watchdog job gates nothing and is gated by nothing" \
    "it declares needs:, so a failure upstream stops the alarm from reporting" \
    "reproduce: sed -n '/^  watchdog:/,/^  [a-z]/p' .github/workflows/build-deploy.yml"
else
  ok "the watchdog job declares no needs, so it neither gates nor is gated"
fi

if printf '%s\n' "$watchdog_block" | grep -q 'actions: read'; then
  ok "the watchdog job asks for actions: read and nothing more"
else
  fail "the watchdog job asks for actions: read" \
    "reading the run list of every workflow is what the check does" \
    "reproduce: sed -n '/^  watchdog:/,/^  [a-z]/p' .github/workflows/build-deploy.yml"
fi

# Nothing may declare needs: watchdog, which would make the alarm a gate from
# the other side.
#
# ⚠ Comments are stripped first. The comment above the watchdog job says the
# words "needs" and "watchdog" in the course of explaining why it has neither,
# and a scan that reads prose as configuration fails on its own documentation.
gates="$(awk '
  { line = $0; sub(/#.*$/, "", line) }
  line ~ /needs:.*watchdog/ { printf "%d: %s\n", NR, line }
' "$PUBLISH_WF")"

if [ -z "$gates" ]; then
  ok "no job in build-deploy.yml needs the watchdog"
else
  fail "no job in build-deploy.yml needs the watchdog" \
    "found: $(printf '%s' "$gates" | tr '\n' ' ')" \
    "a job gated on the alarm makes a broken alarm stop the publish" \
    "reproduce: grep -n 'needs:.*watchdog' .github/workflows/build-deploy.yml"
fi

summary
