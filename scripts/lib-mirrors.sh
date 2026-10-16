# shellcheck shell=bash
# shellcheck disable=SC2034 # the callers read the globals this file sets
#
# Functions for the scripts that read the mirror lists of a port:
# gen-mirrorlist, check-mirror-lag, resolve-anchor and pick-transport.
# Sourced after lib.sh, never executed.
#
#   PROG=name
#   . "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
#   . "$(dirname "${BASH_SOURCE[0]}")/lib-mirrors.sh"
#
# Terms:
#   ARCH   the docker architecture name, the name of ports/<ARCH>.conf
#   LIST   the file name of a mirror list in /etc/pacman.d, for example
#          mirrorlist or mirrorlist-any
#   SERVER the value of a Server line, with $arch and $repo unexpanded
#
# Environment (a test can set each one):
#   ROOTFS_DIR      rootfs/ of the tree, default <repo>/rootfs
#   MIRRORS_DIR     mirrors/ of the tree, default <repo>/mirrors
#   PORTS_DIR       ports/ of the tree, read by scripts/ports
#   PACMAN_OCI      the oci:// client, default
#                   <repo>/bootstrap/any/usr/local/bin/pacman-oci
#   TRANSPORT       worker (default) or oci. With oci, GHCR_OCI_SERVER is the
#                   first server of every list, as use-transport makes it in
#                   the build stage.
#   SKIP_SERVERS    LIST=SERVER pairs, separated by spaces: the servers the
#                   build stage does not read
#   GHCR_WORKER_SERVER, GHCR_OCI_SERVER   the two paths to the GHCR mirror
#   GHCR_MATCH      an extended regular expression; a SERVER that matches it
#                   is the GHCR mirror
#   FETCH_MAX_TIME  seconds for one database transfer, default 120
#
# ⛔ The pacman.conf of the port is the authority for which repository reads
# which list. ports/<ARCH>.conf must name the same repositories in the same
# order, and pacman_arch must be the Architecture of the pacman.conf.

: "${PROG:=lib-mirrors}"

MIRRORS_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS_DIR="${ROOTFS_DIR:-$MIRRORS_REPO/rootfs}"
MIRRORS_DIR="${MIRRORS_DIR:-$MIRRORS_REPO/mirrors}"
PORTS_CMD="$MIRRORS_REPO/scripts/ports"
PACMAN_OCI="${PACMAN_OCI:-$MIRRORS_REPO/bootstrap/any/usr/local/bin/pacman-oci}"
FETCH_MAX_TIME="${FETCH_MAX_TIME:-120}"
TRANSPORT="${TRANSPORT:-worker}"
SKIP_SERVERS="${SKIP_SERVERS:-}"
GHCR_WORKER_SERVER="${GHCR_WORKER_SERVER:-https://ghcr.mirror.archlinux.pkgforge.dev/\$arch/\$repo}"
GHCR_OCI_SERVER="${GHCR_OCI_SERVER:-oci://ghcr.io/pkgforge-dev/mirror-archlinux/\$arch/\$repo}"
GHCR_MATCH="${GHCR_MATCH:-^(https://ghcr\.mirror\.archlinux\.pkgforge\.dev/|oci://ghcr\.io/pkgforge-dev/mirror-archlinux/)}"

case "$TRANSPORT" in
  worker | oci) ;;
  *) die "TRANSPORT is '$TRANSPORT'. Use worker or oci." ;;
esac
case "$FETCH_MAX_TIME" in
  '' | *[!0-9]*) die "FETCH_MAX_TIME is '$FETCH_MAX_TIME'. Use a whole number of seconds." ;;
esac

#---------------------------------------------------------------------------#
# Text
#---------------------------------------------------------------------------#

# first_line TEXT -> the first line of TEXT that is not blank
first_line() {
  awk 'NF { print; exit }' <<< "$1"
}

#---------------------------------------------------------------------------#
# The port
#---------------------------------------------------------------------------#

# port_get ARCH KEY -> one value from ports/<ARCH>.conf. scripts/ports stops
# the caller with a message when ARCH or KEY is unknown.
port_get() {
  bash "$PORTS_CMD" get "$1" "$2"
}

