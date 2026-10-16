#!/usr/bin/env bash
#
# use-transport changes the config of the build stage, and only that.
#
# bootstrap/any/usr/local/bin/use-transport TRANSPORT ROOT on a fixture build
# stage:
#   worker  changes nothing
#   oci     adds the XferCommand of pacman-oci to [options] once, and puts the
#           oci:// server first in each list that a section includes; the
#           other lines stay
#   a second oci run changes nothing
#   it refuses a ROOT named rootfs, an unknown TRANSPORT, and a ROOT with no
#   client
# ⛔ And no file that ships (rootfs/, mirrors/) has an uncommented XferCommand
# or an oci:// server.
#
# $arch and $repo are variables of pacman and stay literal in this file.
# shellcheck disable=SC2016
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

USE="$REPO_ROOT/bootstrap/any/usr/local/bin/use-transport"
REPRO="bash tests/static/43-use-transport.sh (the fixtures are in a temporary directory)"
OCI='oci://ghcr.io/pkgforge-dev/mirror-archlinux/$arch/$repo'
XFER='XferCommand = /usr/local/bin/pacman-oci %o %u'

work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

# stage DIR -> a fixture build stage
stage() {
  rm -rf "$1"
  mkdir -p "$1/etc/pacman.d" "$1/usr/local/bin"
  printf '#!/bin/sh\nexit 1\n' > "$1/usr/local/bin/pacman-oci"
  printf '[options]\nArchitecture = powerpc64le\n#XferCommand = /usr/bin/curl -L -C - -f -o %%o %%u\nSigLevel = Required DatabaseOptional\n\n[base]\nInclude = /etc/pacman.d/mirrorlist\n\n[base-any]\nInclude = /etc/pacman.d/mirrorlist-any\n' \
    > "$1/etc/pacman.conf"
  printf '##\n## a header\n##\n\nServer = https://ghcr.mirror.archlinux.pkgforge.dev/$arch/$repo\nServer = https://repo.archlinuxpower.org/$repo/$arch\n' \
    > "$1/etc/pacman.d/mirrorlist"
  printf 'Server = https://ghcr.mirror.archlinux.pkgforge.dev/$arch/$repo\nServer = https://repo.archlinuxpower.org/base/any\n' \
    > "$1/etc/pacman.d/mirrorlist-any"
}

snapshot() {
  cat "$1/etc/pacman.conf" "$1/etc/pacman.d/mirrorlist" "$1/etc/pacman.d/mirrorlist-any"
}

servers() {
  awk '/^Server/ { sub(/^[^=]*=[[:space:]]*/, ""); print }' "$1"
}

#---------------------------------------------------------------------------#
# worker
#---------------------------------------------------------------------------#
stage "$work/w"
snapshot "$work/w" > "$work/w.before"
rc=0
bash "$USE" worker "$work/w" 2> "$work/err" || rc=$?
if [ "$rc" -eq 0 ] && [ "$(snapshot "$work/w")" = "$(cat "$work/w.before")" ]; then
  ok "worker changes nothing"
else
  fail "worker changes nothing" "exit $rc" "it said: $(cat "$work/err")" "reproduce: $REPRO"
fi

#---------------------------------------------------------------------------#
# oci
#---------------------------------------------------------------------------#
stage "$work/o"
rc=0
bash "$USE" oci "$work/o" 2> "$work/err" || rc=$?
conf="$work/o/etc/pacman.conf"
xfer_lines="$(awk -v x="$XFER" '$0 == x { print NR }' "$conf")"
options_line="$(awk '/^\[options\]$/ { print NR }' "$conf")"
first_section="$(awk '/^\[/ && !/^\[options\]$/ { print NR; exit }' "$conf")"
if [ "$rc" -eq 0 ] && [ "$(awk 'NF { n++ } END { print n + 0 }' <<< "$xfer_lines")" -eq 1 ] &&
  [ "$xfer_lines" -gt "$options_line" ] && [ "$xfer_lines" -lt "$first_section" ]; then
  ok "oci puts one XferCommand of pacman-oci in [options]"
else
  fail "oci puts one XferCommand of pacman-oci in [options]" \
    "exit $rc, XferCommand at line(s) '$(tr '\n' ' ' <<< "$xfer_lines")', [options] at $options_line, the next section at $first_section" \
    "it said: $(cat "$work/err")" "reproduce: $REPRO"
fi

