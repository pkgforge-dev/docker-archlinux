#!/usr/bin/env bash
#
# Check that no fetch can wait for ever.
#
# curl has no total deadline by default, and its connect deadline is about
# two minutes. A server that accepts the connection and then sends nothing
# holds the job until the job timeout. So:
#   - each curl call sets --connect-timeout, and --max-time or --speed-time
#   - each gpg call that reads a keyserver sets
#     --keyserver-options timeout=N, or runs under timeout
#
# Read: scripts/, bootstrap/any/usr/local/bin, the workflows and tests/ (not
# tests/fixtures). A call can go on over lines that end in a backslash, so
# the whole call is read before it is judged. Comments are not read.
#
# ⚠ A curl inside a quoted string or a here-document is text: a reproduce:
# line, or the data of a fixture. It is not judged. So a real call is never
# written inside quotes, for example as sh -c 'curl ...'.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

cd "$REPO_ROOT"
mapfile -t files < <({
  for d in scripts bootstrap/any/usr/local/bin .github/workflows; do
    [ ! -d "$d" ] || find "$d" -type f
  done
  find tests -path tests/fixtures -prune -o -type f -name '*.sh' -print
} | LC_ALL=C sort)
if [ "${#files[@]}" -eq 0 ]; then
  fail "there are files to read" "reproduce: ls scripts .github/workflows"
  summary
  exit 1
fi

# calls TOOL_REGEX: each call as "FILE:LINE<TAB>the whole call". A call
# starts where TOOL_REGEX matches outside quotes and outside a
# here-document.
calls() {
  awk -v tool="$1" '
    # bs: a backslash, made with sprintf. The test for a continued line then
    # holds no backslash that an edit can halve.
    function bs() { return sprintf("%c", 92) }
    function continued(s) { sub(/[[:space:]]+$/, "", s); return substr(s, length(s), 1) == bs() }
    # quoted(s, p): position p of s is inside single or double quotes.
    function quoted(s, p,   i, c, q, prev) {
      q = ""
      prev = ""
      for (i = 1; i < p; i++) {
        c = substr(s, i, 1)
        if (q == "" && (c == "\"" || c == "\047") && prev != bs()) q = c
        else if (q == "\047" && c == "\047") q = ""
        else if (q == "\"" && c == "\"" && prev != bs()) q = ""
        prev = c
      }
      return q != ""
    }
    function flush() {
      if (collecting) printf "%s:%d\t%s\n", file, start, body
      collecting = 0
      body = ""
    }
    FNR == 1 { flush(); eof = "" }
    # The body of a here-document is data.
    eof != "" {
      t = $0
      sub(/^[[:space:]]+/, "", t)
      if (t == eof) eof = ""
      next
    }
    {
      line = $0
      if (match(line, /<<-?[[:space:]]*["\047]?[A-Za-z_][A-Za-z0-9_]*/) && !quoted(line, RSTART)) {
        eof = substr(line, RSTART, RLENGTH)
        sub(/^<<-?[[:space:]]*["\047]?/, "", eof)
      }
      if (line ~ /^[[:space:]]*#/) line = ""
      sub(/[[:space:]]#.*$/, "", line)
      if (collecting) {
        body = body " " line
        if (!continued(line)) flush()
        next
      }
      if (match(line, tool) && !quoted(line, RSTART)) {
        collecting = 1
        file = FILENAME
        start = FNR
        body = line
        if (!continued(line)) flush()
      }
    }
    END { flush() }' "${files[@]}"
}

#---------------------------------------------------------------------------#
# curl
#---------------------------------------------------------------------------#
total=0
no_connect=""
no_deadline=""
while IFS=$'\t' read -r where body; do
  [ -n "$where" ] || continue
  total=$((total + 1))
  case "$body" in
    *--connect-timeout*) ;;
    *) no_connect="$no_connect $where" ;;
  esac
  case "$body" in
    *--max-time* | *--speed-time*) ;;
    *) no_deadline="$no_deadline $where" ;;
  esac
done <<< "$(calls '(^|[^A-Za-z0-9_-])curl[[:space:]]+-')"

if [ "$total" -eq 0 ]; then
  fail "the files call curl" "found no call, so this checked nothing" \
    "reproduce: grep -rn 'curl -' scripts .github/workflows"
else
  check_eq "each of $total curl calls sets --connect-timeout" "" "$no_connect" \
    "grep -n -A3 'curl' FILE; curl waits about two minutes to connect by default"
  check_eq "each of $total curl calls sets --max-time or --speed-time" "" "$no_deadline" \
    "grep -n -A3 'curl' FILE; curl has no total deadline by default"
fi

#---------------------------------------------------------------------------#
# gpg with a keyserver
#---------------------------------------------------------------------------#
ks_total=0
untimed=""
while IFS=$'\t' read -r where body; do
  [ -n "$where" ] || continue
  case "$body" in
    *--recv-keys* | *--refresh-keys* | *--search-keys* | *--send-keys* | *--locate-keys*) ;;
    *) continue ;;
  esac
  ks_total=$((ks_total + 1))
  case "$body" in
    *--keyserver-options*timeout=* | *timeout\ *gpg*) ;;
    *) untimed="$untimed $where" ;;
  esac
done <<< "$(calls '(^|[^A-Za-z0-9_-])(timeout[[:space:]].*)?gpg[[:space:]]+-')"

if [ "$ks_total" -eq 0 ]; then
  ok "no gpg call reads a keyserver"
else
  check_eq "each of $ks_total gpg keyserver calls has a timeout" "" "$untimed" \
    "grep -rn 'recv-keys' scripts .github/workflows; add --keyserver-options timeout=N"
fi

summary