# port_list -> every ARCH, one per line
port_list() {
  bash "$PORTS_CMD" list
}

# port_check ARCH: stops the caller when ARCH is not a port
port_check() {
  case "$1" in
    '' | *[!a-z0-9]*) die "'$1' is not an architecture name" "known: $(port_list | tr '\n' ' ')" ;;
  esac
  port_get "$1" arch > /dev/null
}

# port_conf ARCH -> the path of the pacman.conf of the port
port_conf() {
  printf '%s\n' "$ROOTFS_DIR/$1/etc/pacman.conf"
}

# list_file ARCH LIST -> the path of the list in the tree
list_file() {
  printf '%s\n' "$ROOTFS_DIR/$1/etc/pacman.d/$2"
}

# anchors_file ARCH LIST -> mirrors/<ARCH>.anchors for mirrorlist, and
# mirrors/<ARCH>.<X>-anchors for mirrorlist-<X>
anchors_file() {
  case "$2" in
    mirrorlist) printf '%s\n' "$MIRRORS_DIR/$1.anchors" ;;
    mirrorlist-?*) printf '%s\n' "$MIRRORS_DIR/$1.${2#mirrorlist-}-anchors" ;;
    *) die "the list $2 of $1 has no anchors file name: a list is mirrorlist or mirrorlist-<name>" ;;
  esac
}

# conf_arch CONF -> the value of the Architecture line
conf_arch() {
  awk -F= '/^[[:space:]]*Architecture[[:space:]]*=/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "$1"
}

