#!/usr/bin/env bash
#
# The vendored pacman-oci is the file that bootstrap/pacman-oci.pin names.
#
#   1. the pin has source, raw and sha256; source and raw name the same
#      commit (40 hex) and the path client/pacman-oci of
#      pkgforge-dev/mirror-archlinux
#   2. bootstrap/any/usr/local/bin/pacman-oci has the sha256 of the pin
#   3. the copy has LF line ends, starts with #!/bin/sh, and sh -n reads it
#   4. --version prints "pacman-oci N"
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

PIN="$REPO_ROOT/bootstrap/pacman-oci.pin"
COPY="$REPO_ROOT/bootstrap/any/usr/local/bin/pacman-oci"

field() {
  awk -F= -v k="$1" '
    $0 ~ /^[[:space:]]*#/ { next }
    $1 ~ "^[[:space:]]*" k "[[:space:]]*$" {
      sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); print
    }' "$PIN" | tr -d '\r'
}

if [ ! -f "$PIN" ] || [ ! -f "$COPY" ]; then
  fail "the pin and the copy exist" \
    "pin: $([ -f "$PIN" ] && echo yes || echo no), copy: $([ -f "$COPY" ] && echo yes || echo no)" \
    "reproduce: ls -l bootstrap/pacman-oci.pin bootstrap/any/usr/local/bin/pacman-oci"
  summary
  exit 1
fi

# 1. The fields
source="$(field source)"
raw="$(field raw)"
want="$(field sha256)"
re_source='^https://github\.com/pkgforge-dev/mirror-archlinux/blob/([0-9a-f]{40})/client/pacman-oci$'
re_raw='^https://raw\.githubusercontent\.com/pkgforge-dev/mirror-archlinux/([0-9a-f]{40})/client/pacman-oci$'
c1=""
c2=""
[[ "$source" =~ $re_source ]] && c1="${BASH_REMATCH[1]}"
[[ "$raw" =~ $re_raw ]] && c2="${BASH_REMATCH[1]}"
if [ -n "$c1" ] && [ "$c1" = "$c2" ] && [[ "$want" =~ ^[0-9a-f]{64}$ ]]; then
  ok "the pin names one commit ($c1) in source and raw, and a sha256"
else
  fail "the pin names one commit in source and raw, and a sha256" \
    "source: ${source:-none}" "raw: ${raw:-none}" "sha256: ${want:-none}" \
    "reproduce: cat bootstrap/pacman-oci.pin"
fi

# 2. The sha256
got="$(sha256sum "$COPY" | cut -d' ' -f1)"
if [ "$got" = "$want" ]; then
  ok "the copy has the sha256 of the pin"
else
  fail "the copy has the sha256 of the pin" \
    "pin : $want" "copy: $got" \
    "⛔ the copy and the pin change together" \
    "reproduce: sha256sum bootstrap/any/usr/local/bin/pacman-oci"
fi

# 3. The shape
crs="$(tr -cd '\r' < "$COPY" | wc -c | tr -d '[:space:]')"
first="$(awk 'NR == 1' "$COPY")"
rc=0
said="$(sh -n "$COPY" 2>&1)" || rc=$?
if [ "$crs" -eq 0 ] && [ "$first" = '#!/bin/sh' ] && [ "$rc" -eq 0 ]; then
  ok "the copy has LF line ends, starts with #!/bin/sh, and sh -n reads it"
else
  fail "the copy has LF line ends, starts with #!/bin/sh, and sh -n reads it" \
    "carriage returns: $crs, line 1: $first, sh -n: exit $rc $said" \
    "reproduce: head -1 bootstrap/any/usr/local/bin/pacman-oci; sh -n bootstrap/any/usr/local/bin/pacman-oci"
fi

# 4. --version
v="$(sh "$COPY" --version 2>&1)" || v="exit $?: $v"
if [[ "$v" =~ ^pacman-oci\ [0-9]+$ ]]; then
  ok "--version prints '$v'"
else
  fail "--version prints 'pacman-oci N'" "got: $v" \
    "reproduce: sh bootstrap/any/usr/local/bin/pacman-oci --version"
fi

summary
