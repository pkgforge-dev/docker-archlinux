#!/usr/bin/env bash
#
# scripts/gen-mirrorlist writes the lists of a port together, anchors first,
# or leaves each list of the port as it was.
#
# The fixture port has [base] (mirrorlist) and [base-any] (mirrorlist-any).
# A server is a file:// directory; it answers when the database file is there.
# Cases:
#   - one dead anchor in each list: both lists are written, each anchor in
#     file order, then the candidates that answer
#   - each any-anchor dead: exit 3, and BOTH lists stay as they were
#   - each main anchor dead: exit 3, both lists stay
#   - no pool file: the anchors only
#   - pool sources: the first source that gives candidates is used; when no
#     source answers, exit 3
#   - status-json: only https, active, complete, recent mirrors with a score
#   - mirrorlist-package: the mirror list file in a package that a repository
#     database names, used when the first source does not answer
#   - a list keeps at least half of its ranked servers, else exit 3
#   - a budget of 0 seconds: exit 3
#   - a list with fewer servers than MIN_SERVERS: exit 3 (the other cases set
#     MIN_SERVERS=1, because their lists are small)
#   - a pool line it cannot read, an oci:// anchor, an unknown port: exit 1
#   - all: one port written, one left as it was, exit 3
#
# $repo is a variable of pacman and stays literal in this file.
# shellcheck disable=SC2016
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

GEN="$REPO_ROOT/scripts/gen-mirrorlist"
REPRO="bash tests/static/48-gen-mirrorlist.sh (the fixtures are in a temporary directory)"
TODAY="$(date -u +%Y-%m-%d)"

if ! need_tool curl jq tar gzip; then
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

# live NAME... -> each fixture server answers for base and base-any
live() {
  local s r
  for s in "$@"; do
    for r in base base-any; do
      mkdir -p "$work/srv/$s/$r"
      printf 'db\n' > "$work/srv/$s/$r/$r.db"
    done
  done
}

# tree CASE [ARCH] -> a fixture tree with one port; its lists in the tree have
# a header and no server
tree() {
  local c="$1" a="${2:-fake}"
  mkdir -p "$work/$c/ports" "$work/$c/rootfs/$a/etc/pacman.d" "$work/$c/mirrors"
  printf 'arch = %s\npacman_arch = powerpc64le\nrepos = base base-any\n' "$a" > "$work/$c/ports/$a.conf"
  printf '[options]\nArchitecture = powerpc64le\n\n[base]\nInclude = /etc/pacman.d/mirrorlist\n\n[base-any]\nInclude = /etc/pacman.d/mirrorlist-any\n' \
    > "$work/$c/rootfs/$a/etc/pacman.conf"
  printf '## the list in the tree\n' > "$work/$c/rootfs/$a/etc/pacman.d/mirrorlist"
  printf '## the list in the tree\n' > "$work/$c/rootfs/$a/etc/pacman.d/mirrorlist-any"
}

# anchors CASE FILE NAME... -> mirrors/FILE with one Server line for each name
anchors() {
  local c="$1" f="$2" s
  shift 2
  for s in "$@"; do
    printf 'Server = %s\n' "$(server "$s")"
  done > "$work/$c/mirrors/$f"
}

# gen CASE [ENV=VALUE ...] [-- ARG] -> runs the script; status in CASE.rc
gen() {
  local c="$1" rc=0
  shift
  local -a envs=() args=(fake)
  while [ "$#" -gt 0 ]; do
    if [ "$1" = -- ]; then
      shift
      args=("$@")
      break
    fi
    envs+=("$1")
    shift
  done
  snapshot "$c" > "$work/$c.before"
  env PORTS_DIR="$work/$c/ports" ROOTFS_DIR="$work/$c/rootfs" MIRRORS_DIR="$work/$c/mirrors" \
    PROBE_TIMEOUT=5 MIN_SERVERS=1 "${envs[@]}" bash "$GEN" "${args[@]}" > "$work/$c.out" 2>&1 || rc=$?
  printf '%s\n' "$rc" > "$work/$c.rc"
}

snapshot() {
  cat "$work/$1"/rootfs/*/etc/pacman.d/mirrorlist*
}

servers() {
  awk '/^Server/ { sub(/^[^=]*=[[:space:]]*/, ""); print }' "$1"
}

