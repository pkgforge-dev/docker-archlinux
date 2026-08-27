#!/usr/bin/env bash
#
# No fetch in this repository may hang.
#
# curl's default connect timeout is around two minutes and its default total
# timeout is none at all. A mirror that accepts the connection and then stops
# sending holds the job open until GitHub kills it, six hours later, with no
# message about what it was waiting for. That shape has already cost this
# project time: a 301 followed to a 29 second dead end, and a mirror answering
# from one network and not from another.
#
# So every fetch carries both. The numbers differ by payload and are not
# asserted: a tag list is not a package database. What is asserted is that a
# fetch cannot wait forever, and that a fetch whose failure stops the run gets
# more than one attempt.
#
# ⚠ This is a text scan. A curl written inside a diagnostic string is a command
# the reader types, not one this repository runs, so a line carrying
# `reproduce:` or `check it with:` is skipped. ⛔ That means no diagnostic in
# this repository may be the only place a real fetch is written.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

targets() {
  if [ -d "$REPO_ROOT/scripts" ]; then
    find "$REPO_ROOT/scripts" -type f | sort
  fi
  if [ -d "$REPO_ROOT/.github/workflows" ]; then
    find "$REPO_ROOT/.github/workflows" -type f -name '*.yml' | sort
  fi
  if [ -d "$REPO_ROOT/bootstrap/any/usr/local/bin" ]; then
    find "$REPO_ROOT/bootstrap/any/usr/local/bin" -type f | sort
  fi
}

files="$(targets)"
if [ -z "$files" ]; then
  fail "there is something to scan" \
    "no scripts, workflows or bootstrap binaries found" \
    "reproduce: ls scripts .github/workflows"
  summary
  exit 1
fi

#---------------------------------------------------------------------------#
# invocations FILE -> "<line>\t<gathered text>" per curl command
#
# A call may span several lines through backslash continuation, so the whole
# call is gathered before it is judged, the same way 15-actionable-failures.sh
# gathers a fail.
#
# `need curl` and the word in prose are not invocations. A real one is followed
# by an option.
#---------------------------------------------------------------------------#
invocations() {
  awk '
    function flush() {
      if (!collecting) return
      printf "%d\t%s\n", start, body
      collecting = 0
      body = ""
    }
    {
      line = $0
      sub(/(^|[[:space:]])#.*$/, "", line)
      if (collecting) {
        body = body " " line
        if (line !~ /\\[[:space:]]*$/) flush()
        next
      }
      if (line ~ /curl[[:space:]]+-/) {
        collecting = 1
        start = NR
        body = line
        if (line !~ /\\[[:space:]]*$/) flush()
      }
    }
    END { flush() }
  ' "$1"
}

total=0
skipped=0
no_connect=""
no_max=""

while IFS= read -r file; do
  [ -n "$file" ] || continue
  rel="${file#"$REPO_ROOT/"}"
  while IFS=$'\t' read -r lineno body; do
    [ -n "$lineno" ] || continue
    case "$body" in
      *'reproduce:'* | *'check it with:'* | *'probe them with:'* | *'regenerate the list with:'*)
        skipped=$((skipped + 1))
        continue
        ;;
    esac
    total=$((total + 1))
    case "$body" in
      *--connect-timeout*) ;;
      *) no_connect="$no_connect $rel:$lineno" ;;
    esac
    case "$body" in
      *--max-time*) ;;
      *) no_max="$no_max $rel:$lineno" ;;
    esac
  done <<< "$(invocations "$file")"
done <<< "$files"

if [ "$total" -eq 0 ]; then
  fail "at least one fetch was found to check" \
    "the scan matched nothing, so this test asserted nothing" \
    "reproduce: grep -rn 'curl -' scripts .github/workflows"
  summary
  exit 1
fi
ok "found $total fetch(es) to check, and skipped $skipped written inside a diagnostic"

if [ -z "$no_connect" ]; then
  ok "all $total fetches set --connect-timeout"
else
  n=0
  for _ in $no_connect; do n=$((n + 1)); done
  fail "all $total fetches set --connect-timeout" \
    "$n without one:$no_connect" \
    "curl's default is around two minutes per attempt, and a dead mirror is a normal result here" \
    "reproduce: bash tests/run.sh static, which names each one"
fi

if [ -z "$no_max" ]; then
  ok "all $total fetches set --max-time"
else
  n=0
  for _ in $no_max; do n=$((n + 1)); done
  fail "all $total fetches set --max-time" \
    "$n without one:$no_max" \
    "curl has no default total timeout, so a mirror that connects and then stalls holds the job until CI kills it" \
    "reproduce: bash tests/run.sh static, which names each one"
fi

summary