for l in mirrorlist mirrorlist-any; do
  got="$(servers "$work/o/etc/pacman.d/$l")"
  want="$OCI
$(servers "$(dirname "$work/o")/w/etc/pacman.d/$l")"
  if [ "$got" = "$want" ]; then
    ok "oci puts the oci:// server first in $l, and keeps the other servers in order"
  else
    fail "oci puts the oci:// server first in $l, and keeps the other servers in order" \
      "got: $(tr '\n' ' ' <<< "$got")" "want: $(tr '\n' ' ' <<< "$want")" "reproduce: $REPRO"
  fi
done
if grep -q '^## a header' "$work/o/etc/pacman.d/mirrorlist"; then
  ok "oci keeps the comments of a list"
else
  fail "oci keeps the comments of a list" "the header line is gone" "reproduce: $REPRO"
fi

snapshot "$work/o" > "$work/o.once"
rc=0
bash "$USE" oci "$work/o" 2> "$work/err" || rc=$?
if [ "$rc" -eq 0 ] && [ "$(snapshot "$work/o")" = "$(cat "$work/o.once")" ]; then
  ok "a second oci run changes nothing"
else
  fail "a second oci run changes nothing" "exit $rc" "it said: $(cat "$work/err")" "reproduce: $REPRO"
fi

#---------------------------------------------------------------------------#
# Refusals
#---------------------------------------------------------------------------#
# refused DESC ARG... -> exit 1, and the fixture stage is as it was
refused() {
  local desc="$1" rc=0
  shift
  stage "$work/r"
  snapshot "$work/r" > "$work/r.before"
  bash "$USE" "$@" 2> "$work/err" || rc=$?
  if [ "$rc" -eq 1 ] && [ "$(snapshot "$work/r")" = "$(cat "$work/r.before")" ]; then
    ok "$desc"
  else
    fail "$desc" "exit $rc (want 1), or a file changed" "it said: $(cat "$work/err")" "reproduce: $REPRO"
  fi
}
refused "ROOT=/rootfs, the tree that ships, is refused" oci /rootfs
refused "a TRANSPORT that is not worker or oci is refused" http "$work/r"
# A complete stage named rootfs, so only the name can refuse it.
stage "$work/rootfs"
snapshot "$work/rootfs" > "$work/rootfs.before"
rc=0
bash "$USE" oci "$work/rootfs/" 2> "$work/err" || rc=$?
if [ "$rc" -eq 1 ] && [ "$(snapshot "$work/rootfs")" = "$(cat "$work/rootfs.before")" ]; then
  ok "a complete stage named rootfs is refused, and stays as it was"
else
  fail "a complete stage named rootfs is refused, and stays as it was" \
    "exit $rc (want 1), or a file changed" "it said: $(cat "$work/err")" "reproduce: $REPRO"
fi
stage "$work/n"
rm "$work/n/usr/local/bin/pacman-oci"
rc=0
bash "$USE" oci "$work/n" 2> "$work/err" || rc=$?
if [ "$rc" -eq 1 ] && [ -z "$(grep_matches '^XferCommand' "$work/n/etc/pacman.conf")" ]; then
  ok "a ROOT with no pacman-oci is refused, and pacman.conf gets no XferCommand"
else
  fail "a ROOT with no pacman-oci is refused, and pacman.conf gets no XferCommand" \
    "exit $rc" "it said: $(cat "$work/err")" "reproduce: $REPRO"
fi

#---------------------------------------------------------------------------#
# ⛔ The files that ship
#---------------------------------------------------------------------------#
hits=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  h="$(awk '/^[[:space:]]*XferCommand[[:space:]]*=/ || /^[[:space:]]*Server[[:space:]]*=[[:space:]]*oci/ { print FILENAME ":" FNR }' "$f")"
  [ -z "$h" ] || hits="$hits ${h//$REPO_ROOT\//}"
done <<< "$(find "$REPO_ROOT/rootfs" "$REPO_ROOT/mirrors" -type f | LC_ALL=C sort)"
if [ -z "$hits" ]; then
  ok "no file in rootfs/ or mirrors/ has an XferCommand or an oci:// server"
else
  fail "no file in rootfs/ or mirrors/ has an XferCommand or an oci:// server" \
    "found:$hits" \
    "only use-transport adds them, in the build stage" \
    "reproduce: grep -rnE '^[[:space:]]*(XferCommand|Server[[:space:]]*=[[:space:]]*oci)' rootfs mirrors"
fi

summary