# unchanged CASE DESC RC -> exit RC, and each list of the tree as it was
unchanged() {
  local c="$1" desc="$2" want="$3" rc
  rc="$(cat "$work/$c.rc")"
  if [ "$rc" -eq "$want" ] && [ "$(snapshot "$c")" = "$(cat "$work/$c.before")" ]; then
    ok "$desc"
  else
    fail "$desc" "exit $rc (want $want), or a list changed" \
      "it said: $(tr '\n' '|' < "$work/$c.out")" "reproduce: $REPRO"
  fi
}

live A D P1 P3 G H

#---------------------------------------------------------------------------#
# Both lists written, anchors first
#---------------------------------------------------------------------------#
tree ok
anchors ok fake.anchors A B
anchors ok fake.any-anchors C D
printf 'Server = %s\nServer = %s\nServer = %s\n' "$(server P1)" "$(server P2)" "$(server P3)" > "$work/ok/mirrors/fake.pool"
gen ok
rc="$(cat "$work/ok.rc")"
main="$(servers "$work/ok/rootfs/fake/etc/pacman.d/mirrorlist")"
any="$(servers "$work/ok/rootfs/fake/etc/pacman.d/mirrorlist-any")"
want_head="$(server A)
$(server B)"
ranked="$(awk 'NR > 2' <<< "$main" | LC_ALL=C sort)"
want_ranked="$(printf '%s\n%s\n' "$(server P1)" "$(server P3)" | LC_ALL=C sort)"
if [ "$rc" -eq 0 ] && [ "$(awk 'NR <= 2' <<< "$main")" = "$want_head" ] && [ "$ranked" = "$want_ranked" ]; then
  ok "mirrorlist has both anchors in file order, one of them dead, then the candidates that answer"
else
  fail "mirrorlist has both anchors in file order, one of them dead, then the candidates that answer" \
    "exit $rc, servers: $(tr '\n' ' ' <<< "$main")" "it said: $(tr '\n' '|' < "$work/ok.out")" "reproduce: $REPRO"
fi
if [ "$rc" -eq 0 ] && [ "$any" = "$(server C)
$(server D)" ]; then
  ok "mirrorlist-any has its anchors in file order, and one dead anchor does not stop it"
else
  fail "mirrorlist-any has its anchors in file order, and one dead anchor does not stop it" \
    "exit $rc, servers: $(tr '\n' ' ' <<< "$any")" "it said: $(tr '\n' '|' < "$work/ok.out")" "reproduce: $REPRO"
fi
dates="$(cat "$work/ok/rootfs/fake/etc/pacman.d/mirrorlist" "$work/ok/rootfs/fake/etc/pacman.d/mirrorlist-any" |
  awk 'match($0, /[0-9]{4}-[0-9]{2}-[0-9]{2}/) { print substr($0, RSTART, RLENGTH) }' | awk '!s[$0]++')"
if [ "$dates" = "$TODAY" ]; then
  ok "the header of each list gives the date it was generated"
else
  fail "the header of each list gives the date it was generated" "dates: $(tr '\n' ' ' <<< "$dates"), today: $TODAY" "reproduce: $REPRO"
fi

#---------------------------------------------------------------------------#
# A refusal leaves both lists
#---------------------------------------------------------------------------#
tree anydead
anchors anydead fake.anchors A
anchors anydead fake.any-anchors C E
printf 'Server = %s\n' "$(server P1)" > "$work/anydead/mirrors/fake.pool"
gen anydead
unchanged anydead "each any-anchor dead: exit 3, and mirrorlist stays too, although its anchors answer" 3

tree maindead
anchors maindead fake.anchors B F
anchors maindead fake.any-anchors D
gen maindead
unchanged maindead "each main anchor dead: exit 3, and both lists stay" 3

