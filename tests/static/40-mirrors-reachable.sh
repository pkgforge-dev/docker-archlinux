#!/usr/bin/env bash
#
# Every shipped mirrorlist must be current, reachable, and have a fallback.
#
# Three separate defects live in these files. Entries that no longer resolve,
# lists with no generation date so staleness cannot be measured, and an
# architecture with a single server so there is nothing to fall through to
# when that one server fails. The riscv64 outage was the third of those.
#
# Needs network. MIRRORLIST_MAX_AGE_DAYS bounds how old a list may be.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

MAX_AGE_DAYS="${MIRRORLIST_MAX_AGE_DAYS:-90}"
PROBE_TIMEOUT="${MIRRORLIST_PROBE_TIMEOUT:-20}"
PROBE_RETRIES="${MIRRORLIST_PROBE_RETRIES:-2}"
CONCURRENCY=8
MIN_SERVERS=2

# ⛔ The same identity scripts/gen-mirrorlist and scripts/resolve-anchor send.
# This probe used to send curl's default, so it was not asking the question the
# tools ask: a mirror that filters on User-Agent would answer one of them and
# not the other, and the difference would read as the mirror being down.
UA="${MIRROR_PROBE_UA:-docker-archlinux-mirrorlist/1 (+https://github.com/pkgforge-dev/docker-archlinux)}"

# reachable_floor_for ARCHDIR -> how many of that port's servers must answer
#
# ⛔ Not the same question as how many it ships. The three PowerPC ports ship two
# servers and never have both answer from one network: ArchPOWER's origin sits
# behind a bot challenge that refuses datacentre address ranges, so a
# workstation reaches the origin and a GitHub runner reaches only the read
# through proxy beside it. Measured 2026-08-28 from a runner: 403 for curl's own
# user agent, for pacman's, for a browser's and for this repository's, with a
# Cloudflare interstitial as the body every time.
#
# ⚠ So one answering is the pass for those three. The count assertion above is
# unchanged and still requires both entries to be present, so a port that lost
# its second server fails there rather than here. HISTORY/powerpc.md.
reachable_floor_for() {
  case "$1" in
    ppc | ppc64 | ppc64le) printf '1\n' ;;
    *) printf '%s\n' "$MIN_SERVERS" ;;
  esac
}

lists="$(find "$REPO_ROOT/rootfs" -type f -path '*/etc/pacman.d/mirrorlist' | sort)"
if [ -z "$lists" ]; then
  fail "at least one mirrorlist exists" "searched: $REPO_ROOT/rootfs" \
    "reproduce: ls rootfs/*/etc/pacman.d/mirrorlist"
  summary
  exit 1
fi

resdir="$(mktemp -d)"
trap 'rm -rf "$resdir"' EXIT

now_epoch="$(date -u +%s)"
probe_index=0

# Pass one: parse and assert on shape, and queue the reachability probes.
while IFS= read -r list; do
  [ -n "$list" ] || continue
  rel="${list#"$REPO_ROOT/"}"
  archdir="$(basename "$(dirname "$(dirname "$(dirname "$list")")")")"
  conf="$REPO_ROOT/rootfs/$archdir/etc/pacman.conf"

  # pacman substitutes $arch with the Architecture from its own config
  if [ ! -f "$conf" ]; then
    fail "$rel has a sibling pacman.conf" "expected: rootfs/$archdir/etc/pacman.conf" \
      "reproduce: ls rootfs/$archdir/etc/pacman.conf"
    continue
  fi
  arch="$(awk -F= '/^[[:space:]]*Architecture[[:space:]]*=/ {gsub(/[[:space:]]/,"",$2); print $2; exit}' "$conf")"
  if [ -z "$arch" ]; then
    fail "$rel resolves \$arch from pacman.conf" \
      "no uncommented Architecture line in rootfs/$archdir/etc/pacman.conf" \
      "reproduce: grep -n Architecture rootfs/$archdir/etc/pacman.conf"
    continue
  fi

  # a generation date, so staleness is measurable at all
  gendate="$(awk 'match($0, /[0-9]{4}-[0-9]{2}-[0-9]{2}/) { print substr($0, RSTART, RLENGTH); exit }' "$list")"
  if [ -z "$gendate" ]; then
    fail "$rel carries a generation date" \
      "no YYYY-MM-DD found in the file" \
      "an undated list cannot be checked for staleness" \
      "reproduce: grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' $rel"
  else
    gen_epoch="$(date -u -d "$gendate" +%s)"
    age_days=$(((now_epoch - gen_epoch) / 86400))
    if [ "$age_days" -gt "$MAX_AGE_DAYS" ]; then
      fail "$rel is not stale" \
        "generated $gendate, which is $age_days days ago" \
        "the bound is $MAX_AGE_DAYS days, set MIRRORLIST_MAX_AGE_DAYS to change it" \
        "reproduce: scripts/gen-mirrorlist $archdir"
    else
      ok "$rel was generated $gendate, $age_days days ago"
    fi
  fi

  servers="$(awk '/^[[:space:]]*Server[[:space:]]*=/ {sub(/^[^=]*=[[:space:]]*/,""); print}' "$list")"
  count="$(awk 'NF' <<< "$servers" | wc -l | tr -d '[:space:]')"
  min="$MIN_SERVERS"

  if [ "$count" -lt "$min" ]; then
    fail "$rel offers a fallback server" \
      "active servers: $count, minimum: $min" \
      "with one entry there is nothing to fall through to when it fails" \
      "reproduce: awk '/^Server/ { c++ } END { print c + 0 }' $rel"
  else
    ok "$rel offers $count active servers"
  fi

  if printf '%s\n' "$servers" | grep -q '^https://'; then
    ok "$rel has at least one https server"
  else
    fail "$rel has at least one https server" \
      "every active entry is plain HTTP" \
      "reproduce: grep '^Server' $rel"
  fi

  # ⛔ The repository name comes from the config, not from the word core.
  # ArchPOWER's primary repository is base and its database is base.db, so a
  # probe that assumes core asks three of the eight ports for a path that
  # answers 404 and then reports every one of their mirrors as dead.
  repo="$(awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*\[/ {
      name = $0
      sub(/^[[:space:]]*\[/, "", name)
      sub(/\].*$/, "", name)
      if (name != "options") { print name; exit }
    }' "$conf")"
  if [ -z "$repo" ]; then
    fail "rootfs/$archdir/etc/pacman.conf declares a repository" \
      "no uncommented section other than [options]" \
      "the probe asks that repository for its database, so there has to be one" \
      "reproduce: grep -n '^\[' rootfs/$archdir/etc/pacman.conf"
    continue
  fi

  # queue reachability probes
  while IFS= read -r server; do
    [ -n "$server" ] || continue
    # pacman substitutes these two itself, so the probe must do the same
    url="${server//\$repo/$repo}"
    url="${url//\$arch/$arch}"
    url="$url/$repo.db"
    printf '%s\t%s\t%s\n' "$rel" "$server" "$url" > "$resdir/spec.$probe_index"
    probe_index=$((probe_index + 1))
  done <<< "$servers"
