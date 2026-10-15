#!/usr/bin/env bash
#
# A first server that is behind upstream is not what the build reads.
#
# The first server of five ports is the GHCR mirror, which follows upstream on
# a schedule of its own. pacman reads a list from the top, so a mirror that
# stopped following upstream would build every image from an old package set
# with nothing failing. Three parts stop that, and each is run here:
#
#   scripts/check-mirror-lag   compares the first server with the next one
#   drop-server                removes it from the build stage's own list
#   scripts/resolve-anchor     passes over it, so the anchor matches the build
#
# and the wiring between them in the Dockerfile and build-deploy.yml is read.
#
# The mirrors are local files, as in 67-mangled-responses.sh. A database is a
# tar archive whose members keep the time each package went in, so a fixture
# sets that time with tar --mtime.
#
# $repo is pacman's own variable and is written literally all through this
# file, so the single quotes around it are deliberate.
# shellcheck disable=SC2016
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

# 2026-01-01T00:00:00Z. Every fixture time is this plus an offset, so no case
# depends on the clock.
T0=1767225600
DAY=86400

work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

# file_url PATH -> a file:// URL curl can open on this platform
#
# ⚠ curl on Windows is a native binary and does not read an MSYS path, so the
# path is converted. cygpath -m rather than -w: a URL wants forward slashes.
file_url() {
  case "$(uname -o 2>/dev/null)" in
    Msys | Cygwin) printf 'file:///%s\n' "$(cygpath -m "$1")" ;;
    *) printf 'file://%s\n' "$1" ;;
  esac
}

# mkdb CASE SERVER REPO EPOCH PACKAGE... -> one database, every member at EPOCH
mkdb() {
  local c="$1" s="$2" r="$3" t="$4" m
  shift 4
  m="$work/members/$c-$s-$r"
  mkdir -p "$work/srv/$c/$s/$r" "$m"
  for p in "$@"; do
    mkdir -p "$m/$p"
    printf '%%NAME%%\n%s\n' "$p" > "$m/$p/desc"
  done
  tar --mtime="@$t" -czf "$work/srv/$c/$s/$r/$r.db" -C "$m" "$@"
}

# mkpage CASE SERVER REPO -> a database path that answers with an error page
mkpage() {
  mkdir -p "$work/srv/$1/$2/$3"
  printf '<html><title>403 Forbidden</title></html>\n' > "$work/srv/$1/$2/$3/$3.db"
}

# server CASE SERVER -> the Server value for one fixture server
server() {
  printf '%s/%s/%s/$repo\n' "$(file_url "$work/srv")" "$1" "$2"
}

# tree CASE CONF SERVER... -> a scratch repository with one fake port
tree() {
  local c="$1" conf="$2" s
  shift 2
  mkdir -p "$work/$c/rootfs/fake/etc/pacman.d" "$work/$c/scripts"
  cp "$REPO_ROOT/scripts/check-mirror-lag" "$REPO_ROOT/scripts/resolve-anchor" "$work/$c/scripts/"
  printf '%b' "$conf" > "$work/$c/rootfs/fake/etc/pacman.conf"
  for s in "$@"; do
    printf 'Server = %s\n' "$(server "$c" "$s")"
  done > "$work/$c/rootfs/fake/etc/pacman.d/mirrorlist"
}

CORE='[options]\nArchitecture = x86_64\n\n[core]\nInclude = /etc/pacman.d/mirrorlist\n'
CORE_EXTRA='[options]\nArchitecture = x86_64\n\n[core]\nInclude = /etc/pacman.d/mirrorlist\n\n[extra]\nInclude = /etc/pacman.d/mirrorlist\n'
TWO_LISTS='[options]\nArchitecture = powerpc64le\n\n[base]\nInclude = /etc/pacman.d/mirrorlist\n\n[base-any]\nInclude = /etc/pacman.d/mirrorlist-any\n'

# lag CASE [ENV=VALUE] -> runs check-mirror-lag on the fake port of CASE.
# Leaves the verdict in $work/CASE.out, the reasons in .err, the status in .rc.
lag() {
  local c="$1" rc=0
  shift
  (cd "$work/$c" && env "$@" bash scripts/check-mirror-lag fake) > "$work/$c.out" 2> "$work/$c.err" || rc=$?
  printf '%s\n' "$rc" > "$work/$c.rc"
}

