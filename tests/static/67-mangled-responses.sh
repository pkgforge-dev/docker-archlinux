#!/usr/bin/env bash
#
# scripts/resolve-anchor names a mirror that answers with the wrong thing,
# goes to the next server, and never reads a version from it.
#
# The shapes of a wrong answer:
#   empty      a zero byte database (a 404 that became a file)
#   zstd       Zstandard magic bytes with nothing that decompresses
#   errorpage  an HTML error page as the body (a 403 from one network)
#   truncated  a gzip header that stops (an interrupted transfer)
#   missing    no file at all
# Each of them, then one good mirror, is one list of a fixture port. Then a
# real Zstandard database, from a repository named base, is read: the shape of
# ArchPOWER.
#
# ⚠ A redirect to a server that never answers is not reproducible from a file.
# 65-fetch-policy.sh checks that each transfer has a time limit.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

RESOLVE="$REPO_ROOT/scripts/resolve-anchor"
REPRO="bash tests/static/67-mangled-responses.sh, and read the stderr it prints"
ANCHOR_VERSION="9.9.9.r1.gfeedface-7"
SHAPES="empty zstd errorpage truncated missing"

if ! need_tool tar gzip curl; then
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

# port DIR PACMAN_ARCH REPO -> a tree with the port fake and one list
port() {
  mkdir -p "$1/ports" "$1/rootfs/fake/etc/pacman.d"
  printf '[options]\nArchitecture = %s\n\n[%s]\nInclude = /etc/pacman.d/mirrorlist\n' "$2" "$3" \
    > "$1/rootfs/fake/etc/pacman.conf"
  printf 'arch = fake\npacman_arch = %s\nrepos = %s\n' "$2" "$3" > "$1/ports/fake.conf"
}

#---------------------------------------------------------------------------#
# One directory for each mirror, each with a core.db of one wrong shape
#---------------------------------------------------------------------------#
mkdir -p "$work/srv"/{empty,zstd,errorpage,truncated,missing,good}
: > "$work/srv/empty/core.db"
printf '\050\265\057\375\000\130\041\000\000not-gzip\n' > "$work/srv/zstd/core.db"
printf '<html><head><title>403 Forbidden</title></head><body>Forbidden</body></html>\n' \
  > "$work/srv/errorpage/core.db"
mkdir -p "$work/whole/pacman-1.0-1"
tar -czf "$work/whole.db" -C "$work/whole" pacman-1.0-1
head -c 20 "$work/whole.db" > "$work/srv/truncated/core.db"
rm -rf "$work/srv/missing"
mkdir -p "$work/good/pacman-$ANCHOR_VERSION" "$work/good/bash-5.3.15-1"
tar -czf "$work/srv/good/core.db" -C "$work/good" "pacman-$ANCHOR_VERSION" bash-5.3.15-1

base="$(file_url "$work/srv")"
port "$work/tree" x86_64 core
{
  for shape in $SHAPES good; do
    printf 'Server = %s/%s\n' "$base" "$shape"
  done
} > "$work/tree/rootfs/fake/etc/pacman.d/mirrorlist"

rc=0
PORTS_DIR="$work/tree/ports" ROOTFS_DIR="$work/tree/rootfs" bash "$RESOLVE" fake \
  > "$work/out" 2> "$work/err" || rc=$?

if [ "$rc" -eq 0 ]; then
  ok "resolve-anchor goes past five wrong mirrors and exits 0"
else
  fail "resolve-anchor goes past five wrong mirrors and exits 0" \
    "exit $rc" \
    "it said: $(tr -d '\r' < "$work/err" | tr '\n' '|')" \
    "reproduce: $REPRO"
fi

got="$(tr -d '\r' < "$work/out")"
if [ "$got" = "$ANCHOR_VERSION" ]; then
  ok "it prints $ANCHOR_VERSION, from the good mirror"
else
  fail "it prints $ANCHOR_VERSION, from the good mirror" \
    "it printed: ${got:-nothing}" \
    "⛔ a version from a wrong database is worse than no version" \
    "reproduce: $REPRO"
fi

#---------------------------------------------------------------------------#
# Each wrong mirror is named once, with a reason. The good one is not.
#---------------------------------------------------------------------------#
for shape in $SHAPES; do
  lines="$(awk -v s="/$shape/core.db" 'index($0, s)' "$work/err")"
  n="$(awk 'NF { c++ } END { print c + 0 }' <<< "$lines")"
  reasonless="$(awk '{ l = $0; sub(/[[:space:]]+$/, "", l) } l ~ /:$/' <<< "$lines")"
  if [ "$n" -eq 1 ] && [ -z "$reasonless" ]; then
    ok "the $shape mirror is named once, with a reason"
  else
    fail "the $shape mirror is named once, with a reason" \
      "lines that name it: $n" \
      "lines that end at the colon: ${reasonless:-none}" \
      "reproduce: $REPRO"
  fi
done

complaint="$(awk -v s="/good/core.db" 'index($0, s)' "$work/err")"
if [ -z "$complaint" ]; then
  ok "no line names the good mirror as wrong"
else
  fail "no line names the good mirror as wrong" \
    "found: $complaint" \
    "reproduce: $REPRO"
fi

#---------------------------------------------------------------------------#
# ⭐ A real Zstandard database, in a repository named base, is read.
#---------------------------------------------------------------------------#
if need_tool zstd; then
  mkdir -p "$work/srv/zstdgood" "$work/zgood/pacman-$ANCHOR_VERSION"
  tar --zstd -cf "$work/srv/zstdgood/base.db" -C "$work/zgood" "pacman-$ANCHOR_VERSION"
  port "$work/tree2" powerpc64le base
  printf 'Server = %s/zstdgood\n' "$base" > "$work/tree2/rootfs/fake/etc/pacman.d/mirrorlist"

  zrc=0
  PORTS_DIR="$work/tree2/ports" ROOTFS_DIR="$work/tree2/rootfs" bash "$RESOLVE" fake \
    > "$work/zout" 2> "$work/zerr" || zrc=$?
  zgot="$(tr -d '\r' < "$work/zout")"
  if [ "$zrc" -eq 0 ] && [ "$zgot" = "$ANCHOR_VERSION" ]; then
    ok "a Zstandard base.db is read, and the repository name comes from the port"
  else
    fail "a Zstandard base.db is read, and the repository name comes from the port" \
      "exit $zrc, printed: ${zgot:-nothing}" \
      "it said: $(tr -d '\r' < "$work/zerr" | tr '\n' '|')" \
      "reproduce: $REPRO"
  fi
fi

summary
