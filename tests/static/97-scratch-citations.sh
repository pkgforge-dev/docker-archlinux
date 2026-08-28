#!/usr/bin/env bash
#
# Nothing in the repository may depend on `.tmp/`, and a document that cites a
# path there has to say the path is not there.
#
# ⛔ `.tmp/` is gitignored and wiped between sessions. A reader who follows a
# citation into it finds nothing, with no statement that nothing is what they
# should expect. Nine documents under `HISTORY/` cited scratch fixtures that way
# until 2026-08-29.
#
# ⚠ These are provenance breadcrumbs, not live dependencies. ⛔ Deleting a
# measurement to remove a reference to it is not the fix. Saying so at the
# citation is.
#
# Two separate assertions, and the second is the one that matters:
#
#   1. nothing outside HISTORY/ names a `.tmp/` path at all
#   2. every HISTORY/ document that names one carries the standing note
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

NOTE='Scratch paths in this document'

#---------------------------------------------------------------------------#
# 1. The manual, the scripts, the tests and the workflows never name `.tmp/`.
#
# ⛔ A build, a test or a documented command that reads a scratch path is a real
# dependency on something that is not there, which is a different and worse
# problem than a stale breadcrumb.
#---------------------------------------------------------------------------#
live=""
for d in scripts tests bootstrap examples docs .github Dockerfile README.md; do
  [ -e "$REPO_ROOT/$d" ] || continue
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    # This file explains the rule, so it names the path in its own prose.
    case "$hit" in
      *97-scratch-citations.sh*) continue ;;
    esac
    live="$live $hit"
  done <<< "$(grep -rn --binary-files=without-match '[.]tmp/' "$REPO_ROOT/$d" 2>/dev/null \
    | sed "s#^$REPO_ROOT/##" | awk -F: '{ print $1 ":" $2 }')"
done

if [ -z "$live" ]; then
  ok "nothing outside HISTORY/ names a .tmp/ path"
else
  fail "nothing outside HISTORY/ names a .tmp/ path" \
    "found:$live" \
    "⛔ .tmp/ is gitignored and wiped between sessions, so this is a dependency on nothing" \
    "reproduce: grep -rn '[.]tmp/' scripts tests bootstrap examples docs .github Dockerfile README.md"
fi

#---------------------------------------------------------------------------#
# 2. Every HISTORY/ document naming a scratch path says it is not kept.
#---------------------------------------------------------------------------#
[ -d "$REPO_ROOT/HISTORY" ] || {
  fail "HISTORY/ exists" "reproduce: ls HISTORY"
  summary
  exit 1
}

citing=0
unmarked=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  grep -q '[.]tmp/' "$f" || continue
  citing=$((citing + 1))
  grep -q "$NOTE" "$f" || unmarked="$unmarked ${f#"$REPO_ROOT/"}"
done <<< "$(find "$REPO_ROOT/HISTORY" -type f -name '*.md' | LC_ALL=C sort)"

# ⚠ Zero citing documents is a pass, not a failure: a tree with no breadcrumbs
# left is the end state this is aimed at. What is asserted is that HISTORY/ was
# actually read, so an empty scan cannot be mistaken for a clean one.
total_docs="$(find "$REPO_ROOT/HISTORY" -type f -name '*.md' | awk 'END { print NR + 0 }')"
if [ "$total_docs" -eq 0 ]; then
  fail "HISTORY/ holds documents to check" \
    "the scan found no .md files, so this asserted nothing" \
    "reproduce: find HISTORY -name '*.md'"
elif [ -z "$unmarked" ]; then
  ok "$citing of $total_docs HISTORY documents cite a scratch path, and all say it is not kept"
else
  fail "every HISTORY document citing a scratch path says it is not kept" \
    "without the note:$unmarked" \
    "a reader who follows one finds nothing, and nothing tells them to expect that" \
    "add the standing note beginning: $NOTE" \
    "reproduce: grep -rln '[.]tmp/' HISTORY/ | xargs grep -L '$NOTE'"
fi

summary
