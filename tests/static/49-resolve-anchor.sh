#!/usr/bin/env bash
#
# scripts/resolve-anchor reads the lists the way the build stage reads them,
# and clears a port only when each of its repositories can be read.
#
# The fixture port has [base] (mirrorlist) and [base-any] (mirrorlist-any).
# Cases:
#   - the version comes from the first server of the primary list
#   - SKIP_SERVERS pairs apply to their own list only
#   - a malformed pair, or a pair for a list the port does not have: exit 1
#   - a server whose database has no pacman is passed
#   - [base-any] with no readable server: exit 1, and no version on stdout
#   - --each: one line for each server that is not plain http, in list order,
#     "-" for a server that does not answer or that SKIP_SERVERS names
#   - TRANSPORT=oci reads the oci:// server first
#
# $arch and $repo are variables of pacman and stay literal in this file.
# shellcheck disable=SC2016
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

RESOLVE="$REPO_ROOT/scripts/resolve-anchor"
REPRO="bash tests/static/49-resolve-anchor.sh (the fixtures are in a temporary directory)"

if ! need_tool tar gzip curl; then
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

# mkdb DIR REPO PACKAGE... -> DIR/REPO/REPO.db
mkdb() {
  local d="$1" r="$2" m
  shift 2
  m="$work/members/${d//\//_}-$r"
  mkdir -p "$d/$r" "$m"
  for p in "$@"; do
    mkdir -p "$m/$p"
    printf '%%NAME%%\n%s\n' "$p" > "$m/$p/desc"
  done
  tar -czf "$d/$r/$r.db" -C "$m" "$@"
}

mkdb "$work/srv/a" base pacman-1.0-1 bash-5-1
mkdb "$work/srv/a" base-any iana-etc-1-1
mkdb "$work/srv/b" base pacman-2.0-1
mkdb "$work/srv/b" base-any iana-etc-1-1
mkdb "$work/srv/nopacman" base bash-5-1
mkdb "$work/oci/powerpc64le" base pacman-3.0-1
mkdb "$work/oci/powerpc64le" base-any iana-etc-1-1

mkdir -p "$work/ports" "$work/rootfs/fake/etc/pacman.d"
printf 'arch = fake\npacman_arch = powerpc64le\nrepos = base base-any\n' > "$work/ports/fake.conf"
printf '[options]\nArchitecture = powerpc64le\n\n[base]\nInclude = /etc/pacman.d/mirrorlist\n\n[base-any]\nInclude = /etc/pacman.d/mirrorlist-any\n' \
  > "$work/rootfs/fake/etc/pacman.conf"

# lists MAIN_SERVERS ANY_SERVERS -> the two lists, from fixture names; a name
# that starts with http:// goes in as it is
lists() {
  local s
  for s in $1; do
    case "$s" in
      http://*) printf 'Server = %s\n' "$s" ;;
      *) printf 'Server = %s\n' "$(server "$s")" ;;
    esac
  done > "$work/rootfs/fake/etc/pacman.d/mirrorlist"
  for s in $2; do
    printf 'Server = %s\n' "$(server "$s")"
  done > "$work/rootfs/fake/etc/pacman.d/mirrorlist-any"
}

cat > "$work/fake-oci" <<'EOF'
#!/bin/sh
case "$2" in
  oci://fake/*) p="${2#oci://fake/}" ;;
  *) exit 1 ;;
esac
[ -f "$FAKE_OCI_ROOT/$p" ] || exit 1
cp "$FAKE_OCI_ROOT/$p" "$1"
EOF

# resolve DESC WANT_RC WANT_OUT [ENV=VALUE ...] [-- ARG ...]
resolve() {
  local desc="$1" want_rc="$2" want="$3" rc=0 got
  shift 3
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
  env PORTS_DIR="$work/ports" ROOTFS_DIR="$work/rootfs" "${envs[@]}" \
    bash "$RESOLVE" "${args[@]}" > "$work/out" 2> "$work/err" || rc=$?
  got="$(tr -d '\r' < "$work/out")"
  if [ "$rc" -eq "$want_rc" ] && [ "$got" = "$want" ]; then
    ok "$desc"
  else
    fail "$desc" \
      "want: '$(tr '\n' '|' <<< "$want")', exit $want_rc" \
      "got:  '$(tr '\n' '|' <<< "$got")', exit $rc" \
      "it said: $(tr -d '\r' < "$work/err" | tr '\n' '|')" \
      "reproduce: $REPRO"
  fi
}

lists "a b" "a b"
resolve "the version comes from the first server of the primary list" 0 "1.0-1"
resolve "a SKIP_SERVERS pair for mirrorlist passes its server" 0 "2.0-1" \
  "SKIP_SERVERS=mirrorlist=$(server a)"
resolve "a SKIP_SERVERS pair for mirrorlist-any does not change mirrorlist" 0 "1.0-1" \
  "SKIP_SERVERS=mirrorlist-any=$(server a)"
resolve "a SKIP_SERVERS value that is not LIST=SERVER is refused" 1 "" \
  "SKIP_SERVERS=$(server a)"
resolve "a SKIP_SERVERS pair for a list the port does not have is refused" 1 "" \
  "SKIP_SERVERS=mirrorlist-nosuch=$(server a)"

lists "nopacman b" "a"
resolve "a database with no pacman is passed, and the next server gives the version" 0 "2.0-1"

lists "a" "dead"
resolve "[base-any] with no readable server stops the port, with no version on stdout" 1 ""
if grep -qF -e "[base-any]" "$work/err"; then
  ok "the refusal names [base-any]"
else
  fail "the refusal names [base-any]" "it said: $(tr '\n' '|' < "$work/err")" "reproduce: $REPRO"
fi

lists "a" "a"
resolve "SKIP_SERVERS that leaves [base-any] with no server stops the port" 1 "" \
  "SKIP_SERVERS=mirrorlist-any=$(server a)"

lists "a http://127.0.0.1:9/x/\$repo dead b" "a"
resolve "--each gives one line for each server that is not plain http, in list order" 0 \
  "$(server a) 1.0-1
$(server dead) -
$(server b) 2.0-1" -- --each fake
resolve "--each gives - for a server that SKIP_SERVERS names" 0 \
  "$(server a) 1.0-1
$(server dead) -
$(server b) -" "SKIP_SERVERS=mirrorlist=$(server b)" -- --each fake

lists "a" "a"
resolve "TRANSPORT=oci reads the oci:// server first" 0 "3.0-1" \
  TRANSPORT=oci 'GHCR_OCI_SERVER=oci://fake/$arch/$repo' "PACMAN_OCI=$work/fake-oci" "FAKE_OCI_ROOT=$work/oci"
resolve "TRANSPORT=oci with the oci:// server in SKIP_SERVERS reads the next server" 0 "1.0-1" \
  TRANSPORT=oci 'GHCR_OCI_SERVER=oci://fake/$arch/$repo' "PACMAN_OCI=$work/fake-oci" "FAKE_OCI_ROOT=$work/oci" \
  'SKIP_SERVERS=mirrorlist=oci://fake/$arch/$repo'

summary
