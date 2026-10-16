#!/usr/bin/env bash
#
# Each mirror list in the tree starts with its anchors file, in order.
#
# For each port (scripts/ports list) and each list that its pacman.conf
# includes:
#   - the anchors file of the list exists (mirrors/ARCH.anchors for mirrorlist,
#     mirrors/ARCH.X-anchors for mirrorlist-X)
#   - the list starts with the servers of that file, in file order
#   - the list has at least 2 servers and at least one https server
#   - the list has no oci:// server
#   - the header gives a date that parses and is not in the future
# And over the tree:
#   - each mirrorlist* file is a list that a pacman.conf includes
#   - each mirrors/*.pool line is a comment, a Server line or a known source
#
# Hermetic: no network. tests/network/40-mirrors-reachable.sh probes the
# servers.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

PORTS="$REPO_ROOT/scripts/ports"

servers_of() {
  awk '/^[[:space:]]*Server[[:space:]]*=/ { sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); print }' "$1" | tr -d '\r'
}

# includes CONF -> the file name of each list that an enabled section includes
includes() {
  awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*\[/ { s = $0; next }
    s !~ /\[options\]/ && /^[[:space:]]*Include[[:space:]]*=/ {
      v = $0; sub(/^[^=]*=[[:space:]]*/, "", v); sub(/[[:space:]]+$/, "", v)
      sub(/^.*\//, "", v)
      if (!seen[v]++) print v
    }' "$1" | tr -d '\r'
}

arches="$("$PORTS" list)"
if [ -z "$arches" ]; then
  fail "scripts/ports lists at least one port" \
    "it printed nothing" \
    "reproduce: scripts/ports list"
  summary
  exit 1
fi

today="$(date -u +%Y-%m-%d)"
checked=0
included=""
while IFS= read -r arch; do
  [ -n "$arch" ] || continue
  conf="$REPO_ROOT/rootfs/$arch/etc/pacman.conf"
  lists="$(includes "$conf")"
  if [ -z "$lists" ]; then
    fail "rootfs/$arch/etc/pacman.conf includes a list" \
      "no enabled section has an Include line" \
      "reproduce: grep -n Include rootfs/$arch/etc/pacman.conf"
    continue
  fi
  while IFS= read -r list; do
    [ -n "$list" ] || continue
    checked=$((checked + 1))
    rel="rootfs/$arch/etc/pacman.d/$list"
    included="$included$rel
"
    file="$REPO_ROOT/$rel"
    case "$list" in
      mirrorlist) anchors_rel="mirrors/$arch.anchors" ;;
      mirrorlist-?*) anchors_rel="mirrors/$arch.${list#mirrorlist-}-anchors" ;;
      *) anchors_rel="" ;;
    esac
    if [ ! -f "$file" ]; then
      fail "$rel exists" "rootfs/$arch/etc/pacman.conf includes it" \
        "reproduce: scripts/gen-mirrorlist $arch"
      continue
    fi
    if [ -z "$anchors_rel" ] || [ ! -f "$REPO_ROOT/$anchors_rel" ]; then
      fail "$rel has an anchors file" \
        "expected: ${anchors_rel:-a list named mirrorlist or mirrorlist-<name>}" \
        "reproduce: ls mirrors/"
      continue
    fi

    got="$(servers_of "$file")"
    want="$(servers_of "$REPO_ROOT/$anchors_rel")"
    n_want="$(awk 'NF { n++ } END { print n + 0 }' <<< "$want")"
    head_of="$(awk -v n="$n_want" 'NF && ++c <= n' <<< "$got")"
    if [ "$n_want" -gt 0 ] && [ "$head_of" = "$want" ]; then
      ok "$rel starts with the $n_want server(s) of $anchors_rel, in order"
    else
      fail "$rel starts with the servers of $anchors_rel, in order" \
        "anchors: $(tr '\n' ' ' <<< "$want")" \
        "first $n_want of the list: $(tr '\n' ' ' <<< "$head_of")" \
        "regenerate with: scripts/gen-mirrorlist $arch" \
        "reproduce: diff <(grep '^Server' $anchors_rel) <(grep '^Server' $rel | awk 'NR <= $n_want')"
    fi

    count="$(awk 'NF { n++ } END { print n + 0 }' <<< "$got")"
    https="$(awk '/^https:\/\// { n++ } END { print n + 0 }' <<< "$got")"
    if [ "$count" -ge 2 ] && [ "$https" -ge 1 ]; then
      ok "$rel has $count servers, $https over https"
    else
      fail "$rel has at least 2 servers and one over https" \
        "servers: $count, https: $https" \
        "reproduce: grep '^Server' $rel"
    fi

    oci="$(awk '/^oci/' <<< "$got")"
    if [ -z "$oci" ]; then
      ok "$rel has no oci:// server"
    else
      fail "$rel has no oci:// server" \
        "found: $(tr '\n' ' ' <<< "$oci")" \
        "only use-transport adds one, in the build stage" \
        "reproduce: grep -n oci: $rel"
    fi

    gendate="$(awk 'match($0, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) { print substr($0, RSTART, RLENGTH); exit }' "$file")"
    parsed=""
    if [ -n "$gendate" ]; then
      parsed="$(date -u -d "$gendate" +%Y-%m-%d 2>&1)" || parsed=""
    fi
    if [ -n "$gendate" ] && [ "$parsed" = "$gendate" ] && ! [[ "$gendate" > "$today" ]]; then
      ok "$rel gives the date it was generated, $gendate"
    else
      fail "$rel gives a valid date that is not in the future" \
        "found: ${gendate:-no YYYY-MM-DD}, today: $today" \
        "reproduce: grep -n Generated $rel"
    fi
  done <<< "$lists"