#---------------------------------------------------------------------------#
# Pools
#---------------------------------------------------------------------------#
tree nopool
anchors nopool fake.anchors A G
anchors nopool fake.any-anchors D
gen nopool
rc="$(cat "$work/nopool.rc")"
got="$(servers "$work/nopool/rootfs/fake/etc/pacman.d/mirrorlist")"
if [ "$rc" -eq 0 ] && [ "$got" = "$(server A)
$(server G)" ]; then
  ok "with no pool file, mirrorlist is the anchors"
else
  fail "with no pool file, mirrorlist is the anchors" "exit $rc, servers: $(tr '\n' ' ' <<< "$got")" \
    "it said: $(tr '\n' '|' < "$work/nopool.out")" "reproduce: $REPRO"
fi

tree sources
anchors sources fake.anchors A
anchors sources fake.any-anchors D
printf '## Arch mirrorlist\n#Server = %s\n#Server = %s\n' "$(server P1)" "$(server P2)" > "$work/ml.txt"
printf 'source = mirrorlist %s\nsource = mirrorlist %s\n' "$(file_url "$work/no-such-list.txt")" "$(file_url "$work/ml.txt")" \
  > "$work/sources/mirrors/fake.pool"
gen sources
rc="$(cat "$work/sources.rc")"
got="$(servers "$work/sources/rootfs/fake/etc/pacman.d/mirrorlist")"
if [ "$rc" -eq 0 ] && [ "$got" = "$(server A)
$(server P1)" ]; then
  ok "the second source is used when the first does not answer, and a commented Server line is a candidate"
else
  fail "the second source is used when the first does not answer, and a commented Server line is a candidate" \
    "exit $rc, servers: $(tr '\n' ' ' <<< "$got")" "it said: $(tr '\n' '|' < "$work/sources.out")" "reproduce: $REPRO"
fi

# status-json: the fields of each entry decide, and the URL gets $repo/os/$arch
sj="$work/sj"
for s in S1 S2 S3 S4 S5 S6 S7; do
  mkdir -p "$sj/$s/base/os/powerpc64le"
  printf 'db\n' > "$sj/$s/base/os/powerpc64le/base.db"
done
jq -n --arg b "$(file_url "$sj")" '{ urls: [
    { url: ($b + "/S1/"), protocol: "https", active: true,  completion_pct: 1,   delay: 100,    score: 3 },
    { url: ($b + "/S2/"), protocol: "http",  active: true,  completion_pct: 1,   delay: 100,    score: 1 },
    { url: ($b + "/S3/"), protocol: "https", active: false, completion_pct: 1,   delay: 100,    score: 1 },
    { url: ($b + "/S4/"), protocol: "https", active: true,  completion_pct: 1,   delay: 999999, score: 1 },
    { url: ($b + "/S5/"), protocol: "https", active: true,  completion_pct: 0.5, delay: 100,    score: 1 },
    { url: ($b + "/S6/"), protocol: "https", active: true,  completion_pct: 1,   delay: 100,    score: null },
    { url: ($b + "/S7"),  protocol: "https", active: true,  completion_pct: 1,   delay: 100,    score: 2 } ] }' \
  > "$work/status.json"
tree statusjson
anchors statusjson fake.anchors A
anchors statusjson fake.any-anchors D
printf 'source = status-json %s\n' "$(file_url "$work/status.json")" > "$work/statusjson/mirrors/fake.pool"
gen statusjson
rc="$(cat "$work/statusjson.rc")"
got="$(servers "$work/statusjson/rootfs/fake/etc/pacman.d/mirrorlist" | awk 'NR > 1' | LC_ALL=C sort)"
want="$(printf '%s/S1/$repo/os/$arch\n%s/S7/$repo/os/$arch\n' "$(file_url "$sj")" "$(file_url "$sj")" | LC_ALL=C sort)"
if [ "$rc" -eq 0 ] && [ "$got" = "$want" ]; then
  ok "status-json gives only the https, active, complete, recent mirrors with a score"
else
  fail "status-json gives only the https, active, complete, recent mirrors with a score" \
    "exit $rc, ranked: $(tr '\n' ' ' <<< "$got")" "want: $(tr '\n' ' ' <<< "$want")" \
    "it said: $(tr '\n' '|' < "$work/statusjson.out")" "reproduce: $REPRO"
fi

# mirrorlist-package: a database names the package, and the package has the list
mp="$work/mp"
mkdir -p "$mp/db/pacman-mirrorlist-20260101-1" "$mp/pkg/etc/pacman.d"
printf '%%FILENAME%%\npacman-mirrorlist-20260101-1-any.pkg.tar.gz\n\n%%NAME%%\npacman-mirrorlist\n' \
  > "$mp/db/pacman-mirrorlist-20260101-1/desc"
