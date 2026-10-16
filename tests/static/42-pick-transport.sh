#!/usr/bin/env bash
#
# scripts/pick-transport prints worker when the Worker answers, oci when only
# the registry answers, and worker when neither answers.
#
# A fixture port (PORTS_DIR) has the repositories core and extra. The Worker
# is a file:// directory (GHCR_WORKER_SERVER). The registry is a fake
# pacman-oci (PACMAN_OCI) that serves oci://fake/... from a directory and
# writes each URL it gets to a log.
#
# $arch and $repo are variables of pacman and stay literal in this file.
# shellcheck disable=SC2016
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

PICK="$REPO_ROOT/scripts/pick-transport"
REPRO="bash tests/static/42-pick-transport.sh (the fixtures are in a temporary directory)"

if ! need_tool tar gzip curl; then
  rc=0
  summary || rc=$?
  exit "$rc"
fi

work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

file_url() {
  case "$(uname -o 2>&1)" in
    Msys | Cygwin) printf 'file:///%s\n' "$(cygpath -m "$1")" ;;
    *) printf 'file://%s\n' "$1" ;;
  esac
}

mkdir -p "$work/ports" "$work/members/pacman-1-1" "$work/worker" "$work/oci"
printf 'arch = fake\npacman_arch = x86_64\nrepos = core extra\n' > "$work/ports/fake.conf"
tar -czf "$work/core.db" -C "$work/members" pacman-1-1

cat > "$work/fake-oci" <<'EOF'
#!/bin/sh
# A fake pacman-oci: OUTPUT URL. It serves oci://fake/PATH from $FAKE_OCI_ROOT/PATH.
printf '%s\n' "$2" >> "$FAKE_OCI_LOG"
case "$2" in
  oci://fake/*) p="${2#oci://fake/}" ;;
  *) exit 1 ;;
esac
[ -f "$FAKE_OCI_ROOT/$p" ] || exit 1
cp "$FAKE_OCI_ROOT/$p" "$1"
EOF

# pick -> runs the script; the word goes to pick.out, stderr to pick.err
pick() {
  local rc=0
  : > "$work/oci.log"
  env PORTS_DIR="$work/ports" \
    GHCR_WORKER_SERVER="$(file_url "$work/worker")/\$arch/\$repo" \
    GHCR_OCI_SERVER='oci://fake/$arch/$repo' \
    PACMAN_OCI="$work/fake-oci" FAKE_OCI_ROOT="$work/oci" FAKE_OCI_LOG="$work/oci.log" \
    bash "$PICK" fake > "$work/pick.out" 2> "$work/pick.err" || rc=$?
  printf '%s\n' "$rc" > "$work/pick.rc"
}

# expect DESC WORD
expect() {
  local got rc
  got="$(tr -d '\r' < "$work/pick.out")"
  rc="$(cat "$work/pick.rc")"
  if [ "$rc" -eq 0 ] && [ "$got" = "$2" ]; then
    ok "$1"
  else
    fail "$1" "want '$2', exit 0; got '$got', exit $rc" \
      "it said: $(tr '\n' '|' < "$work/pick.err")" "reproduce: $REPRO"
  fi
}

# The Worker answers
mkdir -p "$work/worker/x86_64/core"
cp "$work/core.db" "$work/worker/x86_64/core/core.db"
pick
expect "worker when the Worker serves the database of the first repository" worker
if [ ! -s "$work/oci.log" ]; then
  ok "the registry is not asked when the Worker answers"
else
  fail "the registry is not asked when the Worker answers" "it asked: $(tr '\n' ' ' < "$work/oci.log")" "reproduce: $REPRO"
fi

# Only the registry answers
rm -rf "$work/worker/x86_64"
mkdir -p "$work/oci/x86_64/core"
cp "$work/core.db" "$work/oci/x86_64/core/core.db"
pick
expect "oci when only the registry serves the database" oci
asked="$(tr -d '\r' < "$work/oci.log")"
if [ "$asked" = "oci://fake/x86_64/core/core.db" ]; then
  ok "the registry is asked for the database of the first repository, with pacman_arch"
else
  fail "the registry is asked for the database of the first repository, with pacman_arch" \
    "it asked: ${asked:-nothing}" "want: oci://fake/x86_64/core/core.db" "reproduce: $REPRO"
fi

# The registry serves a file that is not a database
printf '<html>403</html>\n' > "$work/oci/x86_64/core/core.db"
pick
expect "worker when the registry serves a file that is not a database" worker

# Neither answers
rm -rf "$work/oci/x86_64"
pick
expect "worker when neither path answers" worker

# An unknown architecture
rc=0
PORTS_DIR="$work/ports" bash "$PICK" nosuch > "$work/pick.out" 2> "$work/pick.err" || rc=$?
if [ "$rc" -eq 1 ] && [ ! -s "$work/pick.out" ]; then
  ok "an architecture with no ports/<arch>.conf is refused"
else
  fail "an architecture with no ports/<arch>.conf is refused" "exit $rc, stdout: $(cat "$work/pick.out")" "reproduce: $REPRO"
fi

summary
