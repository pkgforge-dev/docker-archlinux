#!/usr/bin/env bash
#
# The tag families the publish job creates.
#
# Both registry names have to appear. GHCR is derived from the repository owner
# and Docker Hub is a different organisation name, so emitting one name for both
# sends half the tags to a repository nothing pulls.
#
# Nothing that exists today may disappear. :latest and :v<date> are pulled by
# real consumers, so they are asserted here rather than assumed.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

TAGS="$REPO_ROOT/scripts/tag-names"
GHCR="ghcr.io/pkgforge-dev/archlinux"
HUB="pkgforge/archlinux"
VERSION="2026.08.26"
ANCHOR="7.1.0.r9.g54d9411-2"

if [ ! -x "$TAGS" ]; then
  fail "scripts/tag-names is executable" "expected: $TAGS" \
    "reproduce: git update-index --chmod=+x scripts/tag-names"
  summary
  exit 1
fi

tags_for() { # docker arch -> full refs, one per line
  "$TAGS" arch "$1" "$VERSION" "$ANCHOR" "$GHCR" "$HUB"
}

# The uname -m spelling comes first in each alias set, because that half is the
# organisation convention. The docker spelling is this repository's extension.
expect_alias_count() { # arch expected
  local got
  got="$("$TAGS" aliases "$1" | tr ' ' '\n' | awk 'NF' | wc -l | tr -d '[:space:]')"
  if [ "$got" = "$2" ]; then
    ok "$1 has $2 alias name(s)"
  else
    fail "$1 has $2 alias name(s)" "got $got: $("$TAGS" aliases "$1")" \
      "reproduce: $TAGS aliases $1"
  fi
}

expect_alias_count amd64 2
expect_alias_count arm64 2
expect_alias_count armv7 3
# uname -m reports loongarch64 inside the image, where the OCI platform string
# and the image's own architecture field are both loong64. Measured in
# HISTORY/loong64.md.
expect_alias_count loong64 2
# riscv64 is spelled the same in both families, so it is one tag and not two.
expect_alias_count riscv64 1
# uname -m and the docker architecture agree on all three PowerPC ports, so the
# second name in each set is neither: it is the spelling ArchPOWER itself uses
# in its repository paths and in Architecture, which is where a consumer of that
# port will look first.
expect_alias_count ppc 2
expect_alias_count ppc64 2
expect_alias_count ppc64le 2

# Every architecture emits three shapes per alias, on both registries.
for arch in amd64 arm64 armv7 loong64 riscv64 ppc ppc64 ppc64le; do
  aliases="$("$TAGS" aliases "$arch")"
  n_alias="$(printf '%s\n' "$aliases" | tr ' ' '\n' | awk 'NF' | wc -l | tr -d '[:space:]')"
  want=$((n_alias * 3 * 2))
  emitted="$(tags_for "$arch")"
  got="$(awk 'NF' <<< "$emitted" | wc -l | tr -d '[:space:]')"
  if [ "$got" = "$want" ]; then
    ok "$arch emits $want tags, $n_alias alias(es) times rolling, dated and pinned, on two registries"
  else
    fail "$arch emits $want tags" "got $got" \
      "reproduce: $TAGS arch $arch $VERSION $ANCHOR"
  fi

  for a in $aliases; do
    missing=""
    for shape in "$a" "$a-v$VERSION" "$a-$ANCHOR"; do
      for image in "$GHCR" "$HUB"; do
        if ! grep -qxF "$image:$shape" <<< "$emitted"; then
          missing="$missing $image:$shape"
        fi
      done
    done
    if [ -z "$missing" ]; then
      ok "$arch alias $a has a rolling, a dated and a pinned tag on both registries"
    else
      fail "$arch alias $a has all three shapes on both registries" "missing:$missing" \
        "reproduce: $TAGS arch $arch $VERSION $ANCHOR, which must emit $GHCR and $HUB for every alias"
    fi
  done
done

