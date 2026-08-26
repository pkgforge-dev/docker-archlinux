#!/usr/bin/env bash
#
# Signature checking must stay on in every shipped pacman.conf.
#
# A downstream consumer of this image sets SigLevel = Never in its own layer.
# This test exists so that setting can never arrive here by a copy-paste.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

confs="$(find "$REPO_ROOT/rootfs" -type f -name pacman.conf | sort)"

if [ -z "$confs" ]; then
  fail "at least one shipped pacman.conf exists" "searched: $REPO_ROOT/rootfs"
  summary
  exit 1
fi

while IFS= read -r conf; do
  [ -n "$conf" ] || continue
  rel="${conf#"$REPO_ROOT/"}"

  never="$(grep_matches '^[[:space:]]*(Local|Remote)?FileSigLevel|^[[:space:]]*SigLevel' "$conf")"
  if printf '%s\n' "$never" | grep -qiE '=[^#]*\bNever\b'; then
    fail "$rel does not disable signature checking" \
      "found: $(printf '%s\n' "$never" | grep -iE '=[^#]*\bNever\b' | tr '\n' ' ')" \
      "reproduce: grep -nE '^[[:space:]]*SigLevel' $rel"
  else
    ok "$rel does not set any SigLevel to Never"
  fi

  siglevel="$(grep_matches '^[[:space:]]*SigLevel[[:space:]]*=' "$conf")"
  if [ -z "$siglevel" ]; then
    fail "$rel sets SigLevel explicitly" \
      "no uncommented SigLevel line" \
      "reproduce: grep -nE '^[[:space:]]*SigLevel' $rel"
  elif printf '%s\n' "$siglevel" | grep -qE 'SigLevel[[:space:]]*=[[:space:]]*Required\b'; then
    ok "$rel sets SigLevel = Required"
  else
    fail "$rel sets SigLevel = Required" \
      "found: $siglevel" \
      "the first token after = must be Required"
  fi
done <<< "$confs"

summary
