#!/usr/bin/env bash
#
# Check that each failing assertion tells the reader how to see it again.
#
# Each call of fail in tests/ (not tests/fixtures) carries an argument that
# starts with "reproduce:". check_eq of the harness writes that line itself.
# A call starts a line, or comes after ), ;, &&, ||, then, else or do.
#
# ⚠ A call can go on over lines that end in a backslash, so the whole call is
# read before it is judged. The definition of fail in the harness is not a
# call.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

cd "$REPO_ROOT"
mapfile -t files < <(find tests -path tests/fixtures -prune -o -type f -name '*.sh' -print | LC_ALL=C sort)
if [ "${#files[@]}" -eq 0 ]; then
  fail "there are test files to read" "reproduce: find tests -name '*.sh'"
  summary
  exit 1
fi

# Each call of fail as "FILE:LINE<TAB>yes" when it carries reproduce:, else
# "FILE:LINE<TAB>no".
sites="$(awk '
  function flush() {
    if (!collecting) return
    printf "%s:%d\t%s\n", file, start, (body ~ /reproduce:/ ? "yes" : "no")
    collecting = 0
    body = ""
  }
  FNR == 1 { flush() }
  {
    if (collecting) {
      body = body $0
      if ($0 !~ /\\[[:space:]]*$/) flush()
      next
    }
    if ($0 ~ /^[[:space:]]*#/) next
    if (($0 ~ /^[[:space:]]*fail[[:space:]]/ && $0 !~ /^[[:space:]]*fail[[:space:]]*\(/) ||
        $0 ~ /(\)|;|&&|[|][|])[[:space:]]*fail[[:space:]]/ ||
        $0 ~ /(^|[[:space:]])(then|else|do)[[:space:]]+fail[[:space:]]/) {
      collecting = 1
      file = FILENAME
      start = FNR
      body = $0
      if ($0 !~ /\\[[:space:]]*$/) flush()
    }
  }
  END { flush() }' "${files[@]}")"

total=0
missing=""
while IFS=$'\t' read -r where has; do
  [ -n "$where" ] || continue
  total=$((total + 1))
  [ "$has" = yes ] || missing="$missing $where"
done <<< "$sites"

if [ "$total" -eq 0 ]; then
  fail "the files call fail" "found no call, so this checked nothing" \
    "reproduce: grep -rn '^[[:space:]]*fail ' tests"
else
  check_eq "each of $total fail calls in tests/ carries a reproduce: line" "" "$missing" \
    "add a last argument: \"reproduce: <the command>\""
fi

summary