# port_lists ARCH -> one line per list: "LIST REPO [REPO ...]", in the order of
# pacman.conf. Stops the caller when pacman.conf and ports/<ARCH>.conf differ.
port_lists() {
  local arch="$1" conf pacman_arch got repos rows name inc ninc nsrv list order="" sections=""
  local -A repos_of=()
  conf="$(port_conf "$arch")"
  [ -f "$conf" ] || die "no pacman.conf for $arch" "reproduce: ls $conf"
  pacman_arch="$(port_get "$arch" pacman_arch)"
  got="$(conf_arch "$conf")"
  [ "$got" = "$pacman_arch" ] || die "$conf sets Architecture = ${got:-nothing}, and ports/$arch.conf sets pacman_arch = $pacman_arch" \
    "reproduce: grep -n Architecture $conf"
  repos="$(port_get "$arch" repos)"

  # One row per enabled section other than [options]:
  # NAME INCLUDE INCLUDE_COUNT SERVER_COUNT
  rows="$(awk '
    function flush() {
      if (name != "" && name != "options") printf "%s %s %d %d\n", name, (inc == "" ? "-" : inc), ninc, nsrv
    }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*\[/ {
      flush()
      name = $0
      sub(/^[[:space:]]*\[/, "", name)
      sub(/\].*$/, "", name)
      inc = ""; ninc = 0; nsrv = 0
      next
    }
    /^[[:space:]]*Include[[:space:]]*=/ {
      v = $0
      sub(/^[^=]*=[[:space:]]*/, "", v)
      sub(/[[:space:]]+$/, "", v)
      inc = v
      ninc++
      next
    }
    /^[[:space:]]*Server[[:space:]]*=/ { nsrv++; next }
    END { flush() }' "$conf")"

  while read -r name inc ninc nsrv; do
    [ -n "$name" ] || continue
    sections="${sections:+$sections }$name"
    if [ "$ninc" -ne 1 ] || [ "$nsrv" -ne 0 ]; then
      die "[$name] in $conf has $ninc Include and $nsrv Server lines" \
        "each repository section reads one list through one Include line" \
        "reproduce: grep -n -A3 '^\[$name\]' $conf"
    fi
    case "$inc" in
      /etc/pacman.d/*/* | /etc/pacman.d/) die "[$name] in $conf includes $inc, which is not a file in /etc/pacman.d" ;;
      /etc/pacman.d/*) list="${inc#/etc/pacman.d/}" ;;
      *) die "[$name] in $conf includes $inc, which is not a file in /etc/pacman.d" ;;
    esac
    [ -f "$(list_file "$arch" "$list")" ] || die "[$name] in $conf includes $inc, and $(list_file "$arch" "$list") is missing" \
      "reproduce: ls $ROOTFS_DIR/$arch/etc/pacman.d"
    if [ -z "${repos_of[$list]+set}" ]; then
      order="${order:+$order }$list"
      repos_of[$list]="$name"
    else
      repos_of[$list]="${repos_of[$list]} $name"
    fi
  done <<< "$rows"

  [ "$sections" = "$repos" ] || die "the repository sections of $conf are '$sections', and ports/$arch.conf sets repos = $repos" \
    "both name the enabled repositories, in the same order" \
    "reproduce: grep -n '^\[' $conf; scripts/ports get $arch repos"

  for list in $order; do
    printf '%s %s\n' "$list" "${repos_of[$list]}"
  done
}

#---------------------------------------------------------------------------#
# Servers
#---------------------------------------------------------------------------#

# list_servers FILE -> every SERVER of FILE, in file order
list_servers() {
  awk '/^[[:space:]]*Server[[:space:]]*=/ { sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); print }' "$1"
}

# server_url SERVER REPO PACMAN_ARCH -> SERVER with $repo and $arch expanded
server_url() {
  local u="${1//\$repo/$2}"
  u="${u//\$arch/$3}"
  printf '%s\n' "$u"
}

# is_ghcr SERVER -> 0 when SERVER is a path to the GHCR mirror
is_ghcr() {
  [[ "$1" =~ $GHCR_MATCH ]]
}

# skip_check LIST...: stops the caller when a SKIP_SERVERS pair is not
# LIST=SERVER for one of LIST...
skip_check() {
  local pair l x found
  local -a pairs=()
  read -r -a pairs <<< "$SKIP_SERVERS"
  for pair in "${pairs[@]}"; do
    case "$pair" in
      ?*=?*) ;;
      *) die "SKIP_SERVERS holds '$pair', which is not LIST=SERVER" "SKIP_SERVERS: $SKIP_SERVERS" ;;
    esac
    l="${pair%%=*}"
    found=0
    for x in "$@"; do
      if [ "$x" = "$l" ]; then
        found=1
      fi
    done
    if [ "$found" -ne 1 ]; then
      die "SKIP_SERVERS names the list $l, and the port has no such list" "lists of the port: $*" "SKIP_SERVERS: $SKIP_SERVERS"
    fi
  done
}

# skip_of LIST -> every SERVER that SKIP_SERVERS names for LIST
skip_of() {
  local pair
  local -a pairs=()
  read -r -a pairs <<< "$SKIP_SERVERS"
  for pair in "${pairs[@]}"; do
    if [ "${pair%%=*}" = "$1" ]; then
      printf '%s\n' "${pair#*=}"
    fi
  done
}

# servers_of ARCH LIST MODE: puts the servers of LIST into the array SERVERS.
# MODE judge: in the order the build stage gets them, TRANSPORT applied.
# MODE build: the same, less the servers SKIP_SERVERS names for LIST.
SERVERS=()
servers_of() {
  local arch="$1" list="$2" mode="$3" s skips
  SERVERS=()
  if [ "$TRANSPORT" = oci ]; then
    SERVERS+=("$GHCR_OCI_SERVER")
  fi
  skips=""
  if [ "$mode" = build ]; then
    skips="$(skip_of "$list")"
  fi
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    if [ "$TRANSPORT" = oci ] && [ "$s" = "$GHCR_OCI_SERVER" ]; then
      continue
    fi
    SERVERS+=("$s")
  done < <(list_servers "$(list_file "$arch" "$list")")
  if [ -n "$skips" ]; then
    local kept=()
    for s in "${SERVERS[@]}"; do
      if grep -qxF -e "$s" <<< "$skips"; then
        note "$list: the build does not read $s (SKIP_SERVERS)"
        continue
      fi
      kept+=("$s")
    done
    SERVERS=("${kept[@]}")
  fi
}

#---------------------------------------------------------------------------#
# Databases
#---------------------------------------------------------------------------#

# fetch_db URL OUT -> 0 when the file at URL is in OUT. On 1, FETCH_WHY holds
# the reason. An oci:// URL goes to pacman-oci, every other URL to curl.
FETCH_WHY=""
fetch_db() {
  local url="$1" out="$2" rc=0 said=""
  FETCH_WHY=""
  rm -f "$out"
  case "$url" in
    oci://* | oci+http://*)
      [ -f "$PACMAN_OCI" ] || die "the oci:// client is missing at $PACMAN_OCI" "reproduce: ls -l $PACMAN_OCI"
      said="$(timeout -k 5 "$FETCH_MAX_TIME" sh "$PACMAN_OCI" "$out" "$url" 2>&1)" || rc=$?
      ;;
    *)
      # -f: an answer of 403 or 404 is a failure, not a body.
      said="$(timeout -k 5 "$((2 * FETCH_MAX_TIME + 10))" curl -sSfL -A "$HTTP_UA" \
        --connect-timeout 15 --max-time "$FETCH_MAX_TIME" --retry 1 --retry-delay 2 \
        -o "$out" "$url" 2>&1)" || rc=$?
      ;;
  esac
  if [ "$rc" -ne 0 ]; then
    FETCH_WHY="$(first_line "$said")"
    FETCH_WHY="${FETCH_WHY:-no error text}, exit $rc"
    [ "$rc" -ne 124 ] || FETCH_WHY="no answer in the time limit, exit 124"
    return 1
  fi
  if [ ! -f "$out" ]; then
    FETCH_WHY="the transfer ended with no file"
    return 1
  fi
}

# db_open FILE -> 0 when FILE is a gzip or Zstandard tar archive with at least
# one member. Then DB_LISTING holds `tar -tv` with UTC times, and DB_FLAG the
# tar option for the compression. On 1, DB_WHY holds the reason.
#
# Arch Linux and its ports serve gzip databases. ArchPOWER serves Zstandard.
# The file name is <repo>.db in both cases, so the first bytes decide.
DB_LISTING=""
DB_WHY=""
DB_FLAG=""
db_open() {
  local f="$1" magic flag rc=0 out
  DB_LISTING=""
  DB_WHY=""
  DB_FLAG=""
  if [ ! -s "$f" ]; then
    DB_WHY="the body is empty"
    return 1
  fi
  magic="$(od -An -tx1 -N4 "$f" | tr -d ' \n')"
  case "$magic" in
    1f8b*) flag=-z ;;
    28b52ffd)
      if ! command -v zstd > /dev/null; then
        DB_WHY="a Zstandard archive, and zstd is not on PATH"
        return 1
      fi
      flag=--zstd
      ;;
    *)
      DB_WHY="not a gzip or Zstandard archive, the first bytes are ${magic:-none}"
      return 1
      ;;
  esac
  out="$(tar --utc --full-time "$flag" -tvf "$f" 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ]; then
    DB_WHY="tar cannot read it: $(first_line "$out")"
    return 1
  fi
  if [ -z "$(awk 'NF >= 6 { print; exit }' <<< "$out")" ]; then
    DB_WHY="an archive with no member"
    return 1
  fi
  DB_LISTING="$out"
  DB_FLAG="$flag"
}

# db_version PACKAGE -> the version of PACKAGE in DB_LISTING, or nothing
db_version() {
  awk -v p="$1-" '
    NF >= 6 {
      n = $6
      if (index(n, p) != 1) next
      v = substr(n, length(p) + 1)
      sub(/\/.*$/, "", v)
      if (v ~ /^[0-9]/) { print v; exit }
    }' <<< "$DB_LISTING"
}

# db_newest -> the time of the newest member in DB_LISTING, "YYYY-MM-DD HH:MM:SS" UTC
db_newest() {
  awk 'NF >= 6 && $4 " " $5 > m { m = $4 " " $5 } END { print m }' <<< "$DB_LISTING"
}
