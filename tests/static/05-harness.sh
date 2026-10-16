#!/usr/bin/env bash
#
# Check tests/lib/harness.sh and tests/run.sh.
#
# ⛔ This file does not report through the harness. A broken reporter cannot
# report its own fault, so this file keeps its own counters and prints its own
# TAP. ci.yml runs it with bash before tests/run.sh, for the same reason.
#
# Each harness case runs in a subshell. Each runner case runs a copy of
# tests/run.sh in a temporary tree with known test files.
# shellcheck disable=SC2016 # the scripts given to in_harness expand there
set -uo pipefail

HARNESS="${REPO_ROOT:?05-harness.sh needs REPO_ROOT}/tests/lib/harness.sh"
RUNNER="$REPO_ROOT/tests/run.sh"

run=0
failed=0

# check DESC EXPECTED ACTUAL
check() {
  run=$((run + 1))
  if [ "$2" = "$3" ]; then
    printf 'ok %d - %s\n' "$run" "$1"
  else
    failed=$((failed + 1))
    printf 'not ok %d - %s\n' "$run" "$1"
    printf '#   expected: %s\n' "$2"
    printf '#   actual:   %s\n' "$3"
    printf '#   reproduce: %s\n' "REPO_ROOT=\$PWD bash tests/static/05-harness.sh"
  fi
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# in_harness SCRIPT: run SCRIPT with the harness sourced. Prints
# "<rc>|<stdout, newlines as ;>". stderr goes to $work/stderr.
in_harness() {
  local out rc=0
  out="$(REPO_ROOT="$REPO_ROOT" bash -c '
    set -uo pipefail
    . "$0"
    '"$1"'
  ' "$HARNESS" 2> "$work/stderr")" || rc=$?
  printf '%s|%s' "$rc" "$(printf '%s' "$out" | tr '\n' ';')"
}

#---------------------------------------------------------------------------#
# ok, not_ok and fail number and count
#---------------------------------------------------------------------------#
check "ok prints TAP and numbers from 1" \
  "0|ok 1 - first;ok 2 - second" \
  "$(in_harness 'ok first; ok second')"

check "not_ok prints the not ok form and keeps the same counter" \
  "0|ok 1 - a;not ok 2 - b;ok 3 - c" \
  "$(in_harness 'ok a; not_ok b; ok c')"

check "fail prints its diagnostics as TAP comments" \
  "0|not ok 1 - broken;#   why;#   reproduce: run it" \
  "$(in_harness 'fail broken why "reproduce: run it"')"

check "check_eq passes when the values are equal" \
  "0|ok 1 - same" \
  "$(in_harness 'check_eq same a a "run it"')"

check "check_eq fails and prints both values and the reproduce line" \
  "0|not ok 1 - differ;#   want: a;#   got:  b;#   reproduce: run it" \
  "$(in_harness 'check_eq differ a b "run it"')"

#---------------------------------------------------------------------------#
# summary gives the exit status of every test file
#---------------------------------------------------------------------------#
check "summary returns 0 and reports the count when all passed" \
  "0|ok 1 - a;ok 2 - b;1..2;# passed 2 of 2" \
  "$(in_harness 'ok a; ok b; summary')"

check "summary returns 1 when one assertion failed" \
  "1|ok 1 - a;not ok 2 - b;1..2;# failed 1 of 2" \
  "$(in_harness 'ok a; not_ok b; summary')"

check "summary returns 1 when no assertion ran" \
  "1|1..0;# no assertions ran, which is itself a failure" \
  "$(in_harness 'summary')"

#---------------------------------------------------------------------------#
# grep_matches tells "no match" and "could not read" apart
#---------------------------------------------------------------------------#
printf 'alpha\nbeta\ngamma\n' > "$work/f"

check "grep_matches prints numbered matches and returns 0" \
  "0|2:beta" \
  "$(in_harness 'grep_matches "beta" "'"$work"'/f"')"

check "grep_matches returns 0 with no output when nothing matched" \
  "0|" \
  "$(in_harness 'grep_matches "nothing_here" "'"$work"'/f"')"

check "grep_matches returns 2 when the file cannot be read" \
  "2|" \
  "$(in_harness 'grep_matches "beta" "'"$work"'/absent"')"

#---------------------------------------------------------------------------#
# need_tool skips, or fails under TESTS_REQUIRE_TOOLS=1
#---------------------------------------------------------------------------#
check "need_tool returns 0 and prints nothing when the tool is on PATH" \
  "0|0" \
  "$(in_harness 'rc=0; need_tool bash || rc=$?; printf "%s" "$rc"')"

check "need_tool records a skip and returns 1 when a tool is missing" \
  "0|ok 1 - # SKIP missing: no-such-tool-here;1;1..1;# passed 1 of 1" \
  "$(in_harness 'unset TESTS_REQUIRE_TOOLS; rc=0; need_tool bash no-such-tool-here || rc=$?; echo "$rc"; summary')"

check "need_tool records a failure under TESTS_REQUIRE_TOOLS=1" \
  "1|not ok 1 - tools are on PATH: no-such-tool-here;#   TESTS_REQUIRE_TOOLS=1 makes a missing tool a failure;#   reproduce: command -v no-such-tool-here;1;1..1;# failed 1 of 1" \
  "$(in_harness 'TESTS_REQUIRE_TOOLS=1; rc=0; need_tool no-such-tool-here || rc=$?; echo "$rc"; summary')"

#---------------------------------------------------------------------------#
# fixture_dir, image_digest, host_path and the REPO_ROOT guard
#---------------------------------------------------------------------------#
fd="$(REPO_ROOT=/r bash -c '. "$1"; fixture_dir' 42-some-test.sh "$HARNESS")"
check "fixture_dir names tests/fixtures/<test file name without .sh>" "/r/tests/fixtures/42-some-test" "$fd"

unset_rc=0
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
(unset REPO_ROOT; . "$HARNESS") > "$work/unset.out" 2>&1 || unset_rc=$?
check "sourcing the harness without REPO_ROOT exits 2" "2" "$unset_rc"

d="$(printf 'a%.0s' $(seq 1 64))"
check "image_digest reads the digest from the reference, with no runtime" \
  "0|sha256:$d" \
  "$(in_harness 'RUNTIME=/nonexistent-runtime; image_digest "example.com/x@sha256:'"$d"'"')"

hp="$(in_harness "host_path /tmp")"
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*)
    case "$hp" in
      0\|*:*) r="a windows path" ;;
      *) r="$hp" ;;
    esac
    check "host_path converts to a windows path on MSYS" "a windows path" "$r"
    ;;
  *)
    check "host_path keeps the path unchanged on Linux" "0|/tmp" "$hp"
    ;;