done <<< "$arches"

if [ "$checked" -eq 0 ]; then
  fail "at least one list was checked" "no port includes a list" \
    "reproduce: grep -n Include rootfs/*/etc/pacman.conf"
fi

# Each mirrorlist* file is a list that a pacman.conf includes.
orphans=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  rel="${f#"$REPO_ROOT/"}"
  if ! grep -qxF -e "$rel" <<< "$included"; then
    orphans="$orphans $rel"
  fi
done <<< "$(find "$REPO_ROOT/rootfs" -path '*/etc/pacman.d/mirrorlist*' -type f | LC_ALL=C sort)"
if [ -z "$orphans" ]; then
  ok "each mirrorlist file in rootfs/ is a list that a pacman.conf includes"
else
  fail "each mirrorlist file in rootfs/ is a list that a pacman.conf includes" \
    "not included:$orphans" \
    "reproduce: grep -rn Include rootfs/*/etc/pacman.conf"
fi

# Each pool line is a comment, a Server line or a known source.
bad=""
for pool in "$REPO_ROOT"/mirrors/*.pool; do
  [ -e "$pool" ] || continue
  bad="$bad$(awk -v f="${pool#"$REPO_ROOT/"}" '
    /^[[:space:]]*(#|$)/ { next }
    /^[[:space:]]*Server[[:space:]]*=[[:space:]]*[^[:space:]]+[[:space:]]*$/ { next }
    /^[[:space:]]*source[[:space:]]*=[[:space:]]*(status-json|mirrorlist)[[:space:]]+[^[:space:]]+[[:space:]]*$/ { next }
    /^[[:space:]]*source[[:space:]]*=[[:space:]]*mirrorlist-package([[:space:]]+[^[:space:]]+){3}[[:space:]]*$/ { next }
    { printf " %s:%d", f, FNR }' "$pool")"
done
if [ -z "$bad" ]; then
  ok "each line of mirrors/*.pool is a comment, a Server line or a known source"
else
  fail "each line of mirrors/*.pool is a comment, a Server line or a known source" \
    "lines:$bad" \
    "scripts/gen-mirrorlist gives the format" \
    "reproduce: grep -vnE '^[[:space:]]*(#|$|Server|source)' mirrors/*.pool"
fi

summary
