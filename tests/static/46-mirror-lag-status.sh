#!/usr/bin/env bash
#
# When no later server answers, scripts/check-mirror-lag judges the GHCR
# mirror by its record: MIRROR_STATUS_URL, the target <pacman_arch>-<repo>,
# the field lag_seconds.
#
# The fixture port has [base] (mirrorlist) and [base-any] (mirrorlist-any).
# The server named ghcr is the GHCR mirror (GHCR_MATCH). The record is a
# file:// fixture. Cases:
#   - lag_seconds above MIRROR_LAG_MAX drops the GHCR mirror of that list only
#   - a record that cannot be read, that is too old, of another schema, with
#     no target, or with no number: the server stays, and a warning gives the
#     reason
#   - a later server that answers is the reference, and the record is not used
#   - a first server that is not the GHCR mirror is never judged by the record
#   - with TRANSPORT=oci, the Worker path to the GHCR mirror is not a reference
#     for the oci:// path, and a drop names both paths
#   - after that drop, resolve-anchor and the build stage (use-transport, then
#     drop-server) read the first server that is not the GHCR mirror
#   - with TRANSPORT=oci, a list with no server other than the GHCR mirror
#     stays
#
# $arch and $repo are variables of pacman and stay literal in this file.
# shellcheck disable=SC2016
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

LAG="$REPO_ROOT/scripts/check-mirror-lag"
REPRO="bash tests/static/46-mirror-lag-status.sh (the fixtures are in a temporary directory)"
T0=1767225600
DAY=86400
NOW="$(date -u +%s)"

if ! need_tool tar gzip curl jq; then
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

server() {
  printf '%s/%s/$repo\n' "$(file_url "$work/srv")" "$1"
}

# mkdb NAME REPO EPOCH PACKAGE -> a database on the fixture server NAME
mkdb() {
  local m="$work/members/$1-$2"
  mkdir -p "$work/srv/$1/$2" "$m/$4"
  printf '%%NAME%%\n%s\n' "$4" > "$m/$4/desc"
  tar --mtime="@$3" -czf "$work/srv/$1/$2/$2.db" -C "$m" "$4"
}

