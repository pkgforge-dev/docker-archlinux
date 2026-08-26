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

lists="$(find "$REPO_ROOT/rootfs" -type f -path '*/etc/pacman.d/mirrorlist' | sort)"
if [ -z "$lists" ]; then
  fail "at least one mirrorlist exists" "searched: $REPO_ROOT/rootfs"
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
    fail "$rel has a sibling pacman.conf" "expected: rootfs/$archdir/etc/pacman.conf"
    continue
  fi
  arch="$(awk -F= '/^[[:space:]]*Architecture[[:space:]]*=/ {gsub(/[[:space:]]/,"",$2); print $2; exit}' "$conf")"
  if [ -z "$arch" ]; then
    fail "$rel resolves \$arch from pacman.conf" \
      "no uncommented Architecture line in rootfs/$archdir/etc/pacman.conf"
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
        "the bound is $MAX_AGE_DAYS days, set MIRRORLIST_MAX_AGE_DAYS to change it"
    else
      ok "$rel was generated $gendate, $age_days days ago"
    fi
  fi

  servers="$(awk '/^[[:space:]]*Server[[:space:]]*=/ {sub(/^[^=]*=[[:space:]]*/,""); print}' "$list")"
  count="$(awk 'NF' <<< "$servers" | wc -l | tr -d '[:space:]')"

  if [ "$count" -lt "$MIN_SERVERS" ]; then
    fail "$rel offers a fallback server" \
      "active servers: $count, minimum: $MIN_SERVERS" \
      "with one entry there is nothing to fall through to when it fails" \
      "reproduce: grep -c '^Server' $rel"
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

  # queue reachability probes
  while IFS= read -r server; do
    [ -n "$server" ] || continue
    # pacman substitutes these two itself, so the probe must do the same
    url="${server//\$repo/core}"
    url="${url//\$arch/$arch}"
    url="$url/core.db"
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
    code="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time "$PROBE_TIMEOUT" --retry "$PROBE_RETRIES" --retry-delay 2 --retry-all-errors -L "$url")" || code="000"
    printf '%s\n' "$code" > "${spec}.code"
  ) &
  started=$((started + 1))
  if [ $((started % CONCURRENCY)) -eq 0 ]; then
    wait
  fi
done
wait

# Pass three: report.
dead=0
alive=0
for spec in "$resdir"/spec.*; do
  case "$spec" in *.code) continue ;; esac
  [ -e "$spec" ] || continue
  rel="$(cut -f1 < "$spec")"
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
    fail "mirror answers: $server" \
      "in $rel" \
      "HTTP $code for $url" \
      "reproduce: curl -s -o /dev/null -w '%{http_code}' -L '$url'"
    dead=$((dead + 1))
  fi
done

if [ "$dead" -eq 0 ]; then
  ok "all $alive mirror entries answer 200"
else
  diag "$dead of $((dead + alive)) mirror entries did not answer 200"
fi

summary