tar -czf "$mp/core.db" -C "$mp/db" pacman-mirrorlist-20260101-1
printf '## Worldwide\n#Server = %s\n#Server = %s\n' "$(server P2)" "$(server P3)" > "$mp/pkg/etc/pacman.d/mirrorlist"
tar -czf "$mp/pacman-mirrorlist-20260101-1-any.pkg.tar.gz" -C "$mp/pkg" etc
tree package
anchors package fake.anchors A
anchors package fake.any-anchors D
printf 'source = status-json %s\nsource = mirrorlist-package %s pacman-mirrorlist etc/pacman.d/mirrorlist\n' \
  "$(file_url "$work/no-such-status.json")" "$(file_url "$mp/core.db")" > "$work/package/mirrors/fake.pool"
gen package
rc="$(cat "$work/package.rc")"
got="$(servers "$work/package/rootfs/fake/etc/pacman.d/mirrorlist")"
if [ "$rc" -eq 0 ] && [ "$got" = "$(server A)
$(server P3)" ]; then
  ok "mirrorlist-package reads the list in the package that the database names, after a source that does not answer"
else
  fail "mirrorlist-package reads the list in the package that the database names, after a source that does not answer" \
    "exit $rc, servers: $(tr '\n' ' ' <<< "$got")" "it said: $(tr '\n' '|' < "$work/package.out")" "reproduce: $REPRO"
fi

tree nosource
anchors nosource fake.anchors A G
anchors nosource fake.any-anchors D
printf 'source = mirrorlist %s\n' "$(file_url "$work/no-such-list.txt")" > "$work/nosource/mirrors/fake.pool"
gen nosource
unchanged nosource "no pool source answers: exit 3, and both lists stay" 3

tree shrink
anchors shrink fake.anchors A
anchors shrink fake.any-anchors D
printf 'Server = %s\n' "$(server P1)" > "$work/shrink/mirrors/fake.pool"
for s in R1 R2 R3 R4 R5 R6; do
  printf 'Server = %s\n' "$(server "$s")"
done > "$work/shrink/rootfs/fake/etc/pacman.d/mirrorlist"
gen shrink
unchanged shrink "6 ranked servers in the tree and 1 that answers now: exit 3, and both lists stay" 3

tree budget
anchors budget fake.anchors A
anchors budget fake.any-anchors D
gen budget MIRRORLIST_BUDGET=0
unchanged budget "a budget of 0 seconds: exit 3, and both lists stay" 3

tree floor
anchors floor fake.anchors A G
anchors floor fake.any-anchors D
gen floor MIN_SERVERS=2
unchanged floor "a list with fewer servers than MIN_SERVERS: exit 3, and both lists stay" 3

#---------------------------------------------------------------------------#
# Input errors
#---------------------------------------------------------------------------#
tree badpool
anchors badpool fake.anchors A
anchors badpool fake.any-anchors D
printf 'https://bare.invalid/$repo\n' > "$work/badpool/mirrors/fake.pool"
gen badpool
unchanged badpool "a pool line that is not Server or source: exit 1" 1

tree ocianchor
printf 'Server = oci://ghcr.io/x/$arch/$repo\nServer = %s\n' "$(server A)" > "$work/ocianchor/mirrors/fake.anchors"
anchors ocianchor fake.any-anchors D
gen ocianchor
unchanged ocianchor "an oci:// anchor: exit 1" 1

tree noport
gen noport -- nosuch
unchanged noport "an architecture with no ports/<arch>.conf: exit 1" 1

#---------------------------------------------------------------------------#
# all: one port written, one left as it was
#---------------------------------------------------------------------------#
tree all fake
tree all fake2
anchors all fake.anchors A
anchors all fake.any-anchors D
anchors all fake2.anchors B
anchors all fake2.any-anchors D
cp "$work/all/rootfs/fake2/etc/pacman.d/mirrorlist" "$work/all.fake2.before"
gen all -- all
rc="$(cat "$work/all.rc")"
got="$(servers "$work/all/rootfs/fake/etc/pacman.d/mirrorlist")"
if [ "$rc" -eq 3 ] && [ "$got" = "$(server A)" ] &&
  [ "$(cat "$work/all/rootfs/fake2/etc/pacman.d/mirrorlist")" = "$(cat "$work/all.fake2.before")" ]; then
  ok "all writes the port that answers, leaves the other as it was, and exits 3"
else
  fail "all writes the port that answers, leaves the other as it was, and exits 3" \
    "exit $rc, fake: $(tr '\n' ' ' <<< "$got")" "it said: $(tr '\n' '|' < "$work/all.out")" "reproduce: $REPRO"
fi

summary
