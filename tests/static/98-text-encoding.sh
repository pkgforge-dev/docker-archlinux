#!/usr/bin/env bash
#
# Check that no text file holds a character encoded twice.
#
# UTF-8 text read as Latin-1 and written back as UTF-8 turns one character
# into three or more. A marker such as ⛔ then starts with the bytes c3 a2 c2,
# and no correct text has c2 after c3 a2. grep -I passes over binary files.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

cd "$REPO_ROOT"
rc=0
hits="$(LC_ALL=C grep -rlIP '\xc3\xa2\xc2[\x80-\xbf]' --exclude-dir=.git .)" || rc=$?
case "$rc" in
  1) ok "no text file holds a character encoded twice" ;;
  0)
    fail "no text file holds a character encoded twice" \
      "files: $(printf '%s\n' "$hits" | tr '\n' ' ')" \
      "decode each run of c3 a2 c2 xx c2 xx back to one UTF-8 character" \
      "reproduce: LC_ALL=C grep -rnIP '\\xc3\\xa2\\xc2[\\x80-\\xbf]' --exclude-dir=.git ."
    ;;
  *)
    fail "grep -P reads the tree" "grep exited $rc" \
      "reproduce: LC_ALL=C grep -rlIP x --exclude-dir=.git ."
    ;;
esac

summary