# expect CASE DESC VERDICT -> one assertion on the verdict and the status
expect() {
  local c="$1" desc="$2" want="$3" got rc
  got="$(tr -d '\r' < "$work/$c.out")"
  rc="$(cat "$work/$c.rc")"
  if [ "$rc" -eq 0 ] && [ "$got" = "$want" ]; then
    ok "$desc"
  else
    fail "$desc" \
      "want: '$want', exit 0" \
      "got:  '$got', exit $rc" \
      "it said: $(tr -d '\r' < "$work/$c.err" | tr '\n' '|')" \
      "reproduce: bash tests/static/66-mirror-lag.sh, which keeps its fixtures under a temp dir"
  fi
}

#---------------------------------------------------------------------------#
# check-mirror-lag
#---------------------------------------------------------------------------#
mkdb same a core "$T0" pacman-1-1
mkdb same b core "$T0" pacman-1-1
tree same "$CORE" a b
lag same
expect same "a first server as current as the next one is kept" "keep"

mkdb behind a core "$T0" pacman-1-1
mkdb behind b core "$((T0 + 2 * DAY))" pacman-2-1
tree behind "$CORE" a b
lag behind
expect behind "a first server two days behind the next one is dropped" "drop $(server behind a)"
if tr -d '\r' < "$work/behind.err" | grep -q "behind by $((2 * DAY))s"; then
  ok "the reason names how far behind it is, in seconds"
else
  fail "the reason names how far behind it is, in seconds" \
    "it said: $(tr -d '\r' < "$work/behind.err" | tr '\n' '|')" \
    "reproduce: bash tests/static/66-mirror-lag.sh, which keeps its fixtures under a temp dir"
fi

mkdb near a core "$T0" pacman-1-1
mkdb near b core "$((T0 + 3600))" pacman-2-1
tree near "$CORE" a b
lag near
expect near "a first server one hour behind, inside the default 12 hours, is kept" "keep"

lag behind MIRROR_LAG_MAX="$((3 * DAY))"
expect behind "MIRROR_LAG_MAX moves the bound: two days behind is kept under three" "keep"

mkdb ahead a core "$((T0 + 3600))" pacman-2-1
mkdb ahead b core "$T0" pacman-1-1
tree ahead "$CORE" a b
lag ahead
expect ahead "a first server ahead of the next one is kept" "keep"

mkdb gone b core "$T0" pacman-1-1
tree gone "$CORE" a b
lag gone
expect gone "a first server that serves no database, where the next one does, is dropped" "drop $(server gone a)"

mkdb alone a core "$T0" pacman-1-1
mkpage alone c core
tree alone "$CORE" a b c
lag alone
expect alone "with no readable database after the first, the first stays: it is the only path" "keep"

mkdb skipbad a core "$T0" pacman-1-1
mkpage skipbad b core
mkdb skipbad c core "$((T0 + 2 * DAY))" pacman-2-1
tree skipbad "$CORE" a b c
lag skipbad
expect skipbad "an error page in second place is stepped over, and the third server is the reference" "drop $(server skipbad a)"

mkdb extra a core "$T0" pacman-1-1
mkdb extra a extra "$T0" bash-1-1
mkdb extra b core "$T0" pacman-1-1
mkdb extra b extra "$((T0 + 2 * DAY))" bash-2-1
tree extra "$CORE_EXTRA" a b
lag extra
expect extra "a first server current for core and behind for extra is dropped: the build reads both" "drop $(server extra a)"

mkdb twolists a base "$T0" pacman-1-1
mkdb twolists b base "$T0" pacman-1-1
tree twolists "$TWO_LISTS" a b
lag twolists
expect twolists "a section that includes another list is not judged against this one" "keep"
if tr -d '\r' < "$work/twolists.err" | grep -q 'base-any'; then
  fail "the base-any section, which reads mirrorlist-any, is not fetched from this list" \
    "it said: $(tr -d '\r' < "$work/twolists.err" | tr '\n' '|')" \
    "reproduce: bash tests/static/66-mirror-lag.sh, which keeps its fixtures under a temp dir"
