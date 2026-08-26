#!/usr/bin/env bash
#
# The harness itself.
#
# Every other test file reports through tests/lib/harness.sh. If `ok` miscounts,
# if `fail` forgets to mark a failure, or if `summary` returns zero when
# something failed, then every suite reports whatever it likes and a green run
# means nothing. Fourteen files were trusting it and none of them checked it.
#
# ⛔ This file deliberately does NOT use the harness to report. A test that
# checks a reporter by reporting through it cannot fail in the one case that
# matters, which is the reporter being broken. So it carries its own counters
# and prints its own TAP.
#
# Each case runs the harness in a subshell and inspects the captured output and
# the captured exit status from outside.
set -uo pipefail

HARNESS="${REPO_ROOT:?05-harness.sh needs REPO_ROOT}/tests/lib/harness.sh"

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
    printf '#   reproduce: bash tests/static/05-harness.sh\n'
  fi
}

# in_harness SCRIPT -> runs SCRIPT with the harness sourced, prints
# "<rc>|<stdout with newlines as ;>"
in_harness() {
  local out rc=0
  out="$(REPO_ROOT="$REPO_ROOT" bash -c '
    set -uo pipefail
    . "$0"
    '"$1"'
  ' "$HARNESS" 2>/dev/null)" || rc=$?
  printf '%s|%s' "$rc" "$(printf '%s' "$out" | tr '\n' ';')"
}

#---------------------------------------------------------------------------#
# ok and not_ok number and count
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

#---------------------------------------------------------------------------#
# summary is the exit status every suite depends on
#---------------------------------------------------------------------------#
check "summary returns 0 and reports the count when all passed" \
  "0|ok 1 - a;ok 2 - b;1..2;# passed 2 of 2" \
  "$(in_harness 'ok a; ok b; summary')"

check "summary returns 1 when one assertion failed" \
  "1|ok 1 - a;not ok 2 - b;1..2;# failed 1 of 2" \
  "$(in_harness 'ok a; not_ok b; summary')"

check "summary returns 1 when nothing ran at all" \
  "1|1..0;# no assertions ran, which is itself a failure" \
  "$(in_harness 'summary')"

#---------------------------------------------------------------------------#
# grep_matches has to tell three states apart
#
# A test that cannot distinguish "nothing matched" from "the file could not be
# read" passes on a missing file, which is the shape that makes a whole suite
# green against a tree that is not there.
#---------------------------------------------------------------------------#
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
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
# The harness refuses to load unconfigured
#---------------------------------------------------------------------------#
unset_rc=0
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
(unset REPO_ROOT; . "$HARNESS") >/dev/null 2>&1 || unset_rc=$?
check "sourcing the harness without REPO_ROOT exits 2" "2" "$unset_rc"

#---------------------------------------------------------------------------#
# image_digest reads a digest already in the reference, with no runtime
#
# This is the path CI takes. It must not shell out, because the two runtimes
# disagree about the field and docker errors rather than printing an empty
# value.
#---------------------------------------------------------------------------#
d="$(printf 'a%.0s' $(seq 1 64))"
check "image_digest returns the digest carried by the reference" \
  "0|sha256:$d" \
  "$(in_harness 'RUNTIME=/nonexistent-runtime; image_digest "example.com/x@sha256:'"$d"'"')"

#---------------------------------------------------------------------------#
# host_path
#---------------------------------------------------------------------------#
hp="$(in_harness "host_path /tmp")"
case "$(uname -o 2>/dev/null)" in
  Msys | Cygwin)
    # cygpath -w /tmp produces a path with a drive letter or a UNC prefix.
    case "$hp" in
      0\|*:*) r="a windows path" ;;
      *) r="$hp" ;;
    esac
    check "host_path converts to a windows path on MSYS" "a windows path" "$r"
    ;;
  *)
    check "host_path passes the path through unchanged elsewhere" "0|/tmp;" "$hp"
    ;;
esac

printf '1..%d\n' "$run"
if [ "$failed" -gt 0 ]; then
  printf '# failed %d of %d\n' "$failed" "$run"
  exit 1
fi
printf '# passed %d of %d\n' "$run" "$run"