done <<< "$lists"

# Pass two: probe, bounded concurrency.
started=0
for spec in "$resdir"/spec.*; do
  [ -e "$spec" ] || continue
  (
    url="$(cut -f3 < "$spec")"
    code="$(curl -s -o /dev/null -w '%{http_code}' -A "$UA" --connect-timeout 10 --max-time "$PROBE_TIMEOUT" --retry "$PROBE_RETRIES" --retry-delay 2 --retry-all-errors -L "$url")" || code="000"
    printf '%s\n' "$code" > "${spec}.code"
  ) &
  started=$((started + 1))
  if [ $((started % CONCURRENCY)) -eq 0 ]; then
    wait
  fi
done
wait

# Pass three: report, per architecture.
#
# ⚠ The assertion is a floor per list, not "every entry answers". A mirror list
# exists so pacman can fall through, and a single entry failing does not produce
# a wrong image. Mirrors also block by source network: one entry in the amd64
# list answers 200 from a workstation and 403 from a GitHub runner, so a
# strict rule would make the repository unbuildable for a reason outside it.
#
# The defect this guards is the one that caused the outage: riscv64 shipped with
# a single active server and nothing to fall through to. So each list must keep
# at least MIN_SERVERS reachable, and at least half of what it ships. Every dead
# entry is still named, because a list quietly decaying towards the floor is the
# thing worth seeing early.
dead_total=0
alive_total=0
while IFS= read -r list; do
  [ -n "$list" ] || continue
  rel="${list#"$REPO_ROOT/"}"
  archdir="$(basename "$(dirname "$(dirname "$(dirname "$list")")")")"
  dead=0
  alive=0
  for spec in "$resdir"/spec.*; do
    case "$spec" in *.code) continue ;; esac
    [ -e "$spec" ] || continue
    [ "$(cut -f1 < "$spec")" = "$rel" ] || continue
    server="$(cut -f2 < "$spec")"
    url="$(cut -f3 < "$spec")"
    if [ -f "${spec}.code" ]; then
      code="$(cat "${spec}.code")"
    else
      code="probe-did-not-run"
    fi
    if [ "$code" = "200" ]; then
      alive=$((alive + 1))
    else
      dead=$((dead + 1))
      diag "$rel: HTTP $code from $server"
      diag "  reproduce: curl -s -o /dev/null -w '%{http_code}' -L '$url'"
    fi
  done

  total=$((alive + dead))
  [ "$total" -gt 0 ] || continue
  # at least the port's floor, and at least half the list
  floor="$(reachable_floor_for "$archdir")"
  half=$(((total + 1) / 2))
  [ "$half" -gt "$floor" ] && floor="$half"

  if [ "$alive" -ge "$floor" ]; then
    ok "$rel: $alive of $total servers answer 200, floor is $floor"
  else
    fail "$rel keeps at least $floor reachable servers" \
      "reachable: $alive of $total" \
      "a list at or below the floor is how the riscv64 outage started" \
      "regenerate with: scripts/gen-mirrorlist $archdir" \
      "reproduce: awk '/^Server/ { c++ } END { print c + 0 }' $rel"
  fi

  dead_total=$((dead_total + dead))
  alive_total=$((alive_total + alive))
done <<< "$lists"

if [ "$dead_total" -eq 0 ]; then
  ok "every one of the $alive_total mirror entries answers 200"
else
  diag "$dead_total of $((dead_total + alive_total)) entries did not answer 200, named above"
fi

summary
