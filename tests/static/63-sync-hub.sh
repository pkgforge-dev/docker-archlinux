#!/usr/bin/env bash
#
# scripts/sync-hub copies to Docker Hub each GHCR tag that Docker Hub lacks
# (pinned) or that points at another digest (rolling), and nothing else.
#
# Each case runs `scripts/sync-hub --fixtures DIR`: no registry is called and
# nothing is written. The aliases come from scripts/ports.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

SYNC="$REPO_ROOT/scripts/sync-hub"
PORTS="$REPO_ROOT/scripts/ports"

if [ ! -x "$SYNC" ]; then
  fail "scripts/sync-hub is executable" "reproduce: ls -l scripts/sync-hub"
  summary
  exit 1
fi

work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

SRC="ghcr.io/example/archlinux"
HUB="docker.io/example/archlinux"
P1="$("$PORTS" list | awk 'NR == 1')"
P2="$("$PORTS" list | awk 'NR == 2')"
A1="$("$PORTS" aliases "$P1" | awk 'NR == 1')"
A2="$("$PORTS" aliases "$P2" | awk 'NR == 1')"
digest() { printf 'sha256:%064d' "$1"; }

setup() {
  FX="$work/$1"
  mkdir -p "$FX"
  : > "$FX/tags.tsv"
  : > "$FX/heads.tsv"
}
# on REGISTRY TAG N -> the tag is on REGISTRY with digest N
on() {
  local repo=example/archlinux
  printf '%s\t%s\t%s\n' "$1" "$repo" "$2" >> "$FX/tags.tsv"
  printf '%s\t%s\t%s\t200\t%s\n' "$1" "$repo" "$2" "$(digest "$3")" >> "$FX/heads.tsv"
}
run_sync() {
  local rc=0
  env SOURCE_IMAGE="$SRC" HUB_TARGET="$HUB" RETRY_PAUSE=0 \
    "$SYNC" --fixtures "$FX" > "$FX/out" 2> "$FX/err" || rc=$?
  printf '%s\n' "$rc"
}
repro="bash tests/static/63-sync-hub.sh; the fixtures are made in the test"

#---------------------------------------------------------------------------#
# Case "mixed".
#---------------------------------------------------------------------------#
setup mixed
# On both, in step.
on ghcr.io v2030.01.01 1
on docker.io v2030.01.01 1
on ghcr.io "$A1" 2
on docker.io "$A1" 2
on ghcr.io "$A1-v2030.01.02" 3
on docker.io "$A1-v2030.01.02" 3
# A pinned tag on both with another digest: never moved.
on ghcr.io "$A1-v2030.01.01" 4
on docker.io "$A1-v2030.01.01" 44
# latest moved on GHCR.
on ghcr.io latest 5
on docker.io latest 55
# Not on Docker Hub.
on ghcr.io v2030.01.02 6
on ghcr.io "$A1-7.1.0-1" 3
on ghcr.io "$A2" 7
on ghcr.io "$A2-v2030.01.02" 7

rc="$(run_sync)"
out="$FX/out"
if [ "$rc" -eq 0 ]; then
  ok "mixed: the dry plan exits 0"
else
  fail "mixed: the dry plan exits 0" "exit $rc: $(tr '\n' '|' < "$FX/err")" "reproduce: $repro"
fi

want="copy $A1-7.1.0-1 $(digest 3) pinned
copy $A2 $(digest 7) rolling
copy $A2-v2030.01.02 $(digest 7) pinned
copy v2030.01.02 $(digest 6) pinned
move latest $(digest 55) $(digest 5)"
got="$(awk '/^(copy|move) /' "$out" | LC_ALL=C sort)"
if [ "$got" = "$(LC_ALL=C sort <<< "$want")" ]; then
  ok "mixed: the missing pinned tags are copied, a missing rolling tag is copied, a moved rolling tag moves"
else
  fail "mixed: the missing pinned tags are copied, a missing rolling tag is copied, a moved rolling tag moves" \
    "got: $(tr '\n' '|' <<< "$got")" "want: $(tr '\n' '|' <<< "$want")" "reproduce: $repro"
fi

if ! grep -q -- " $A1-v2030.01.01 " "$out"; then
  ok "mixed: a pinned tag with another digest on Docker Hub is not moved"
else
  fail "mixed: a pinned tag with another digest on Docker Hub is not moved" \
    "$(grep -- "$A1-v2030.01.01" "$out")" "⛔ a pinned tag never points at another image" "reproduce: $repro"
fi

summary_line="$(awk '/^summary /' "$out")"
if [ "$summary_line" = "summary tags=9 in_step=4 copy=4 move=1 failed=0" ]; then
  ok "mixed: the summary counts each tag once"
else
  fail "mixed: the summary counts each tag once" "got: ${summary_line:-none}" "reproduce: $repro"
fi

#---------------------------------------------------------------------------#
# Lists that cannot be read, and a tag that GHCR does not answer for.
#---------------------------------------------------------------------------#
setup nosource
on ghcr.io latest 5
printf 'ghcr.io\texample/archlinux\n' > "$FX/unreadable"
rc="$(run_sync)"
if [ "$rc" -ne 0 ] && ! grep -qE '^(copy|move) ' "$FX/out"; then
  ok "a GHCR tag list that cannot be read stops the copy"
else
  fail "a GHCR tag list that cannot be read stops the copy" "exit $rc" "reproduce: $repro"
fi

setup nohub
on ghcr.io latest 5
printf 'docker.io\texample/archlinux\n' > "$FX/unreadable"
rc="$(run_sync)"
if [ "$rc" -ne 0 ] && ! grep -qE '^(copy|move) ' "$FX/out"; then
  ok "a Docker Hub tag list that cannot be read stops the copy"
else
  fail "a Docker Hub tag list that cannot be read stops the copy" "exit $rc" \
    "read as empty, every tag would be copied again" "reproduce: $repro"
fi

setup nohead
on ghcr.io latest 5
printf 'ghcr.io\texample/archlinux\tv2030.01.03\n' >> "$FX/tags.tsv"
printf 'ghcr.io\texample/archlinux\tv2030.01.03\t500\t\n' >> "$FX/heads.tsv"
rc="$(run_sync)"
if [ "$rc" -ne 0 ] && grep -q '^copy latest ' "$FX/out" && grep -q 'failed=1$' "$FX/out"; then
  ok "a tag that GHCR does not answer for fails the run, and the other tags still copy"
else
  fail "a tag that GHCR does not answer for fails the run, and the other tags still copy" \
    "exit $rc; stdout: $(tr '\n' '|' < "$FX/out")" "reproduce: $repro"
fi

setup empty
printf 'docker.io\texample/archlinux\tlatest\n' > "$FX/tags.tsv"
rc="$(run_sync)"
if [ "$rc" -ne 0 ]; then
  ok "an empty GHCR tag list stops the copy"
else
  fail "an empty GHCR tag list stops the copy" "exit 0" "reproduce: $repro"
fi

summary