# The index tags that already exist and must keep working.
index="$("$TAGS" index "$VERSION" "$GHCR" "$HUB")"
for shape in "latest" "v$VERSION"; do
  for image in "$GHCR" "$HUB"; do
    if grep -qxF "$image:$shape" <<< "$index"; then
      ok "index tag $image:$shape is created"
    else
      fail "index tag $image:$shape is created" "the index tags are: $(printf '%s\n' "$index" | tr '\n' ' ')" \
        "reproduce: $TAGS index $VERSION"
    fi
  done
done

# No alias may be claimed by two architectures, or one would overwrite another.
all_aliases="$(for arch in amd64 arm64 armv7 loong64 riscv64 ppc ppc64 ppc64le; do "$TAGS" aliases "$arch" | tr ' ' '\n'; done | awk 'NF')"
dupes="$(printf '%s\n' "$all_aliases" | sort | uniq -d | tr '\n' ' ')"
if [ -z "$(printf '%s' "$dupes" | tr -d '[:space:]')" ]; then
  ok "no alias is claimed by two architectures"
else
  fail "no alias is claimed by two architectures" "duplicated: $dupes" \
    "reproduce: for a in amd64 arm64 armv7 loong64 riscv64 ppc ppc64 ppc64le; do scripts/tag-names aliases $a; done"
fi

# Both organisation names appear. They differ and it is not a typo.
amd64_tags="$(tags_for amd64)"
if grep -q "^$GHCR:" <<< "$amd64_tags" && grep -q "^$HUB:" <<< "$amd64_tags"; then
  ok "both registry names are emitted, $GHCR and $HUB"
else
  fail "both registry names are emitted" "one of the two organisation names is missing" \
    "reproduce: $TAGS arch amd64 $VERSION $ANCHOR, and look for both $GHCR and $HUB"
fi

# An unknown architecture is refused rather than silently skipped.
#
# The name here was ppc64le until 2026-08-28, when ppc64le became one of the
# eight this repository builds and the assertion started proving the opposite
# of what it says. s390x is the replacement because it is a real Arch port name
# that this repository does not build, so a session adding it trips this and
# reads the note rather than wondering why an unrelated test failed.
if "$TAGS" arch s390x "$VERSION" "$ANCHOR" "$GHCR" >/dev/null 2>&1; then
  fail "an unknown architecture is refused" "tag-names accepted s390x" \
    "reproduce: $TAGS arch s390x $VERSION $ANCHOR, which must exit non-zero"
else
  ok "an unknown architecture is refused"
fi

# A missing version is refused, so a tag can never be created as bare :-v
if "$TAGS" arch amd64 "" "$ANCHOR" "$GHCR" >/dev/null 2>&1; then
  fail "an empty version is refused" "tag-names accepted an empty version" \
    "reproduce: $TAGS arch amd64 '' $ANCHOR, which must exit non-zero"
else
  ok "an empty version is refused"
fi

#---------------------------------------------------------------------------#
# A pinned tag is created once and never pointed at another image.
#
# ⛔ v<date>, <alias>-v<date> and <alias>-<anchor> are pinned; latest and
# <alias> are rolling. --existing names the tags the repository carries, and a
# pinned one on that list is left out, so the publish cannot move it. Before
# the flag v2026.08.26 and v2026.08.28 were each created by more than one
# build, and every <alias>-<anchor> moved each day. HISTORY/pinned-tags.md.
#---------------------------------------------------------------------------#
work="$(work_dir)"
trap 'rm -rf "$work"' EXIT
# x86_64-$ANCHOR.1 is another anchor family, as riscv64's -2.1 is beside the
# -2 of the others. It holds x86_64-$ANCHOR as a prefix and must not hide it.
printf '%s\n' "x86_64-v$VERSION" "amd64-$ANCHOR" "v$VERSION" "latest" "x86_64" "x86_64-$ANCHOR.1" > "$work/existing"

# Each call keeps its status, so a tag-names that exits non-zero fails an
# assertion here rather than ending this file under set -e with no line.
arch_rc=0
kept="$("$TAGS" --existing "$work/existing" arch amd64 "$VERSION" "$ANCHOR" "$GHCR" "$HUB" 2> "$work/arch.err")" || arch_rc=$?
moved=""
for shape in "x86_64-v$VERSION" "amd64-$ANCHOR"; do
  for image in "$GHCR" "$HUB"; do
    if grep -qxF "$image:$shape" <<< "$kept"; then
      moved="$moved $image:$shape"
    fi
  done
