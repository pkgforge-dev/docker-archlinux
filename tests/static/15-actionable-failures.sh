#!/usr/bin/env bash
#
# Every failing assertion has to say how to see the failure again.
#
# A test that prints only what it expected leaves the reader to reconstruct the
# command from the source. That reconstruction is where the time goes, and it is
# work the test already did once. So every `fail` in tests/ carries a line
# starting `reproduce:` naming the command.
#
# ⚠ A call can span several lines through backslash continuation, so the whole
# call is gathered before it is judged. The definition of `fail` in the harness
# is not a call and is skipped.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

files="$(find "$REPO_ROOT/tests" -type f -name '*.sh' | sort)"
if [ -z "$files" ]; then
  fail "there are test files to check" \
    "searched: $REPO_ROOT/tests" \
    "reproduce: find tests -name '*.sh'"
  summary
  exit 1
fi

# sites FILE -> "<line>\t<yes|no>" per fail call
#
# yes means the gathered call carries a reproduce: line.
sites() {
  awk '
    function flush(  i) {
      if (!collecting) return
      printf "%d\t%s\n", start, (body ~ /reproduce:/ ? "yes" : "no")
      collecting = 0
      body = ""
    }
    {
      if (collecting) {
        body = body $0
        if ($0 !~ /\\[[:space:]]*$/) flush()
        next
      }
      # a call, not the definition
      if ($0 ~ /^[[:space:]]*fail[[:space:]]/ && $0 !~ /^[[:space:]]*fail[[:space:]]*\(/) {
        collecting = 1
        start = NR
        body = $0
        if ($0 !~ /\\[[:space:]]*$/) flush()
      }
    }
    END { flush() }
  ' "$1"
}

total=0
missing=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  rel="${f#"$REPO_ROOT/"}"
  while IFS=$'\t' read -r lineno has; do
    [ -n "$lineno" ] || continue
    total=$((total + 1))
    [ "$has" = "yes" ] || missing="$missing $rel:$lineno"
  done <<< "$(sites "$f")"
done <<< "$files"

if [ "$total" -eq 0 ]; then
  fail "at least one fail call was found to check" \
    "the scan matched nothing, so this test asserted nothing" \
    "reproduce: grep -rn '^[[:space:]]*fail ' tests"
elif [ -z "$missing" ]; then
  ok "all $total fail calls in tests/ carry a reproduce: line"
else
  n=0
  for _ in $missing; do n=$((n + 1)); done
  fail "all $total fail calls in tests/ carry a reproduce: line" \
    "$n without one:$missing" \
    "a reader who cannot re-run the check has to rebuild the command from the source" \
    "add a final argument shaped: \"reproduce: <the command>\"" \
    "reproduce: bash tests/run.sh static, which names each one"
fi

summary
