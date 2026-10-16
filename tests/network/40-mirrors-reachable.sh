#!/usr/bin/env bash
#
# The servers of each mirror list, and the mirror lines of each keyring pin,
# answer from this network.
#
# The lists: each list that the pacman.conf of a port includes, for each port
# of scripts/ports list. Each server of a list gets one GET of the database
# of the first repository that reads the list. Per list:
#   - at least one anchor (the first servers, from the anchors file) answers 200
#   - at least half of the other servers answer 200
# Per keyring pin: at least one mirror line serves the pinned package.
# Each server that does not answer is named, with a reproduce line.
#
# Needs network and curl. Environment: MIRRORLIST_PROBE_TIMEOUT (seconds,
# default 20).
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

PROBE_TIMEOUT="${MIRRORLIST_PROBE_TIMEOUT:-20}"
CONCURRENCY=8
UA="docker-archlinux (+https://github.com/${GITHUB_REPOSITORY:-pkgforge-dev/docker-archlinux})"
PORTS="$REPO_ROOT/scripts/ports"

if ! need_tool curl awk timeout; then
  rc=0
  summary || rc=$?
  exit "$rc"
fi

work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

servers_of() {
  awk '/^[[:space:]]*Server[[:space:]]*=/ { sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); print }' "$1" | tr -d '\r'
}

# sections CONF -> "REPO LIST" for each enabled section, in file order
sections() {
  awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*\[/ { s = $0; sub(/^[[:space:]]*\[/, "", s); sub(/\].*$/, "", s); next }
    s != "" && s != "options" && /^[[:space:]]*Include[[:space:]]*=/ {
      v = $0; sub(/^[^=]*=[[:space:]]*/, "", v); sub(/[[:space:]]+$/, "", v); sub(/^.*\//, "", v)
      print s " " v
    }' "$1" | tr -d '\r'
}

# probe URL OUT -> writes the HTTP code to OUT
probe() {
  local code rc=0
  code="$(timeout -k 5 $((2 * PROBE_TIMEOUT + 10)) curl -s -L -o /dev/null -w '%{http_code}' -A "$UA" \
    --connect-timeout 10 --max-time "$PROBE_TIMEOUT" --retry 1 --retry-delay 2 "$1")" || rc=$?
  printf '%s\n' "${code:-000}" > "$2"
}

#---------------------------------------------------------------------------#
# Pass 1: queue each probe
#---------------------------------------------------------------------------#
n=0
specs="$work/specs"
: > "$specs"
while IFS= read -r arch; do
  [ -n "$arch" ] || continue
  conf="$REPO_ROOT/rootfs/$arch/etc/pacman.conf"
  parch="$("$PORTS" get "$arch" pacman_arch)"
  declare -A first_repo=()
  while read -r repo list; do
    [ -n "$repo" ] || continue
    [ -z "${first_repo[$list]+set}" ] || continue
    first_repo[$list]="$repo"
    rel="rootfs/$arch/etc/pacman.d/$list"
    case "$list" in
      mirrorlist) anchors="mirrors/$arch.anchors" ;;
      *) anchors="mirrors/$arch.${list#mirrorlist-}-anchors" ;;
    esac
    n_anchor="$(servers_of "$REPO_ROOT/$anchors" | awk 'NF { n++ } END { print n + 0 }')"

    # ⚠ The build writes a new list in its own checkout, and nothing writes
    # the committed list again. Its date is shown, not judged.
    gendate="$(awk 'match($0, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) { d = substr($0, RSTART, RLENGTH); exit } END { print d }' "$REPO_ROOT/$rel")"
    diag "$rel: the header date is ${gendate:-absent}"

    i=0
    while IFS= read -r s; do
      [ -n "$s" ] || continue
      i=$((i + 1))
      kind=ranked
      [ "$i" -gt "$n_anchor" ] || kind=anchor
      url="${s//\$repo/$repo}"
      url="${url//\$arch/$parch}/$repo.db"
      printf '%s\t%s\t%s\t%s\t%s\n' "$n" "$rel" "$kind" "$s" "$url" >> "$specs"
      n=$((n + 1))
    done <<< "$(servers_of "$REPO_ROOT/$rel")"
  done <<< "$(sections "$conf")"
  unset first_repo