esac

#---------------------------------------------------------------------------#
# yaml_json reads YAML with either yq
#---------------------------------------------------------------------------#
if command -v yq > /dev/null && command -v jq > /dev/null; then
  printf 'on:\n  push:\njobs:\n  a:\n    runs-on: x\n' > "$work/w.yml"
  check "yaml_json reads a workflow, and on stays a key" \
    "0|on,jobs,a,x" \
    "$(in_harness 'yaml_json "'"$work"'/w.yml" | jq -r "[(keys_unsorted[]), (.jobs | keys[]), .jobs.a[\"runs-on\"]] | join(\",\")"')"
elif [ "${TESTS_REQUIRE_TOOLS:-0}" = 1 ]; then
  check "yq and jq are on PATH for yaml_json (TESTS_REQUIRE_TOOLS=1)" present missing
else
  run=$((run + 1))
  printf 'ok %d - # SKIP yq or jq is missing, so yaml_json is not checked\n' "$run"
fi

#---------------------------------------------------------------------------#
# tests/run.sh, run in a temporary tree
#---------------------------------------------------------------------------#
tree="$work/tree"
mkdir -p "$tree/tests/lib" "$tree/tests/static" "$tree/tests/network" "$tree/tests/image"
cp "$RUNNER" "$tree/tests/run.sh"
cp "$HARNESS" "$tree/tests/lib/harness.sh"

# passing FILE: a test file with one passing assertion that logs its name.
passing() {
  cat > "$1" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
. "$REPO_ROOT/tests/lib/harness.sh"
printf '%s\n' "$(basename "$0")" >> "$REPO_ROOT/ran.log"
ok "a test that passes"
summary
EOF
}
passing "$tree/tests/static/10-first.sh"
passing "$tree/tests/static/20-second.sh"
passing "$tree/tests/network/10-probe.sh"
: > "$tree/tests/static/notes.txt"

# runner ARGS...: run the copy with no REPO_ROOT, IMAGE or PLATFORM from the
# caller. Sets rc, out (stdout and stderr) and ran (the
# files that ran, space separated).
runner() {
  rc=0
  : > "$tree/ran.log"
  out="$(env -u IMAGE -u PLATFORM -u REPO_ROOT bash "$tree/tests/run.sh" "$@" 2>&1)" || rc=$?
  ran="$(tr '\n' ' ' < "$tree/ran.log")"
}
lines() { printf '%s\n' "$out" | tr '\n' ' ' | sed 's/ $//'; }

runner --list static
check "--list static names each tests/static/*.sh, in order" "10-first.sh 20-second.sh" "$(lines)"
check "--list static exits 0" 0 "$rc"

runner static
check "static runs every file of the suite" "10-first.sh 20-second.sh " "$ran"
check "static exits 0 when every file passes" 0 "$rc"

runner network
check "network runs the files of the network suite" "10-probe.sh " "$ran"

runner static 20-second.sh
check "a named file runs alone" "20-second.sh " "$ran"
runner static 20-second
check "a named file runs alone, named without .sh" "20-second.sh " "$ran"
runner static "$tree/tests/static/10-first.sh" 20-second
check "two named files run, in file order" "10-first.sh 20-second.sh " "$ran"
runner static 20
check "a number runs the one file that starts with it" "20-second.sh " "$ran"
runner static 30-absent
check "a name that is not a file of the suite is a usage error" 2 "$rc"
runner all 10-first
check "all with a FILE is a usage error" 2 "$rc"
runner -j 0 static
check "-j 0 is a usage error" 2 "$rc"
runner nosuchsuite
check "an unknown suite is a usage error" 2 "$rc"
runner image
check "the image suite with no IMAGE runs nothing and fails" "1 " "$rc $ran"

passing "$tree/tests/image/10-look.sh"
rc=0
out="$(env -u REPO_ROOT IMAGE=x PLATFORM=linux/amd64 bash "$tree/tests/run.sh" image 2>&1)" || rc=$?
check "the image suite runs with IMAGE and PLATFORM set" 0 "$rc"
rc=0
: > "$tree/ran.log"
out="$(env -u REPO_ROOT IMAGE=x PLATFORM=linux/amd64 bash "$tree/tests/run.sh" all 2>&1)" || rc=$?
check "all runs the static, network and image files, in that order" \
  "0 10-first.sh 20-second.sh 10-probe.sh 10-look.sh " "$rc $(tr '\n' ' ' < "$tree/ran.log")"
runner image
check "the image suite stops when IMAGE is not set" "1 " "$rc $ran"
rm -f "$tree/tests/image/10-look.sh"
runner image
check "a suite with no file fails" 1 "$rc"

cat > "$tree/tests/static/15-root.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
. "$REPO_ROOT/tests/lib/harness.sh"
check_eq "REPO_ROOT is the root of the tree" "$EXPECT_ROOT" "$REPO_ROOT" "tests/run.sh static 15-root"
summary
EOF
rc=0
out="$(env -u REPO_ROOT EXPECT_ROOT="$tree" bash "$tree/tests/run.sh" static 15-root 2>&1)" || rc=$?
check "a test file gets REPO_ROOT, the root of the tree" 0 "$rc"
rm -f "$tree/tests/static/15-root.sh"

cat > "$tree/tests/static/30-fails.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
. "$REPO_ROOT/tests/lib/harness.sh"
fail "a test that fails" "reproduce: tests/run.sh static 30-fails"
summary
EOF
runner static
check "a failing file fails the run" 1 "$rc"
check "and every other file still runs" "10-first.sh 20-second.sh " "$ran"
case "$out" in
  *"failed: static/30-fails.sh, reproduce: tests/run.sh static 30-fails.sh"*) r=named ;;
  *) r="$(printf '%s\n' "$out" | tail -n 3 | tr '\n' ' ')" ;;