else
  ok "the base-any section, which reads mirrorlist-any, is not fetched from this list"
fi

rc=0
(cd "$work/same" && MIRROR_LAG_MAX=12h bash scripts/check-mirror-lag fake) > /dev/null 2>&1 || rc=$?
if [ "$rc" -eq 1 ]; then
  ok "a MIRROR_LAG_MAX that is not a number of seconds is refused"
else
  fail "a MIRROR_LAG_MAX that is not a number of seconds is refused" "exit $rc, want 1" "reproduce: bash tests/static/66-mirror-lag.sh, which keeps its fixtures under a temp dir"
fi

rc=0
(cd "$work/same" && bash scripts/check-mirror-lag) > /dev/null 2>&1 || rc=$?
if [ "$rc" -eq 1 ]; then
  ok "check-mirror-lag with no architecture exits 1"
else
  fail "check-mirror-lag with no architecture exits 1" "exit $rc" "reproduce: bash tests/static/66-mirror-lag.sh, which keeps its fixtures under a temp dir"
fi

#---------------------------------------------------------------------------#
# drop-server
#---------------------------------------------------------------------------#
DROP="$REPO_ROOT/bootstrap/any/usr/local/bin/drop-server"
list="$work/drop.list"
reset_list() {
  printf '## a comment\n\nServer = https://first.invalid/$repo\nServer = https://second.invalid/$repo  \n## Ranked\nServer = https://third.invalid/$repo\n' > "$list"
}

reset_list
rc=0
bash "$DROP" "$list" 'https://first.invalid/$repo' 2> "$work/drop.err" || rc=$?
servers="$(awk '/^Server/ { sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); print }' "$list" | tr '\n' ' ')"
if [ "$rc" -eq 0 ] && [ "$servers" = 'https://second.invalid/$repo https://third.invalid/$repo ' ] &&
  grep -q '^## Ranked' "$list"; then
  ok "drop-server removes the one line and keeps the rest of the list, comments too"
else
  fail "drop-server removes the one line and keeps the rest of the list, comments too" \
    "exit $rc, servers left: $servers" "it said: $(cat "$work/drop.err")" "reproduce: bash tests/static/66-mirror-lag.sh, which keeps its fixtures under a temp dir"
fi

reset_list
rc=0
bash "$DROP" "$list" 'https://second.invalid/$repo' 2> /dev/null || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q 'second.invalid' "$list"; then
  ok "drop-server matches a line that carries trailing blanks"
else
  fail "drop-server matches a line that carries trailing blanks" "exit $rc" "reproduce: bash tests/static/66-mirror-lag.sh, which keeps its fixtures under a temp dir"
fi

for bad in 'https://absent.invalid/$repo' 'https://first.invalid'; do
  reset_list
  cp "$list" "$work/drop.before"
  rc=0
  bash "$DROP" "$list" "$bad" 2> /dev/null || rc=$?
  if [ "$rc" -ne 0 ] && [ "$(cat "$list")" = "$(cat "$work/drop.before")" ]; then
    ok "drop-server refuses $bad, which is no whole Server value, and leaves the list as it was"
  else
    fail "drop-server refuses $bad, which is no whole Server value, and leaves the list as it was" \
      "exit $rc" "the check and the build would read two different lists" "reproduce: bash tests/static/66-mirror-lag.sh, which keeps its fixtures under a temp dir"
  fi
done

printf 'Server = https://only.invalid/$repo\n' > "$list"
rc=0
bash "$DROP" "$list" 'https://only.invalid/$repo' 2> /dev/null || rc=$?
if [ "$rc" -ne 0 ] && grep -q 'only.invalid' "$list"; then
  ok "drop-server refuses to leave a list with no server"
else
  fail "drop-server refuses to leave a list with no server" "exit $rc" "reproduce: bash tests/static/66-mirror-lag.sh, which keeps its fixtures under a temp dir"
fi

