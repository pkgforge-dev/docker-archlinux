#!/usr/bin/env bash
#
# scripts/check-mirror-lag drops a first server that is behind the next server
# of its list, for each list of a port. The Dockerfile applies the drops to
# the build stage only.
#
# The ports are fixture trees (PORTS_DIR, ROOTFS_DIR) with one port named
# fake. The servers are local directories, read through file:// URLs. A
# database is a tar archive whose members keep the time each package went in,
# so a fixture sets that time with tar --mtime.
#
# 46-mirror-lag-status.sh covers the record of the GHCR mirror, the reference
# when no later server answers.
#
# $repo is a variable of pacman and stays literal in this file.
# shellcheck disable=SC2016
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

LAG="$REPO_ROOT/scripts/check-mirror-lag"
REPRO="bash tests/static/66-mirror-lag.sh (the fixtures are in a temporary directory)"

# 2026-01-01T00:00:00Z. Each fixture time is this plus an offset.
T0=1767225600
DAY=86400

if ! need_tool tar gzip curl jq; then
  rc=0
  summary || rc=$?
  exit "$rc"
fi

work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

# file_url PATH -> a file:// URL for curl on this host
file_url() {
  case "$(uname -o 2>&1)" in
    Msys | Cygwin) printf 'file:///%s\n' "$(cygpath -m "$1")" ;;
    *) printf 'file://%s\n' "$1" ;;
  esac
}

# server CASE NAME -> the Server value of one fixture server
server() {
  printf '%s/%s/%s/$repo\n' "$(file_url "$work/srv")" "$1" "$2"
}

# port CASE PACMAN_ARCH REPO:LIST... -> a tree with the port fake
port() {
  local c="$1" parch="$2" spec repos=""
  shift 2
  mkdir -p "$work/$c/ports" "$work/$c/rootfs/fake/etc/pacman.d"
  {
    printf '[options]\nArchitecture = %s\n' "$parch"
    for spec in "$@"; do
      printf '\n[%s]\nInclude = /etc/pacman.d/%s\n' "${spec%%:*}" "${spec#*:}"
      repos="$repos ${spec%%:*}"
    done
  } > "$work/$c/rootfs/fake/etc/pacman.conf"
  printf 'arch = fake\npacman_arch = %s\nrepos =%s\n' "$parch" "$repos" > "$work/$c/ports/fake.conf"
}

# list CASE LIST NAME... -> the list, one Server line for each fixture server
list() {
  local c="$1" l="$2" s
  shift 2
  for s in "$@"; do
    printf 'Server = %s\n' "$(server "$c" "$s")"
  done > "$work/$c/rootfs/fake/etc/pacman.d/$l"
}

# mkdb CASE NAME REPO EPOCH PACKAGE... -> one database, each member at EPOCH
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

# mkpage CASE NAME REPO -> a database path that answers with an error page
mkpage() {
  mkdir -p "$work/srv/$1/$2/$3"
  printf '<html><title>403 Forbidden</title></html>\n' > "$work/srv/$1/$2/$3/$3.db"
}

# lag CASE [ENV=VALUE ...] -> runs the script on the port fake of CASE; the
# verdict goes to CASE.out, the reasons to CASE.err, the status to CASE.rc
lag() {
  local c="$1" rc=0
  shift
  env PORTS_DIR="$work/$c/ports" ROOTFS_DIR="$work/$c/rootfs" \
    MIRROR_STATUS_URL="file:///nonexistent/status.json" "$@" \
    bash "$LAG" fake > "$work/$c.out" 2> "$work/$c.err" || rc=$?
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
      "want: '$(tr '\n' '|' <<< "$want")', exit 0" \
      "got:  '$(tr '\n' '|' <<< "$got")', exit $rc" \
      "it said: $(tr -d '\r' < "$work/$c.err" | tr '\n' '|')" \
      "reproduce: $REPRO"
  fi
}

