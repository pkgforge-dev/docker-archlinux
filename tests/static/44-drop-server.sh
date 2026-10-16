#!/usr/bin/env bash
#
# drop-server removes exactly the servers it is given, from the lists it is
# given, and refuses all else.
#
# bootstrap/any/usr/local/bin/drop-server:
#   drop-server LIST_FILE SERVER     one server from one list
#   drop-server --pairs DIR PAIRS    each LIST=SERVER pair, on DIR/LIST
# The Dockerfile runs the second form with SKIP_SERVERS. A refusal leaves the
# list as it was.
#
# $repo is a variable of pacman and stays literal in this file.
# shellcheck disable=SC2016
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

DROP="$REPO_ROOT/bootstrap/any/usr/local/bin/drop-server"
REPRO="bash tests/static/44-drop-server.sh (the fixtures are in a temporary directory)"

work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

servers() {
  awk '/^Server/ { sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); print }' "$1" | tr '\n' ' '
}

reset() {
  mkdir -p "$work/d"
  printf '## a comment\n\nServer = https://first.invalid/$repo\nServer = https://second.invalid/$repo  \n## Ranked\nServer = https://third.invalid/$repo\n' \
    > "$work/d/mirrorlist"
  printf 'Server = https://first.invalid/$repo\nServer = https://any.invalid/base/any\n' > "$work/d/mirrorlist-any"
}

#---------------------------------------------------------------------------#
# One server
#---------------------------------------------------------------------------#
reset
rc=0
bash "$DROP" "$work/d/mirrorlist" 'https://first.invalid/$repo' 2> "$work/err" || rc=$?
got="$(servers "$work/d/mirrorlist")"
if [ "$rc" -eq 0 ] && [ "$got" = 'https://second.invalid/$repo https://third.invalid/$repo ' ] &&
  grep -q '^## Ranked' "$work/d/mirrorlist"; then
  ok "drop-server removes the one line and keeps the rest, comments too"
else
  fail "drop-server removes the one line and keeps the rest, comments too" \
    "exit $rc, servers left: $got" "it said: $(cat "$work/err")" "reproduce: $REPRO"
fi

reset
rc=0
bash "$DROP" "$work/d/mirrorlist" 'https://second.invalid/$repo' 2> "$work/err" || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q 'second.invalid' "$work/d/mirrorlist"; then
  ok "drop-server finds a line with spaces at the end"
else
  fail "drop-server finds a line with spaces at the end" "exit $rc" "it said: $(cat "$work/err")" "reproduce: $REPRO"
fi

# refused DESC ARG... -> exit 1, and both lists are as they were
refused() {
  local desc="$1" rc=0
  shift
  reset
  cat "$work/d/mirrorlist" "$work/d/mirrorlist-any" > "$work/before"
  bash "$DROP" "$@" 2> "$work/err" || rc=$?
  if [ "$rc" -eq 1 ] && [ "$(cat "$work/d/mirrorlist" "$work/d/mirrorlist-any")" = "$(cat "$work/before")" ]; then
    ok "$desc"
  else
    fail "$desc" "exit $rc (want 1), or a list changed" "it said: $(cat "$work/err")" "reproduce: $REPRO"
  fi
}

refused "a server that is no Server line is refused" "$work/d/mirrorlist" 'https://absent.invalid/$repo'
refused "a part of a Server value is refused" "$work/d/mirrorlist" 'https://first.invalid'
printf 'Server = https://only.invalid/$repo\n' > "$work/only"
rc=0
bash "$DROP" "$work/only" 'https://only.invalid/$repo' 2> "$work/err" || rc=$?
if [ "$rc" -eq 1 ] && grep -q 'only.invalid' "$work/only"; then
  ok "drop-server refuses to leave a list with no server"
else
  fail "drop-server refuses to leave a list with no server" "exit $rc" "it said: $(cat "$work/err")" "reproduce: $REPRO"
fi

#---------------------------------------------------------------------------#
# Pairs
#---------------------------------------------------------------------------#
reset
rc=0
bash "$DROP" --pairs "$work/d" 'mirrorlist=https://first.invalid/$repo mirrorlist-any=https://first.invalid/$repo' \
  2> "$work/err" || rc=$?
a="$(servers "$work/d/mirrorlist")"
b="$(servers "$work/d/mirrorlist-any")"
if [ "$rc" -eq 0 ] && [ "$a" = 'https://second.invalid/$repo https://third.invalid/$repo ' ] &&
  [ "$b" = 'https://any.invalid/base/any ' ]; then
  ok "--pairs drops one server from each list it names"
else
  fail "--pairs drops one server from each list it names" \
    "exit $rc; mirrorlist: $a; mirrorlist-any: $b" "it said: $(cat "$work/err")" "reproduce: $REPRO"
fi

reset
rc=0
bash "$DROP" --pairs "$work/d" 'mirrorlist-any=https://first.invalid/$repo' 2> "$work/err" || rc=$?
a="$(servers "$work/d/mirrorlist")"
if [ "$rc" -eq 0 ] && [ "$a" = 'https://first.invalid/$repo https://second.invalid/$repo https://third.invalid/$repo ' ]; then
  ok "--pairs leaves a list that no pair names as it was"
else
  fail "--pairs leaves a list that no pair names as it was" "exit $rc; mirrorlist: $a" "reproduce: $REPRO"
fi

reset
cat "$work/d/mirrorlist" "$work/d/mirrorlist-any" > "$work/before"
rc=0
bash "$DROP" --pairs "$work/d" '' 2> "$work/err" || rc=$?
if [ "$rc" -eq 0 ] && [ "$(cat "$work/d/mirrorlist" "$work/d/mirrorlist-any")" = "$(cat "$work/before")" ]; then
  ok "--pairs with no pair changes nothing"
else
  fail "--pairs with no pair changes nothing" "exit $rc" "it said: $(cat "$work/err")" "reproduce: $REPRO"
fi

refused "--pairs refuses a pair that is not LIST=SERVER" --pairs "$work/d" 'mirrorlist'
refused "--pairs refuses a LIST that is a path" --pairs "$work/d" '../d/mirrorlist=https://first.invalid/$repo'
refused "--pairs refuses a LIST that is not in DIR" --pairs "$work/d" 'nolist=https://first.invalid/$repo'

summary