done
if [ "$arch_rc" -eq 0 ] && [ -z "$moved" ]; then
  ok "a pinned architecture tag that exists is left out, on both registries"
else
  fail "a pinned architecture tag that exists is left out, on both registries" \
    "exit $arch_rc, printed although on the list:$moved" \
    "the publish would point a pinned tag at another image" \
    "reproduce: printf 'x86_64-v$VERSION\n' > l; $TAGS --existing l arch amd64 $VERSION $ANCHOR $GHCR $HUB"
fi

# Tag names, not an architecture list: x86_64 and amd64 are the two rolling
# tags here. Held in a variable so 75-architecture-set.sh does not read the
# loop as one over architectures.
want_printed="x86_64 amd64 x86_64-$ANCHOR amd64-v$VERSION"
absent=""
for shape in $want_printed; do
  for image in "$GHCR" "$HUB"; do
    if ! grep -qxF "$image:$shape" <<< "$kept"; then
      absent="$absent $image:$shape"
    fi
  done
done
if [ -z "$absent" ]; then
  ok "the rolling tags, listed or not, and the pinned tags not on the list are printed"
else
  fail "the rolling tags, listed or not, and the pinned tags not on the list are printed" \
    "missing:$absent" \
    "a rolling tag left out stops moving, and a pinned tag left out is never created" \
    "reproduce: $TAGS --existing <list> arch amd64 $VERSION $ANCHOR $GHCR $HUB"
fi

if grep -qF "x86_64-v$VERSION is pinned and exists" "$work/arch.err" &&
  grep -qF "amd64-$ANCHOR is pinned and exists" "$work/arch.err"; then
  ok "each pinned tag that is left out is named on stderr"
else
  fail "each pinned tag that is left out is named on stderr" \
    "stderr: $(tr '\n' '|' < "$work/arch.err")" \
    "reproduce: $TAGS --existing <list> arch amd64 $VERSION $ANCHOR $GHCR"
fi

index_rc=0
index_kept="$("$TAGS" --existing "$work/existing" index "$VERSION" "$GHCR" "$HUB" 2> /dev/null)" || index_rc=$?
if [ "$index_rc" -eq 0 ] && ! grep -qF ":v$VERSION" <<< "$index_kept" && grep -qxF "$GHCR:latest" <<< "$index_kept" &&
  grep -qxF "$HUB:latest" <<< "$index_kept"; then
  ok "the dated index tag that exists is left out, and latest is printed on both registries"
else
  fail "the dated index tag that exists is left out, and latest is printed on both registries" \
    "exit $index_rc, printed: $(tr '\n' ' ' <<< "$index_kept")" \
    "reproduce: printf 'v$VERSION\n' > l; $TAGS --existing l index $VERSION $GHCR $HUB"
fi

: > "$work/empty"
fresh_rc=0
fresh="$("$TAGS" --existing "$work/empty" arch amd64 "$VERSION" "$ANCHOR" "$GHCR" "$HUB" 2> /dev/null)" || fresh_rc=$?
if [ "$fresh_rc" -eq 0 ] && [ "$fresh" = "$(tags_for amd64)" ]; then
  ok "an empty list, a new repository, prints every tag"
else
  fail "an empty list, a new repository, prints every tag" \
    "exit $fresh_rc, printed $(awk 'NF' <<< "$fresh" | wc -l | tr -d '[:space:]') of $(tags_for amd64 | wc -l | tr -d '[:space:]')" \
    "reproduce: : > l; $TAGS --existing l arch amd64 $VERSION $ANCHOR $GHCR $HUB"
fi

if "$TAGS" --existing "$work/absent" index "$VERSION" "$GHCR" > /dev/null 2>&1; then
  fail "a list that cannot be read is refused" \
    "tag-names printed tags for a list that does not exist" \
    "read as empty, it would move every pinned tag" \
    "reproduce: $TAGS --existing /nonexistent index $VERSION $GHCR, which must exit non-zero"
else
  ok "a list that cannot be read is refused"
fi

summary
