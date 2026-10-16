#!/usr/bin/env bash
#
# Run the test suites and print TAP.
#
#   tests/run.sh [-j N] SUITE [FILE ...]
#   tests/run.sh --list SUITE
#
#   SUITE   static    the tree, with no network and no container runtime
#           network   live reads of mirrors and registries
#           image     one built image; needs IMAGE and PLATFORM
#           all       static, network and image, in that order
#   FILE    one file of SUITE: its basename with or without .sh, its path,
#           or its number when one file starts with it (51 for 51-*.sh).
#           With no FILE, every tests/SUITE/*.sh runs. SUITE all takes no FILE.
#   -j N    run N files at once (default 1). The output of each file stays
#           together, and the files print in file order.
#   --list  print the basename of each file of SUITE, one per line.
#
# Example:
#   IMAGE=ghcr.io/pkgforge-dev/archlinux:latest PLATFORM=linux/riscv64 tests/run.sh image
#
# A file fails when it exits non-zero, prints no TAP plan line (1..N), or does
# not end within its deadline. The deadline is TESTS_FILE_TIMEOUT seconds; the
# default is 600 for static and network, 1800 for image (emulated ports are
# slow). It is shorter than the timeout-minutes of each CI job, so a file that
# hangs is named in the log.
#
# ⭐ When the run stops early (INT, TERM or an error), the output of each file
# that started is printed before the exit. This includes the files that did
# not end.
#
# Exit status: 0 every file passed, 1 a file failed or no file ran, 2 usage.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

SUITES="static network image"

usage() {
  echo "usage: tests/run.sh [-j N] static|network|image|all [FILE ...]" >&2
  echo "       tests/run.sh --list static|network|image" >&2
  exit 2
}

list=0
jobs=1
while [ "$#" -gt 0 ]; do
  case "$1" in
    --list)
      list=1
      shift
      ;;
    -j)
      [ "$#" -ge 2 ] || usage
      jobs="$2"
      shift 2
      ;;
    -j*)
      jobs="${1#-j}"
      shift
      ;;
    -h | --help) usage ;;
    --)
      shift
      break
      ;;
    -*) usage ;;
    *) break ;;
  esac
done
case "$jobs" in
  '' | *[!0-9]* | 0*) usage ;;
esac
case "${TESTS_FILE_TIMEOUT:-}" in
  '') ;;
  *[!0-9]* | 0*)
    echo "tests/run.sh: TESTS_FILE_TIMEOUT is not a whole number of seconds above 0: $TESTS_FILE_TIMEOUT" >&2
    exit 2
    ;;
esac

[ "$#" -ge 1 ] || usage
suite="$1"
shift
names=("$@")

case "$suite" in
  all)
    [ "$list" -eq 0 ] && [ "${#names[@]}" -eq 0 ] || usage
    suites="$SUITES"
    ;;
  *)
    case " $SUITES " in
      *" $suite "*) suites="$suite" ;;
      *) usage ;;
    esac
    ;;
esac
if [ "$list" -eq 1 ] && [ "${#names[@]}" -gt 0 ]; then
  usage
fi