# status FILE BASE_LAG ANY_LAG [GENERATED [SCHEMA]] -> a record; a lag of
# "absent" leaves the target out
status() {
  local f="$1" base="$2" any="$3" gen="${4:-$NOW}" schema="${5:-1}"
  jq -n --argjson g "$gen" --argjson s "$schema" --arg b "$base" --arg a "$any" '
    { schema: $s, generated_epoch: $g,
      targets: (
        [ if $b == "absent" then empty else { target: "powerpc64le-base", lag_seconds: ($b | tonumber? // null) } end,
          if $a == "absent" then empty else { target: "powerpc64le-base-any", lag_seconds: ($a | tonumber? // null) } end ]) }' > "$f"
}

# The fixture port
mkdir -p "$work/ports" "$work/rootfs/fake/etc/pacman.d"
printf 'arch = fake\npacman_arch = powerpc64le\nrepos = base base-any\n' > "$work/ports/fake.conf"
printf '[options]\nArchitecture = powerpc64le\n\n[base]\nInclude = /etc/pacman.d/mirrorlist\n\n[base-any]\nInclude = /etc/pacman.d/mirrorlist-any\n' \
  > "$work/rootfs/fake/etc/pacman.conf"
mkdb ghcr base "$T0" pacman-1-1
mkdb ghcr base-any "$T0" iana-etc-1-1
mkdb plain base "$T0" pacman-1-1
mkdb plain base-any "$T0" iana-etc-1-1

# lists FIRST SECOND... -> both lists with these fixture servers
lists() {
  local s
  for s in "$@"; do
    printf 'Server = %s\n' "$(server "$s")"
  done > "$work/rootfs/fake/etc/pacman.d/mirrorlist"
  cp "$work/rootfs/fake/etc/pacman.d/mirrorlist" "$work/rootfs/fake/etc/pacman.d/mirrorlist-any"
}

# lag DESC WANT [ENV=VALUE ...] -> one run, one assertion on the verdict
lag() {
  local desc="$1" want="$2" rc=0 got
  shift 2
  env PORTS_DIR="$work/ports" ROOTFS_DIR="$work/rootfs" \
    GHCR_MATCH='^(oci://fake/|file://.*/ghcr/)' \
    MIRROR_STATUS_URL="$(file_url "$work/status.json")" "$@" \
    bash "$LAG" fake > "$work/out" 2> "$work/err" || rc=$?
  got="$(tr -d '\r' < "$work/out")"
  if [ "$rc" -eq 0 ] && [ "$got" = "$want" ]; then
    ok "$desc"
  else
    fail "$desc" \
      "want: '$(tr '\n' '|' <<< "$want")', exit 0" \
      "got:  '$(tr '\n' '|' <<< "$got")', exit $rc" \
      "it said: $(tr -d '\r' < "$work/err" | tr '\n' '|')" \
      "reproduce: $REPRO"
  fi
}

# said DESC TEXT -> the last run named TEXT on stderr
said() {
  if grep -qF -e "$2" "$work/err"; then
    ok "$1"
  else
    fail "$1" "no line has '$2'" "it said: $(tr -d '\r' < "$work/err" | tr '\n' '|')" "reproduce: $REPRO"
  fi
}

KEEP_BOTH="keep mirrorlist
keep mirrorlist-any"

# The GHCR mirror first, then a server that does not answer
lists ghcr dead
status "$work/status.json" 0 99999
lag "lag_seconds above MIRROR_LAG_MAX drops the GHCR mirror from that list only" \
  "keep mirrorlist
drop mirrorlist-any $(server ghcr)"

status "$work/status.json" 0 99999
lag "MIRROR_LAG_MAX sets the limit for the record too" "$KEEP_BOTH" MIRROR_LAG_MAX=100000

rm -f "$work/status.json"
lag "a record that cannot be read keeps the GHCR mirror" "$KEEP_BOTH"
said "the warning gives the URL of the record that cannot be read" "$(file_url "$work/status.json")"

status "$work/status.json" 99999 99999 "$((NOW - 2 * DAY))"
lag "a record older than MIRROR_STATUS_MAX_AGE is not used" "$KEEP_BOTH"
said "the warning names MIRROR_STATUS_MAX_AGE, the limit it passed" "MIRROR_STATUS_MAX_AGE"

status "$work/status.json" 99999 99999 "$NOW" 2
lag "a record of another schema is not used" "$KEEP_BOTH"

status "$work/status.json" 0 absent
lag "a record with no target for the repository keeps the GHCR mirror" "$KEEP_BOTH"
said "the warning names the target that is not there" "powerpc64le-base-any"

status "$work/status.json" 0 none
lag "a lag_seconds that is not a number keeps the GHCR mirror" "$KEEP_BOTH"

# A later server answers: it is the reference, and the record is not used
lists ghcr plain
status "$work/status.json" 99999 99999
lag "a later server that answers is the reference, and the record is not used" "$KEEP_BOTH"

# A first server that is not the GHCR mirror is not judged by the record
lists plain dead
status "$work/status.json" 99999 99999
lag "the record does not judge a first server that is not the GHCR mirror" "$KEEP_BOTH"

# TRANSPORT=oci: the oci:// path is first. The Worker path serves the same
# files, so the next other server is the reference. The fake client serves
# the copy of the ghcr fixture for oci://fake/ and for the oci:// path that
# use-transport writes.
OCI_REAL='oci://ghcr.io/pkgforge-dev/mirror-archlinux/$arch/$repo'
cat > "$work/fake-oci" <<'EOF'
#!/bin/sh
case "$2" in
  oci://fake/*) p="${2#oci://fake/}" ;;
  oci://ghcr.io/pkgforge-dev/mirror-archlinux/*) p="${2#oci://ghcr.io/pkgforge-dev/mirror-archlinux/}" ;;
  *) exit 1 ;;
esac
[ -f "$FAKE_OCI_ROOT/$p" ] || exit 1
cp "$FAKE_OCI_ROOT/$p" "$1"
EOF
mkdir -p "$work/oci/powerpc64le"
cp -r "$work/srv/ghcr/base" "$work/srv/ghcr/base-any" "$work/oci/powerpc64le/"
mkdb newer base "$((T0 + 2 * DAY))" pacman-2-1
mkdb newer base-any "$T0" iana-etc-1-1
lists ghcr newer
status "$work/status.json" 0 0
OCI_ENV=(TRANSPORT=oci "PACMAN_OCI=$work/fake-oci" "FAKE_OCI_ROOT=$work/oci")
lag "with TRANSPORT=oci the Worker is not the reference, and the drop names the oci:// path and the Worker path" \
  "drop mirrorlist oci://fake/\$arch/\$repo
drop mirrorlist $(server ghcr)
keep mirrorlist-any" \
  "${OCI_ENV[@]}" 'GHCR_OCI_SERVER=oci://fake/$arch/$repo'

# skip_of_out -> SKIP_SERVERS from the last verdict: a LIST=SERVER pair for
# each drop line
skip_of_out() {
  awk '$1 == "drop" { printf "%s%s=%s", sep, $2, $3; sep = " " }' "$work/out"
}

# resolve-anchor reads the lists as the build stage does, so the version
# comes from the first server that is not the GHCR mirror.
skip="$(skip_of_out)"
rc=0
env PORTS_DIR="$work/ports" ROOTFS_DIR="$work/rootfs" "${OCI_ENV[@]}" \
  'GHCR_OCI_SERVER=oci://fake/$arch/$repo' SKIP_SERVERS="$skip" \
  bash "$REPO_ROOT/scripts/resolve-anchor" fake > "$work/anchor.out" 2> "$work/anchor.err" || rc=$?
got="$(tr -d '\r' < "$work/anchor.out")"
if [ "$rc" -eq 0 ] && [ "$got" = "2-1" ]; then
  ok "after the drop, resolve-anchor gives the version of the server after the GHCR mirror"
else
  fail "after the drop, resolve-anchor gives the version of the server after the GHCR mirror" \
    "want: '2-1', exit 0 (the GHCR fixture has 1-1)" "got: '$got', exit $rc" \
    "SKIP_SERVERS: $skip" \
    "it said: $(tr -d '\r' < "$work/anchor.err" | tr '\n' '|')" \
    "reproduce: $REPRO"
fi

# The build stage: use-transport writes the oci:// path, then drop-server
# applies the pairs. The first server left is the one after the GHCR mirror.
lag "with the oci:// path of use-transport, the drop names it and the Worker path" \
  "drop mirrorlist $OCI_REAL
drop mirrorlist $(server ghcr)
keep mirrorlist-any" \
  "${OCI_ENV[@]}" 'GHCR_MATCH=^(oci://ghcr\.io/pkgforge-dev/mirror-archlinux/|file://.*/ghcr/)'
skip="$(skip_of_out)"
stage="$work/stage"
mkdir -p "$stage/usr/local/bin"
cp -r "$work/rootfs/fake/etc" "$stage/"
cp "$REPO_ROOT/bootstrap/any/usr/local/bin/pacman-oci" "$stage/usr/local/bin/"
rc=0
{
  bash "$REPO_ROOT/bootstrap/any/usr/local/bin/use-transport" oci "$stage" &&
    bash "$REPO_ROOT/bootstrap/any/usr/local/bin/drop-server" --pairs "$stage/etc/pacman.d" "$skip"
} > "$work/stage.out" 2>&1 || rc=$?
first="$(awk '/^Server/ { sub(/^[^=]*=[[:space:]]*/, ""); print; exit }' "$stage/etc/pacman.d/mirrorlist")"
if [ "$rc" -eq 0 ] && [ "$first" = "$(server newer)" ]; then
  ok "the build stage reads the server after the GHCR mirror first"
else
  fail "the build stage reads the server after the GHCR mirror first" \
    "want: $(server newer), exit 0" "got: ${first:-none}, exit $rc" \
    "SKIP_SERVERS: $skip" \
    "the list: $(tr '\n' '|' < "$stage/etc/pacman.d/mirrorlist")" \
    "it said: $(tr -d '\r' < "$work/stage.out" | tr '\n' '|')" \
    "reproduce: $REPRO"
fi

# The GHCR mirror is the only server of the tree list: a drop of both paths
# leaves no server, so the list stays.
lists ghcr
status "$work/status.json" 99999 99999
lag "with TRANSPORT=oci, a list with no server other than the GHCR mirror stays" "$KEEP_BOTH" \
  "${OCI_ENV[@]}" 'GHCR_OCI_SERVER=oci://fake/$arch/$repo'

summary