esac
check "the summary names the failed file and the command that runs it alone" named "$r"
rm -f "$tree/tests/static/30-fails.sh"

# A file that exits 0 and prints no plan asserted nothing.
printf '#!/usr/bin/env bash\nexit 0\n' > "$tree/tests/static/30-silent.sh"
runner static
check "a file that exits 0 with no TAP plan line fails the run" 1 "$rc"
case "$out" in
  *"failed: static/30-silent.sh"*) r=named ;;
  *) r="$(printf '%s\n' "$out" | tail -n 3 | tr '\n' ' ')" ;;
esac
check "and the summary names that file" named "$r"
rm -f "$tree/tests/static/30-silent.sh"

#---------------------------------------------------------------------------#
# -j N: files run at once, and each file's output stays together, in order
#---------------------------------------------------------------------------#
rm -f "$tree/tests/static/"*.sh
# 10-first marks its start and its end. 20-second waits up to 10 s for
# 10-first to start, then records an overlap when 10-first has not ended.
# With WAIT=1, 10-first waits up to 10 s for 20-second to start. 20-second
# and 30-third print three lines each, with pauses between them.
cat > "$tree/tests/static/10-first.sh" << 'EOF2'
#!/usr/bin/env bash
set -euo pipefail
. "$REPO_ROOT/tests/lib/harness.sh"
: > "$REPO_ROOT/10.started"
n=0
while [ "${WAIT:-0}" = 1 ] && [ ! -e "$REPO_ROOT/20.started" ] && [ "$n" -lt 100 ]; do
  sleep 0.1
  n=$((n + 1))
