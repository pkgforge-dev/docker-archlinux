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

#---------------------------------------------------------------------------#
# A keyserver fetch is a fetch.
#
# ⛔ The scan above reads curl and nothing else, so gpg --recv-keys, which opens
# a network connection over hkps, sat outside the policy entirely. It was added
# to the tree on 2026-08-29 and the scan said nothing, which is the shape of
# gap this file exists to close: a policy that covers the tool it was written
# against rather than the thing it was written about.
#
# gpg's own option is --keyserver-options timeout=N. There is no separate
# connect timeout, so one value covers both.
#---------------------------------------------------------------------------#
ks_total=0
ks_untimed=""

# ⚠ A trailing backslash is tested with sprintf("%c", 92) rather than written
# into a regex. A backslash in a pattern written through an editing tool can
# arrive halved, and the pattern then matches nothing while the scan still
# reports a pass. That is what happened to the first version of this block: it
# found zero keyserver fetches in a tree holding one, and said so as an ok line.
ks_invocations() {
  awk '
    function bs() { return sprintf("%c", 92) }
    function flush() {
      if (!collecting) return
      print start ":" body
      collecting = 0
      body = ""
    }
    function continued(s) {
      sub(/[[:space:]]+$/, "", s)
      return substr(s, length(s), 1) == bs()
    }
    {
      line = $0
      sub(/(^|[[:space:]])#.*$/, "", line)
      if (collecting) {
        body = body " " line
        if (!continued(line)) flush()
        next
      }
      # ⚠ Any gpg invocation starts a gather, and whether it is a keyserver
      # fetch is decided on the whole gathered call. A call written across a
      # continuation puts gpg on one line and --recv-keys on the next, and a
      # scan that judges the first line alone walks straight past it. That is
      # the miss this comment exists for: --keyserver-options is not
      # --keyserver, so matching the first line found nothing at all.
      if (line ~ /(^|[[:space:]])gpg[[:space:]]+-/) {
        collecting = 1
        start = NR
        body = line
        if (!continued(line)) flush()
      }
    }
    END { flush() }
  ' "$1"
}

while IFS= read -r file; do
  [ -n "$file" ] || continue
  rel="${file#"$REPO_ROOT/"}"
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    lineno="${hit%%:*}"
    body="${hit#*:}"
    case "$body" in
      *'reproduce:'* | *'check it with:'*) continue ;;
    esac
    # Only the gpg calls that reach a keyserver. --list-keys and --verify are
    # local and cannot hang on a network.
    case "$body" in
      *--recv-keys* | *--refresh-keys* | *--search-keys* | *--send-keys*) ;;
      *) continue ;;
    esac
    ks_total=$((ks_total + 1))
    case "$body" in
      *'--keyserver-options'*timeout=*) ;;
      *) ks_untimed="$ks_untimed $rel:$lineno" ;;
    esac
  done <<< "$(ks_invocations "$file")"
done <<< "$files"

# ⛔ Zero is a failure, not a pass. This repository fetches keys, so a scan that
# finds none has stopped working rather than found nothing to do.
if [ "$ks_total" -eq 0 ]; then
  fail "at least one keyserver fetch was found to check" \
    "the scan matched nothing, so this assertion checked nothing" \
    "scripts/build-pacman-static imports the pinned signers before it verifies the tag" \
    "reproduce: grep -rn 'recv-keys' scripts/"
elif [ -z "$ks_untimed" ]; then
  ok "all $ks_total keyserver fetches set a timeout"
else
  fail "all $ks_total keyserver fetches set a timeout" \
    "without one:$ks_untimed" \
    "gpg has no default total timeout, so a keyserver that stalls holds the job" \
    "add --keyserver-options timeout=N" \
    "reproduce: grep -rn 'recv-keys' scripts/"
fi

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
