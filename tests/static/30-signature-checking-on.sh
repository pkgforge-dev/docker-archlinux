#!/usr/bin/env bash
#
# Signature checks stay on in each pacman.conf that ships.
#
# For each rootfs/*/etc/pacman.conf:
#   - no SigLevel, LocalFileSigLevel or RemoteFileSigLevel is Never
#   - an uncommented SigLevel line exists, and its first value is Required
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

confs="$(find "$REPO_ROOT/rootfs" -type f -name pacman.conf | sort)"

if [ -z "$confs" ]; then
  fail "at least one pacman.conf ships" "searched: $REPO_ROOT/rootfs" \
    "reproduce: ls rootfs/*/etc/pacman.conf"
  summary
  exit 1
fi

while IFS= read -r conf; do
  [ -n "$conf" ] || continue
  rel="${conf#"$REPO_ROOT/"}"

  lines="$(grep_matches '^[[:space:]]*(Local|Remote)?FileSigLevel|^[[:space:]]*SigLevel' "$conf")"
  never="$(awk 'tolower($0) ~ /=[^#]*(^|[^a-z])never([^a-z]|$)/' <<< "$lines")"
  if [ -z "$never" ]; then
    ok "$rel sets no SigLevel to Never"
  else
    fail "$rel sets no SigLevel to Never" \
      "found: $(tr '\n' ' ' <<< "$never")" \
      "reproduce: grep -nE '^[[:space:]]*SigLevel' $rel"
  fi

  siglevel="$(grep_matches '^[[:space:]]*SigLevel[[:space:]]*=' "$conf")"
  if [ -z "$siglevel" ]; then
    fail "$rel sets SigLevel" \
      "no uncommented SigLevel line" \
      "reproduce: grep -nE '^[[:space:]]*SigLevel' $rel"
  elif [ -n "$(awk '/SigLevel[[:space:]]*=[[:space:]]*Required([[:space:]]|$)/' <<< "$siglevel")" ]; then
    ok "$rel sets SigLevel = Required"
  else
    fail "$rel sets SigLevel = Required" \
      "found: $siglevel" \
      "the first value after = must be Required" \
      "reproduce: grep -n SigLevel $rel"
  fi
done <<< "$confs"

summary