done
sleep 0.3
: > "$REPO_ROOT/10.ended"
ok "10-first"
summary
EOF2
for f in 20-second 30-third; do
  cat > "$tree/tests/static/$f.sh" << EOF2
#!/usr/bin/env bash
set -euo pipefail
. "\$REPO_ROOT/tests/lib/harness.sh"
if [ "$f" = 20-second ]; then
  : > "\$REPO_ROOT/20.started"
  n=0
  while [ ! -e "\$REPO_ROOT/10.started" ] && [ "\$n" -lt 100 ]; do
    sleep 0.1
    n=\$((n + 1))
  done
  if [ -e "\$REPO_ROOT/10.started" ] && [ ! -e "\$REPO_ROOT/10.ended" ]; then
    : > "\$REPO_ROOT/overlap"
  fi
fi
ok "$f line 1"
sleep 0.2
ok "$f line 2"
sleep 0.2
ok "$f line 3"
summary
EOF2
done

# blocks: the file number of each TAP line, in output order, each run of one
# number shown once. Together and in order: "10 20 30".
blocks() {
  printf '%s\n' "$out" | awk '
    /^# ===== static\// { f = $3; sub(/^static\//, "", f); sub(/-.*/, "", f); next }
    /^(not )?ok / && f != "" { if (f != last) { printf "%s ", f; last = f } }
  ' | sed 's/ $//'
}
# jobs_run ARGS...: a clean run of the copy with ARGS. Sets overlap.
jobs_run() {
  rm -f "$tree/10.started" "$tree/10.ended" "$tree/20.started" "$tree/overlap"
  runner "$@"
  overlap=no
  if [ -e "$tree/overlap" ]; then
    overlap=yes
  fi
}

WAIT=1 jobs_run -j 3 static
check "-j 3: the run passes" 0 "$rc"
check "-j 3: 20-second runs while 10-first runs" yes "$overlap"
check "-j 3: the output of each file stays together, in file order" "10 20 30" "$(blocks)"

jobs_run -j1 static
check "-j1: the run passes" 0 "$rc"
check "-j1: 20-second starts after 10-first ends" no "$overlap"
check "-j1: the output of each file stays together, in file order" "10 20 30" "$(blocks)"