#---------------------------------------------------------------------------#
# One list
#---------------------------------------------------------------------------#
port same x86_64 core:mirrorlist
mkdb same a core "$T0" pacman-1-1
mkdb same b core "$T0" pacman-1-1
list same mirrorlist a b
lag same
expect same "a first server as new as the next one is kept" "keep mirrorlist"

port behind x86_64 core:mirrorlist
mkdb behind a core "$T0" pacman-1-1
mkdb behind b core "$((T0 + 2 * DAY))" pacman-2-1
list behind mirrorlist a b
lag behind
expect behind "a first server two days behind the next one is dropped" "drop mirrorlist $(server behind a)"
if grep -qF -e "$((2 * DAY))" "$work/behind.err"; then
  ok "the reason gives the lag in seconds"
else
  fail "the reason gives the lag in seconds" \
    "it said: $(tr -d '\r' < "$work/behind.err" | tr '\n' '|')" \
    "reproduce: $REPRO"
fi

port near x86_64 core:mirrorlist
mkdb near a core "$T0" pacman-1-1
mkdb near b core "$((T0 + 3600))" pacman-2-1
list near mirrorlist a b
lag near
expect near "a first server one hour behind, less than the 12 hours of the default, is kept" "keep mirrorlist"

lag behind MIRROR_LAG_MAX="$((3 * DAY))"
expect behind "MIRROR_LAG_MAX sets the limit: two days behind is kept under three days" "keep mirrorlist"

port ahead x86_64 core:mirrorlist
mkdb ahead a core "$((T0 + 3600))" pacman-2-1
mkdb ahead b core "$T0" pacman-1-1
list ahead mirrorlist a b
lag ahead
expect ahead "a first server newer than the next one is kept" "keep mirrorlist"

port gone x86_64 core:mirrorlist
mkdb gone b core "$T0" pacman-1-1
list gone mirrorlist a b
lag gone
expect gone "a first server with no database, where the next one has one, is dropped" "drop mirrorlist $(server gone a)"

port alone x86_64 core:mirrorlist
mkdb alone a core "$T0" pacman-1-1
mkpage alone c core
list alone mirrorlist a b c
lag alone
expect alone "with no readable database after the first, the first server stays" "keep mirrorlist"

port skipbad x86_64 core:mirrorlist
mkdb skipbad a core "$T0" pacman-1-1
mkpage skipbad b core
mkdb skipbad c core "$((T0 + 2 * DAY))" pacman-2-1
list skipbad mirrorlist a b c
lag skipbad
expect skipbad "an error page in second place is not the reference; the third server is" "drop mirrorlist $(server skipbad a)"

port twice x86_64 core:mirrorlist
mkdb twice a core "$T0" pacman-1-1
mkdb twice b core "$((T0 + 2 * DAY))" pacman-2-1
list twice mirrorlist a a b
lag twice
expect twice "a copy of the first server is not the reference, and the drop names the server once" "drop mirrorlist $(server twice a)"

port extra x86_64 core:mirrorlist extra:mirrorlist
mkdb extra a core "$T0" pacman-1-1
mkdb extra a extra "$T0" bash-1-1
mkdb extra b core "$T0" pacman-1-1
mkdb extra b extra "$((T0 + 2 * DAY))" bash-2-1
list extra mirrorlist a b
lag extra
expect extra "a first server new for core and behind for extra is dropped: the build reads both" "drop mirrorlist $(server extra a)"

port single x86_64 core:mirrorlist
mkdb single a core "$T0" pacman-1-1
list single mirrorlist a
lag single
expect single "a list with one server keeps it" "keep mirrorlist"

#---------------------------------------------------------------------------#
# Each list of the port, in the order of pacman.conf
#---------------------------------------------------------------------------#
port twolists powerpc64le base:mirrorlist base-any:mirrorlist-any
mkdb twolists a base "$T0" pacman-1-1
mkdb twolists b base "$T0" pacman-1-1
mkdb twolists a base-any "$T0" iana-etc-1-1
mkdb twolists b base-any "$((T0 + 2 * DAY))" iana-etc-2-1
list twolists mirrorlist a b
list twolists mirrorlist-any a b
lag twolists
expect twolists "each list gets its own line: base is kept, base-any is dropped" \
  "keep mirrorlist