#---------------------------------------------------------------------------#
# resolve-anchor reads the same list the build reads
#---------------------------------------------------------------------------#
mkdb anchor a core "$T0" pacman-1.0-1
mkdb anchor b core "$((T0 + 2 * DAY))" pacman-2.0-1
tree anchor "$CORE" a b
rc=0
got="$(cd "$work/anchor" && bash scripts/resolve-anchor fake 2> /dev/null)" || rc=$?
if [ "$rc" -eq 0 ] && [ "$got" = "1.0-1" ]; then
  ok "resolve-anchor reads the first server when nothing is passed over"
else
  fail "resolve-anchor reads the first server when nothing is passed over" "exit $rc, got '$got'" "reproduce: bash tests/static/66-mirror-lag.sh, which keeps its fixtures under a temp dir"
fi
rc=0
got="$(cd "$work/anchor" && SKIP_SERVER="$(server anchor a)" bash scripts/resolve-anchor fake 2> "$work/anchor.err")" || rc=$?
if [ "$rc" -eq 0 ] && [ "$got" = "2.0-1" ] && grep -q 'passing over' "$work/anchor.err"; then
  ok "resolve-anchor passes over SKIP_SERVER and names it"
else
  fail "resolve-anchor passes over SKIP_SERVER and names it" \
    "exit $rc, got '$got', want 2.0-1" "it said: $(tr '\n' '|' < "$work/anchor.err")" "reproduce: bash tests/static/66-mirror-lag.sh, which keeps its fixtures under a temp dir"
fi

#---------------------------------------------------------------------------#
# The wiring
#---------------------------------------------------------------------------#
DF="$REPO_ROOT/Dockerfile"
WF="$REPO_ROOT/.github/workflows/build-deploy.yml"

drop_line="$(awk '/^[[:space:]]*drop-server \/etc\/pacman\.d\/mirrorlist / { print NR; exit }' "$DF")"
arg_line="$(awk '/^ARG SKIP_SERVER/ { print NR; exit }' "$DF")"
strap_line="$(awk '/pacstrap-docker \/rootfs/ { print NR; exit }' "$DF")"
if [ -n "$drop_line" ] && [ -n "$arg_line" ] && [ -n "$strap_line" ] &&
  [ "$arg_line" -lt "$drop_line" ] && [ "$drop_line" -lt "$strap_line" ]; then
  ok "the Dockerfile takes SKIP_SERVER and drops it from the build stage's list before pacstrap"
else
  fail "the Dockerfile takes SKIP_SERVER and drops it from the build stage's list before pacstrap" \
    "ARG at line ${arg_line:-none}, drop-server at ${drop_line:-none}, pacstrap at ${strap_line:-none}" \
    "reproduce: grep -n 'SKIP_SERVER\|drop-server\|pacstrap-docker' Dockerfile"
fi

builds="$(awk '/uses: docker\/build-push-action@/ { n++ } END { print n + 0 }' "$WF")"
passed="$(awk '/SKIP_SERVER=\$\{\{ fromJSON\(needs\.resolve\.outputs\.skip_servers/ { n++ } END { print n + 0 }' "$WF")"
if [ "$builds" -gt 0 ] && [ "$passed" -eq "$builds" ]; then
  ok "every one of the $builds build steps in build-deploy.yml passes SKIP_SERVER"
else
  fail "every build step in build-deploy.yml passes SKIP_SERVER" \
    "$builds build steps, $passed pass it" \
    "a build step without it exports a bootstrap stage that read another list" \
    "reproduce: grep -n 'build-push-action\|SKIP_SERVER=' .github/workflows/build-deploy.yml"
fi

check_line="$(awk '/scripts\/check-mirror-lag "\$arch"/ { print NR; exit }' "$WF")"
resolve_line="$(awk '/SKIP_SERVER="\$skip_server" scripts\/resolve-anchor "\$arch"/ { print NR; exit }' "$WF")"
if [ -n "$check_line" ] && [ -n "$resolve_line" ] && [ "$check_line" -lt "$resolve_line" ]; then
  ok "the resolve job checks the first server, then resolves the anchor without the server it drops"
else
  fail "the resolve job checks the first server, then resolves the anchor without the server it drops" \
    "check-mirror-lag at line ${check_line:-none}, resolve-anchor with SKIP_SERVER at ${resolve_line:-none}" \
    "reproduce: grep -n 'check-mirror-lag\|resolve-anchor' .github/workflows/build-deploy.yml"
fi

summary
