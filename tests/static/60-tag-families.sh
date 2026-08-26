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
# riscv64 is spelled the same in both families, so it is one tag and not two.
expect_alias_count riscv64 1

# Every architecture emits three shapes per alias, on both registries.
for arch in amd64 arm64 armv7 riscv64; do
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
all_aliases="$(for arch in amd64 arm64 armv7 riscv64; do "$TAGS" aliases "$arch" | tr ' ' '\n'; done | awk 'NF')"
dupes="$(printf '%s\n' "$all_aliases" | sort | uniq -d | tr '\n' ' ')"
if [ -z "$(printf '%s' "$dupes" | tr -d '[:space:]')" ]; then
  ok "no alias is claimed by two architectures"
else
  fail "no alias is claimed by two architectures" "duplicated: $dupes" \
    "reproduce: for a in amd64 arm64 armv7 riscv64; do scripts/tag-names aliases $a; done"
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
if "$TAGS" arch ppc64le "$VERSION" "$ANCHOR" "$GHCR" >/dev/null 2>&1; then
  fail "an unknown architecture is refused" "tag-names accepted ppc64le" \
    "reproduce: $TAGS arch ppc64le $VERSION $ANCHOR, which must exit non-zero"
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

summary