done <<< "$("$PORTS" list)"

# The keyring pins: each mirror line with the pinned package
for pin in "$REPO_ROOT"/bootstrap/keyrings/*.pin; do
  [ -e "$pin" ] || continue
  pkg="$(awk -F= '$1 ~ /^[[:space:]]*package[[:space:]]*$/ { v = $2; gsub(/[[:space:]]/, "", v); print v }' "$pin" | tr -d '\r')"
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    printf '%s\t%s\t%s\t%s\t%s\n' "$n" "${pin#"$REPO_ROOT/"}" pin "$m" "$m/$pkg" >> "$specs"
    n=$((n + 1))
  done <<< "$(awk -F= '$1 ~ /^[[:space:]]*mirror[[:space:]]*$/ { v = $0; sub(/^[^=]*=[[:space:]]*/, "", v); sub(/[[:space:]]+$/, "", v); print v }' "$pin" | tr -d '\r')"
done

#---------------------------------------------------------------------------#
# Pass 2: probe, CONCURRENCY at the same time
#---------------------------------------------------------------------------#
started=0
while IFS=$'\t' read -r id _ _ _ url; do
  probe "$url" "$work/code.$id" &
  started=$((started + 1))
  if [ $((started % CONCURRENCY)) -eq 0 ]; then
    wait
  fi
done < "$specs"
wait

#---------------------------------------------------------------------------#
# Pass 3: judge each list and each pin
#---------------------------------------------------------------------------#
while IFS= read -r target; do
  [ -n "$target" ] || continue
  a_live=0
  a_all=0
  r_live=0
  r_all=0
  p_live=0
  p_all=0
  while IFS=$'\t' read -r id t kind s url; do
    [ "$t" = "$target" ] || continue
    code="$(cat "$work/code.$id" 2>&1)" || code=none
    live=0
    [ "$code" != 200 ] || live=1
    case "$kind" in
      anchor) a_all=$((a_all + 1)); a_live=$((a_live + live)) ;;
      ranked) r_all=$((r_all + 1)); r_live=$((r_live + live)) ;;
      pin) p_all=$((p_all + 1)); p_live=$((p_live + live)) ;;
    esac
    if [ "$live" -eq 0 ]; then
      diag "$target: HTTP $code from $s"
      diag "  reproduce: curl -s -o /dev/null -w '%{http_code}' -L '$url'"
    fi
  done < "$specs"

  if [ "$p_all" -gt 0 ]; then
    if [ "$p_live" -ge 1 ]; then
      ok "$target: $p_live of $p_all mirror lines serve the pinned package"
    else
      fail "$target: a mirror line serves the pinned package" \
        "0 of $p_all answered 200, each is named above" \
        "the build reads the copy in bootstrap/keyrings, so only a missing copy needs a mirror" \
        "reproduce: grep -n '^mirror' $target"
    fi
    continue
  fi
  if [ "$a_live" -ge 1 ]; then
    ok "$target: $a_live of $a_all anchors answer 200"
  else
    fail "$target: at least one anchor answers 200" \
      "0 of $a_all answered, each is named above" \
      "reproduce: scripts/gen-mirrorlist <arch>, which probes the anchors"
  fi
  if [ "$r_all" -gt 0 ]; then
    if [ $((2 * r_live)) -ge "$r_all" ]; then
      ok "$target: $r_live of $r_all ranked servers answer 200, at least half"
    else
      fail "$target: at least half of the ranked servers answer 200" \
        "$r_live of $r_all answered, each other is named above" \
        "regenerate with: scripts/gen-mirrorlist <arch>" \
        "reproduce: bash tests/network/40-mirrors-reachable.sh"
    fi
  fi
done <<< "$(cut -f2 "$specs" | awk '!seen[$0]++')"

summary
