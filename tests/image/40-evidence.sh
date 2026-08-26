#!/usr/bin/env bash
#
# The evidence file must be evidence.
#
# A record that says "built successfully" is not evidence. Each entry names a
# package, its version, its size, its checksum and when it was released, so a
# reader can tell what was in an image without having the image.
#
# EVIDENCE points at the file for the image under test.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"
image_require
: "${EVIDENCE:?this test needs EVIDENCE set to the evidence file for this image}"

if ! command -v jq >/dev/null 2>&1; then
  fail "jq is available" "this test reads the evidence file with jq"
  summary
  exit 1
fi

if [ ! -f "$EVIDENCE" ]; then
  fail "the evidence file exists" \
    "expected: $EVIDENCE" \
    "the build must write one evidence file per platform"
  summary
  exit 1
fi

if ! jq -e . "$EVIDENCE" >/dev/null 2>&1; then
  fail "the evidence file is valid JSON" "path: $EVIDENCE"
  summary
  exit 1
fi
ok "the evidence file is valid JSON"

# Top level: what was built, from what, and when.
for key in image platform digest built source_commit anchor packages; do
  if [ "$(jq -r --arg k "$key" 'has($k)' "$EVIDENCE")" = "true" ]; then
    ok "evidence has a top level $key"
  else
    fail "evidence has a top level $key" \
      "keys present: $(jq -r 'keys | join(", ")' "$EVIDENCE")"
  fi
done

# The evidence must describe the image under test, not some other one.
ev_platform="$(jq -r '.platform // ""' "$EVIDENCE")"
if [ "$ev_platform" = "$PLATFORM" ]; then
  ok "evidence platform matches the image under test ($PLATFORM)"
else
  fail "evidence platform matches the image under test" \
    "evidence says: $ev_platform" \
    "testing: $PLATFORM"
fi

ev_digest="$(jq -r '.digest // ""' "$EVIDENCE")"
img_digest="$(image_digest "$IMAGE")"
if [ -z "$img_digest" ]; then
  fail "the image digest is known locally" \
    "neither the reference nor $RUNTIME image inspect yielded a digest for $IMAGE" \
    "an image with no digest cannot be tied to its evidence" \
    "reproduce: $RUNTIME image inspect $IMAGE --format '{{ .RepoDigests }}'"
elif [ "$ev_digest" = "$img_digest" ]; then
  ok "evidence digest matches the image ($img_digest)"
else
  fail "evidence digest matches the image" \
    "evidence says: $ev_digest" \
    "image reports: $img_digest"
fi

# The source commit ties the image back to the tree that produced it.
ev_commit="$(jq -r '.source_commit // ""' "$EVIDENCE")"
if printf '%s\n' "$ev_commit" | grep -qE '^[0-9a-f]{40}$'; then
  ok "evidence source_commit is a full commit hash"
else
  fail "evidence source_commit is a full commit hash" "found: $ev_commit"
fi

# Every package entry carries all five facts.
pkg_count="$(jq -r '.packages | length' "$EVIDENCE")"
if [ "$pkg_count" -gt 0 ]; then
  ok "evidence records $pkg_count packages"
else
  fail "evidence records at least one package" "packages: $pkg_count"
fi

incomplete="$(jq -r '
  [ .packages[]
    | select(
        (.name // "" | length) == 0
        or (.version // "" | length) == 0
        or (.size // 0 | tonumber? // 0) <= 0
        or (.sha256 // "" | test("^[0-9a-f]{64}$") | not)
        or (.released // "" | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}") | not)
      )
    | .name // "<unnamed>" ]
  | join(", ")' "$EVIDENCE")"
if [ -z "$incomplete" ]; then
  ok "every package entry has a name, a version, a positive size, a sha256 and a release date"
else
  fail "every package entry has a name, a version, a positive size, a sha256 and a release date" \
    "incomplete entries: $incomplete" \
    "reproduce: jq '.packages[] | select(.sha256 == null)' $EVIDENCE"
fi

# The anchor is the package the pinned tag family is named after, so it has to
# be one of the packages actually recorded.
anchor="$(jq -r '.anchor.name // ""' "$EVIDENCE")"
anchor_ver="$(jq -r '.anchor.version // ""' "$EVIDENCE")"
if [ -z "$anchor" ] || [ -z "$anchor_ver" ]; then
  fail "the anchor names a package and a version" \
    "anchor.name: $anchor, anchor.version: $anchor_ver"
elif [ "$(jq -r --arg n "$anchor" --arg v "$anchor_ver" \
      '[ .packages[] | select(.name == $n and .version == $v) ] | length' "$EVIDENCE")" -gt 0 ]; then
  ok "the anchor $anchor $anchor_ver appears in the recorded packages"
else
  fail "the anchor appears in the recorded packages" \
    "anchor: $anchor $anchor_ver" \
    "the pinned tag family is named after this version, so it must be recorded"
fi

summary
