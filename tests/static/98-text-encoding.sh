#!/usr/bin/env bash
#
# No text file in the tree carries a character that was encoded twice.
#
# A UTF-8 file that is read as Latin-1 and written back as UTF-8 turns each
# marker into three characters: ⛔ becomes a small a with a circumflex and two
# C1 control characters. Three files under mirrors/ carried eight of them, and
# nothing failed, because every reader of those files skips comments.
#
# The bytes of a marker encoded twice start c3 a2 c2, and no correct text here
# has c2 after c3 a2. grep -I passes over binary files, so the vendored keyring
# packages are not read.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

rc=0
hits="$(LC_ALL=C grep -rlIP '\xc3\xa2\xc2[\x80-\xbf]' --exclude-dir=.git --exclude-dir=.tmp "$REPO_ROOT")" || rc=$?
case "$rc" in
  1)
    ok "no text file in the tree carries a character encoded twice"
    ;;
  0)
    fail "no text file in the tree carries a character encoded twice" \
      "files: $(printf '%s\n' "$hits" | sed "s|^$REPO_ROOT/||" | tr '\n' ' ')" \
      "decode each run of c3 a2 c2 xx c2 xx back to one UTF-8 character" \
      "reproduce: LC_ALL=C grep -rnIP '\\xc3\\xa2\\xc2[\\x80-\\xbf]' --exclude-dir=.git ."
    ;;
  *)
    fail "grep -P can scan the tree" \
      "grep exited $rc" \
      "reproduce: LC_ALL=C grep -rlIP x --exclude-dir=.git ."
    ;;
esac

summary