#---------------------------------------------------------------------------#
# A file that hangs: the deadline stops it, and an early stop of the run
# still prints the output of every file that started.
#---------------------------------------------------------------------------#
rm -f "$tree/tests/static/"*.sh
passing "$tree/tests/static/10-first.sh"
passing "$tree/tests/static/30-third.sh"
# 20-hang prints one assertion, starts a sleep that writes its pid, and waits.
cat > "$tree/tests/static/20-hang.sh" << 'EOF2'
#!/usr/bin/env bash
set -euo pipefail
. "$REPO_ROOT/tests/lib/harness.sh"
ok "before the hang"
sleep 1000 &
printf '%s\n' "$!" > "$REPO_ROOT/hang.pid"
wait
summary
EOF2
# gone PIDFILE: "gone" when the process of PIDFILE ends within 5 s
gone() {
  local n=0 pid
  read -r pid < "$1" || return 0
  while [ -d "/proc/$pid" ] && [ "$n" -lt 50 ]; do
    sleep 0.1
    n=$((n + 1))
  done
  if [ -d "/proc/$pid" ]; then
    kill "$pid"
    echo "still running"
  else
    echo gone
  fi
}
has_line() {
  case "$out" in
    *"$1"*) echo yes ;;
    *) echo no ;;
  esac
}

if command -v timeout > /dev/null && [ -d /proc/self ]; then
  rm -f "$tree/hang.pid"
  t0="$SECONDS"
  TESTS_FILE_TIMEOUT=2 runner -j 3 static
  took=$((SECONDS - t0))
  check "a file that does not end within TESTS_FILE_TIMEOUT fails the run" 1 "$rc"
  check "the run ends within 30 s with a deadline of 2 s" yes "$(if [ "$took" -lt 30 ]; then echo yes; else echo "no, $took s"; fi)"
  check "the summary names the file that did not end" yes "$(has_line 'failed: static/20-hang.sh, reproduce: tests/run.sh static 20-hang.sh')"
  check "the output of that file up to the deadline is printed" yes "$(has_line 'ok 1 - before the hang')"
  # -j 3 runs the files at once, so they log in any order.
  check "the other files still run" "10-first.sh 30-third.sh" "$(tr ' ' '\n' <<< "$ran" | awk 'NF' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
  check "the deadline stops the processes that the file started" gone "$(gone "$tree/hang.pid")"

  # The run itself is stopped by TERM after 3 s, while 20-hang waits.
  rm -f "$tree/hang.pid"
  rc=0
  : > "$tree/ran.log"
  out="$(env -u IMAGE -u PLATFORM -u REPO_ROOT TESTS_FILE_TIMEOUT=100 \
    timeout -k 5 -s TERM 3 bash "$tree/tests/run.sh" -j 3 static 2>&1)" || rc=$?
  check "TERM stops the run (exit of timeout)" 124 "$rc"
  check "after TERM, the output of a file that ended before is printed" yes "$(has_line '# ===== static/30-third.sh =====')"
  check "after TERM, the partial output of the file that did not end is printed" yes "$(has_line 'ok 1 - before the hang')"
  check "after TERM, the summary names the file that did not end" yes "$(has_line 'failed: static/20-hang.sh')"
  check "after TERM, no stop is tried on a file that ended" no "$(has_line 'No such process')"
  check "after TERM, the processes of the file that did not end stop" gone "$(gone "$tree/hang.pid")"
  TESTS_FILE_TIMEOUT=abc runner static 10-first
  check "a TESTS_FILE_TIMEOUT that is not a number is a usage error" 2 "$rc"
else
  run=$((run + 1))
  printf 'ok %d - # SKIP timeout or /proc is missing, so the deadline is not checked\n' "$run"
fi
rm -f "$tree/tests/static/20-hang.sh"

printf '1..%d\n' "$run"
if [ "$failed" -gt 0 ]; then
  printf '# failed %d of %d\n' "$failed" "$run"
  exit 1
fi
printf '# passed %d of %d\n' "$run" "$run"