drop mirrorlist-any $(server twolists a)"

#---------------------------------------------------------------------------#
# Inputs it refuses
#---------------------------------------------------------------------------#
# refused DESC CASE [ENV=VALUE ...] [-- ARG ...] -> exit 1 expected
refused() {
  local desc="$1" c="$2" rc=0
  shift 2
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
  env PORTS_DIR="$work/$c/ports" ROOTFS_DIR="$work/$c/rootfs" "${envs[@]}" \
    bash "$LAG" "${args[@]}" > "$work/refused.out" 2> "$work/refused.err" || rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$work/refused.out" ]; then
    ok "$desc"
  else
    fail "$desc" \
      "exit $rc (want 1), stdout: $(tr '\n' '|' < "$work/refused.out")" \
      "it said: $(tr '\n' '|' < "$work/refused.err")" \
      "reproduce: $REPRO"
  fi
}

refused "a MIRROR_LAG_MAX that is not a number of seconds is refused" same MIRROR_LAG_MAX=12h
refused "no architecture is refused" same --
refused "an architecture with no ports/<arch>.conf is refused" same -- nosuch

port mismatch x86_64 core:mirrorlist
mkdb mismatch a core "$T0" pacman-1-1
list mismatch mirrorlist a
printf 'arch = fake\npacman_arch = x86_64\nrepos = core extra\n' > "$work/mismatch/ports/fake.conf"
refused "a pacman.conf whose sections are not the repos of the port is refused" mismatch

#---------------------------------------------------------------------------#
# The Dockerfile: the drops apply to the build stage, before pacstrap
#---------------------------------------------------------------------------#
DF="$REPO_ROOT/Dockerfile"
# line_of ERE -> the first line of the Dockerfile that matches. ENVIRON, not
# -v: awk -v reads backslash escapes in the value.
line_of() {
  RE="$1" awk '$0 ~ ENVIRON["RE"] { print NR; exit }' "$DF"
}
etc_line="$(line_of '^COPY rootfs/.* /etc$')"
targ_line="$(line_of '^ARG TRANSPORT=worker$')"
use_line="$(line_of '^RUN use-transport "\$\{TRANSPORT\}"$')"
sarg_line="$(line_of '^ARG SKIP_SERVERS=')"
drop_line="$(line_of '^RUN drop-server --pairs /etc/pacman\.d "\$\{SKIP_SERVERS\}"$')"
strap_line="$(line_of 'pacstrap-docker /rootfs')"
order="COPY to /etc ${etc_line:-none}, ARG TRANSPORT ${targ_line:-none}, use-transport ${use_line:-none}, ARG SKIP_SERVERS ${sarg_line:-none}, drop-server ${drop_line:-none}, pacstrap ${strap_line:-none}"
if [ -n "$etc_line" ] && [ -n "$targ_line" ] && [ -n "$use_line" ] && [ -n "$sarg_line" ] &&
  [ -n "$drop_line" ] && [ -n "$strap_line" ] &&
  [ "$etc_line" -lt "$targ_line" ] && [ "$targ_line" -lt "$use_line" ] && [ "$use_line" -lt "$sarg_line" ] &&
  [ "$sarg_line" -lt "$drop_line" ] && [ "$drop_line" -lt "$strap_line" ]; then
  ok "the Dockerfile sets the transport, then drops SKIP_SERVERS from /etc/pacman.d, then runs pacstrap"
else
  fail "the Dockerfile sets the transport, then drops SKIP_SERVERS from /etc/pacman.d, then runs pacstrap" \
    "lines: $order" \
    "reproduce: grep -nE 'COPY rootfs|TRANSPORT|SKIP_SERVERS|pacstrap-docker' Dockerfile"
fi

summary
