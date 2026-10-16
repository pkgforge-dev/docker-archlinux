#!/usr/bin/env bash
#
# The tag families that scripts/tag-names makes, for each port of
# scripts/ports.
#
#   latest, v<version>                    the index
#   <alias>, <alias>-v<version>, <alias>-<anchor>   each port, each alias
#
# ⛔ No family and no alias may go away: people and mirror-archlinux pull
# them. A pinned tag that exists is left out, so the publish never moves it.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

TAGS="$REPO_ROOT/scripts/tag-names"
PORTS="$REPO_ROOT/scripts/ports"
# Two images, to see that each tag is made on each image given.
IMG1="ghcr.io/example/archlinux"
IMG2="docker.io/example/archlinux"
VERSION="2030.01.02"
ANCHOR="7.1.0.r9.g54d9411-2"

for f in "$TAGS" "$PORTS"; do
  if [ ! -x "$f" ]; then
    fail "${f#"$REPO_ROOT/"} is executable" "reproduce: git update-index --chmod=+x ${f#"$REPO_ROOT/"}"
    summary
    exit 1
  fi
done

work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

mapfile -t ARCHES < <("$PORTS" list)
if [ "${#ARCHES[@]}" -eq 0 ]; then
  fail "scripts/ports lists the ports" "it lists none" "reproduce: scripts/ports list"
  summary
  exit 1
fi

#---------------------------------------------------------------------------#
# 1. Each port: its aliases, three shapes each, on both images.
#---------------------------------------------------------------------------#
for arch in "${ARCHES[@]}"; do
  want_aliases="$("$PORTS" aliases "$arch" | tr '\n' ' ' | sed 's/ $//')"
  got_aliases="$("$TAGS" aliases "$arch")"
  if [ "$got_aliases" = "$want_aliases" ]; then
    ok "$arch: tag-names aliases is the alias list of ports/$arch.conf, in order"
  else
    fail "$arch: tag-names aliases is the alias list of ports/$arch.conf, in order" \
      "tag-names: '$got_aliases'; ports: '$want_aliases'" "reproduce: scripts/tag-names aliases $arch"
  fi

  rc=0
  "$TAGS" arch "$arch" "$VERSION" "$ANCHOR" "$IMG1" "$IMG2" > "$work/$arch" || rc=$?
  want=""
  for a in $want_aliases; do
    for shape in "$a" "$a-v$VERSION" "$a-$ANCHOR"; do
      want="$want$IMG1:$shape
$IMG2:$shape
"
    done
  done
  if [ "$rc" -eq 0 ] && [ "$(LC_ALL=C sort "$work/$arch")" = "$(printf '%s' "$want" | LC_ALL=C sort)" ]; then
    ok "$arch: each alias has a rolling, a dated and an anchor tag on both images, and nothing else"
  else
    fail "$arch: each alias has a rolling, a dated and an anchor tag on both images, and nothing else" \
      "exit $rc; got: $(tr '\n' ' ' < "$work/$arch")" \
      "reproduce: scripts/tag-names arch $arch $VERSION $ANCHOR $IMG1 $IMG2"
  fi
done

# No alias is the alias of two ports, or one port would write over another.
dupes="$(for arch in "${ARCHES[@]}"; do "$PORTS" aliases "$arch"; done | LC_ALL=C sort | uniq -d | tr '\n' ' ')"
if [ -z "${dupes// /}" ]; then
  ok "no alias belongs to two ports"
else
  fail "no alias belongs to two ports" "shared: $dupes" "reproduce: scripts/ports field aliases"
fi

#---------------------------------------------------------------------------#
# 2. The index.
#---------------------------------------------------------------------------#
rc=0
index="$("$TAGS" index "$VERSION" "$IMG1" "$IMG2")" || rc=$?
want_index="$IMG1:latest
$IMG2:latest
$IMG1:v$VERSION
$IMG2:v$VERSION"
if [ "$rc" -eq 0 ] && [ "$(LC_ALL=C sort <<< "$index")" = "$(LC_ALL=C sort <<< "$want_index")" ]; then
  ok "the index has latest and v<version> on both images"
else
  fail "the index has latest and v<version> on both images" "exit $rc; got: $(tr '\n' ' ' <<< "$index")" \
    "reproduce: scripts/tag-names index $VERSION $IMG1 $IMG2"
fi