# files_of SUITE -> the path of each test file of SUITE, sorted
files_of() {
  local t
  for t in "$REPO_ROOT/tests/$1"/*.sh; do
    [ -e "$t" ] || continue
    printf '%s\n' "$t"
  done
}

if [ "$list" -eq 1 ]; then
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    basename "$t"
  done <<< "$(files_of "$suite")"
  exit 0
fi

# The FILE arguments as basenames with .sh. An unknown name is a usage error.
wanted=" "
for n in "${names[@]}"; do
  n="$(basename "$n")"
  case "$n" in
    *.sh) ;;
    *) n="$n.sh" ;;
  esac
  if [ ! -f "$REPO_ROOT/tests/$suite/$n" ]; then
    # A number names the one file that starts with it: 51 is 51-*.sh.
    match=()
    for t in "$REPO_ROOT/tests/$suite/${n%.sh}"-*.sh; do
      if [ -e "$t" ]; then
        match+=("$(basename "$t")")
      fi
    done
    if [ "${#match[@]}" -eq 1 ]; then
      n="${match[0]}"
    fi
  fi
  if [ ! -f "$REPO_ROOT/tests/$suite/$n" ]; then
    echo "tests/run.sh: no file $n in tests/$suite" >&2
    echo "  the files there:" >&2
    files_of "$suite" | sed "s|^$REPO_ROOT/|    |" >&2
    exit 2
  fi
  wanted="$wanted$n "
done

files=()
labels=()
limits=()
for s in $suites; do
  case "$s" in
    image) limit="${TESTS_FILE_TIMEOUT:-1800}" ;;
    *) limit="${TESTS_FILE_TIMEOUT:-600}" ;;
  esac
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    n="$(basename "$t")"
    if [ "${#names[@]}" -gt 0 ]; then
      case "$wanted" in
        *" $n "*) ;;
        *) continue ;;
      esac
    fi
    files+=("$t")
    labels+=("$s/$n")
    limits+=("$limit")
  done <<< "$(files_of "$s")"
done

case " $suites " in
  *" image "*)
    if [ "${#files[@]}" -gt 0 ]; then
      : "${IMAGE:?the image suite needs IMAGE set}"
      : "${PLATFORM:?the image suite needs PLATFORM set, for example linux/riscv64}"
    fi
    ;;
esac

if [ "${#files[@]}" -eq 0 ]; then
  printf '\n# ===== summary =====\n'
  printf '# no test file ran for suite: %s\n' "$suites"
  exit 1
fi

# The deadline of a file comes from timeout(1) of coreutils. ⚠ With no timeout
# on PATH, the files run with no deadline, and the run says so.
use_timeout=1
if ! command -v timeout > /dev/null; then
  use_timeout=0
  echo "tests/run.sh: no timeout command on PATH, so no test file has a deadline" >&2
fi

# Each file writes its output to OUT/<index>.out and its status and duration
# to OUT/<index>.rc. The directory is under TMPDIR, never in the tree, so a
# static test that scans the tree does not see it.
out="$(mktemp -d "${TMPDIR:-/tmp}/tests-run.XXXXXX")"
all_ended=0
n_started=0
failed_names=()
next=0

# stop_jobs: after an early exit, stop each file that started and did not
# end. A file that ended has its status file, and is not stopped.
#
# ⚠ timeout(1) runs a file in a process group of its own, so a signal to the
# group of this script does not reach the file. TERM to timeout reaches the
# whole group of the file.
stop_jobs() {
  local k pid
  [ "$all_ended" -eq 0 ] || return 0
  for ((k = 0; k < n_started; k++)); do
    [ ! -f "$out/$k.rc" ] || continue
    [ -s "$out/$k.pid" ] || continue
    read -r pid < "$out/$k.pid"
    if ! kill "$pid" 2> "$out/kill.err"; then
      # A file that ends between the check and the stop is not an error.
      awk -v l="${labels[$k]}" '!/[Nn]o such process/ { print "tests/run.sh: could not stop " l ": " $0 }' \
        "$out/kill.err" >&2
    fi
  done
}

# report INDEX: print the output of one file and judge it.
report() {
  local i="$1" label="${labels[$1]}" rc=missing secs=0 verdict=ok
  printf '\n# ===== %s =====\n' "$label"
  if [ -f "$out/$i.out" ]; then
    cat "$out/$i.out"
  fi
  if [ -f "$out/$i.rc" ]; then
    read -r rc secs < "$out/$i.rc"
  fi
  case "$rc" in
    0)
      if ! grep -Eq '^1\.\.[0-9]+' "$out/$i.out"; then
        # The harness fails a file that reaches summary with no assertion. A
        # file that never reaches summary prints no plan, and can still exit 0.
        verdict="failed, no TAP plan line, so it asserted nothing"
      fi
      ;;
    missing) verdict="failed, it did not end before the run stopped" ;;
    124 | 137)
      verdict="failed, exit $rc"
      if [ "$use_timeout" -eq 1 ]; then
        verdict="failed, it did not end within ${limits[$i]} s (TESTS_FILE_TIMEOUT), so it was stopped"
      fi
      ;;
    *) verdict="failed, exit $rc" ;;
  esac
  if [ "$verdict" != ok ]; then
    failed_names+=("$label")
  fi
  printf '# ----- %s: %s, %d s\n' "$label" "$verdict" "$secs"
}

# flush: print each ended file that is next in file order.
flush() {
  while [ "$next" -lt "${#files[@]}" ] && [ -f "$out/$next.rc" ]; do
    report "$next"
    next=$((next + 1))
  done
}

# flush_upto N: print each file before index N that is not printed yet, ended
# or not.
flush_upto() {
  while [ "$next" -lt "$1" ]; do
    report "$next"
    next=$((next + 1))
  done
}

print_failed() {
  local n
  for n in "${failed_names[@]}"; do
    printf '# failed: %s, reproduce: tests/run.sh %s %s\n' "$n" "${n%%/*}" "${n#*/}"
  done
}

# on_exit: after an early exit, stop the files that run, then print each file
# that started, with the output it has, and the summary. Then remove OUT.
on_exit() {
  local rc=$?
  stop_jobs
  if [ "$all_ended" -eq 0 ] && [ "$n_started" -gt 0 ]; then
    flush_upto "$n_started"
    printf '\n# ===== summary =====\n'
    printf '# the run stopped (exit %s) after %d of %d test files started\n' \
      "$rc" "$n_started" "${#files[@]}"
    print_failed
  fi
  rm -rf "$out"
}
trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# run_one INDEX PATH LIMIT: run one test file with no stdin, for LIMIT
# seconds at most. OUT/INDEX.pid is the process that stop_jobs stops. The
# status file is written last and moved into place, so its presence means the
# file ended.
run_one() {
  local start="$SECONDS" rc=0
  if [ "$use_timeout" -eq 1 ]; then
    timeout -k 10 "$3" bash "$2" > "$out/$1.out" 2>&1 < /dev/null &
  else
    bash "$2" > "$out/$1.out" 2>&1 < /dev/null &
  fi
  printf '%s\n' "$!" > "$out/$1.pid"
  wait "$!" || rc=$?
  printf '%s %s\n' "$rc" "$((SECONDS - start))" > "$out/$1.part"
  mv "$out/$1.part" "$out/$1.rc"
}

started="$SECONDS"
running=0
i=0
while [ "$i" -lt "${#files[@]}" ]; do
  while [ "$running" -ge "$jobs" ]; do
    wait_rc=0
    wait -n || wait_rc=$?
    running=$((running - 1))
    if [ "$wait_rc" -ne 0 ]; then
      echo "tests/run.sh: a test runner process ended with status $wait_rc" >&2
    fi
    flush
  done
  run_one "$i" "${files[$i]}" "${limits[$i]}" &
  running=$((running + 1))
  i=$((i + 1))
  n_started="$i"
done
wait
all_ended=1
flush_upto "${#files[@]}"

printf '\n# ===== summary =====\n'
printf '# test files: %d, failed: %d, jobs: %d, %d s\n' \
  "${#files[@]}" "${#failed_names[@]}" "$jobs" "$((SECONDS - started))"
print_failed
[ "${#failed_names[@]}" -eq 0 ]