#---------------------------------------------------------------------------#
# 3. Bad input is refused.
#---------------------------------------------------------------------------#
# refused DESC CMD... -> ok when CMD exits non-zero and prints no tag
refused() {
  local desc="$1" rc=0
  shift
  "$@" > "$work/refused.out" 2> "$work/refused.err" || rc=$?
  if [ "$rc" -ne 0 ] && [ ! -s "$work/refused.out" ]; then
    ok "$desc"
  else
    fail "$desc" "exit $rc, printed: $(tr '\n' ' ' < "$work/refused.out")" "reproduce: $*"
  fi
}
refused "a name that is not a port is refused" "$TAGS" arch notaport "$VERSION" "$ANCHOR" "$IMG1"
refused "an empty version is refused" "$TAGS" arch "${ARCHES[0]}" "" "$ANCHOR" "$IMG1"
refused "an empty anchor is refused" "$TAGS" arch "${ARCHES[0]}" "$VERSION" "" "$IMG1"
refused "an anchor that makes a bad tag is refused" "$TAGS" arch "${ARCHES[0]}" "$VERSION" "1:7.1.0-1" "$IMG1"
refused "a list that cannot be read is refused" "$TAGS" --existing "$work/no-such-file" index "$VERSION" "$IMG1"

#---------------------------------------------------------------------------#
# 4. --existing leaves out each pinned tag that is on the list.
#---------------------------------------------------------------------------#
arch="${ARCHES[0]}"
mapfile -t al < <("$PORTS" aliases "$arch")
a1="${al[0]}"
a2="${al[${#al[@]} - 1]}"
# <a1>-<ANCHOR>.1 is another anchor that has <a1>-<ANCHOR> as a prefix. It
# must not hide <a1>-<ANCHOR>.
printf '%s\n' "$a1-v$VERSION" "$a2-$ANCHOR" "v$VERSION" latest "$a1" "$a1-$ANCHOR.1" > "$work/existing"

rc=0
"$TAGS" --existing "$work/existing" arch "$arch" "$VERSION" "$ANCHOR" "$IMG1" "$IMG2" > "$work/kept" 2> "$work/kept.err" || rc=$?
printf '%s\n' "$IMG1:$a1-v$VERSION" "$IMG1:$a2-$ANCHOR" "$IMG2:$a1-v$VERSION" "$IMG2:$a2-$ANCHOR" > "$work/pinned"
moved="$(awk 'NR == FNR { p[$0] = 1; next } ($0 in p) { printf "%s ", $0 }' "$work/pinned" "$work/kept")"
if [ "$rc" -eq 0 ] && [ -z "${moved// /}" ]; then
  ok "a pinned port tag on the list is left out, on both images"
else
  fail "a pinned port tag on the list is left out, on both images" "exit $rc; printed: $moved" \
    "the publish would point a pinned tag at another image" \
    "reproduce: scripts/tag-names --existing <list> arch $arch $VERSION $ANCHOR $IMG1 $IMG2"
fi

absent=""
for t in "$a1" "$a2" "$a1-$ANCHOR" "$a2-v$VERSION"; do
  for image in "$IMG1" "$IMG2"; do
    grep -qxF -- "$image:$t" "$work/kept" || absent="$absent $image:$t"
  done
done
if [ -z "$absent" ]; then
  ok "rolling tags, on the list or not, and pinned tags not on the list are printed"
else
  fail "rolling tags, on the list or not, and pinned tags not on the list are printed" "missing:$absent" \
    "a rolling tag left out stops moving; a pinned tag left out is never made" \
    "reproduce: scripts/tag-names --existing <list> arch $arch $VERSION $ANCHOR $IMG1 $IMG2"
fi

rc=0
"$TAGS" --existing "$work/existing" index "$VERSION" "$IMG1" "$IMG2" > "$work/index" 2> "$work/index.err" || rc=$?
if [ "$rc" -eq 0 ] && [ "$(LC_ALL=C sort "$work/index" | tr '\n' ' ')" = "$IMG2:latest $IMG1:latest " ]; then
  ok "an existing v<version> is left out of the index, and latest is printed"
else
  fail "an existing v<version> is left out of the index, and latest is printed" \
    "exit $rc; printed: $(tr '\n' ' ' < "$work/index")" \
    "reproduce: scripts/tag-names --existing <list> index $VERSION $IMG1 $IMG2"
fi

: > "$work/empty"
rc=0
"$TAGS" --existing "$work/empty" arch "$arch" "$VERSION" "$ANCHOR" "$IMG1" "$IMG2" > "$work/all" 2> "$work/all.err" || rc=$?
if [ "$rc" -eq 0 ] && cmp -s "$work/all" "$work/$arch"; then
  ok "an empty list, a new repository, prints every tag"
else
  fail "an empty list, a new repository, prints every tag" "exit $rc" \
    "reproduce: : > l; scripts/tag-names --existing l arch $arch $VERSION $ANCHOR $IMG1 $IMG2"
fi

summary
