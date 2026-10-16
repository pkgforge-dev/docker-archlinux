#!/usr/bin/env bash
#
# The evidence file of the image is complete, and describes this image.
#
# Each package entry gives the name, the version, the size, the sha256 and
# the build date of the package. A reader can then tell what is in an image
# without the image. scripts/gen-evidence writes the file.
#
# EVIDENCE names the evidence file of the image under test.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"
image_require
: "${EVIDENCE:?this test needs EVIDENCE set to the evidence file of this image}"

if ! command -v jq >/dev/null 2>&1; then
  fail "jq is on PATH" "this test reads the evidence file with jq" \
    "reproduce: command -v jq"
  summary
  exit 1
fi

if [ ! -f "$EVIDENCE" ]; then
  fail "the evidence file exists" \
    "expected: $EVIDENCE" \
    "the build writes one evidence file for each platform" \
    "reproduce: scripts/gen-evidence <arch> $IMAGE $PLATFORM $EVIDENCE (the commit and the time come from the labels)"
  summary
  exit 1
fi

if ! jq -e . "$EVIDENCE" >/dev/null 2>&1; then
  fail "the evidence file is JSON" "path: $EVIDENCE" \
    "reproduce: jq . $EVIDENCE"
  summary
  exit 1
fi
ok "the evidence file is JSON"

work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

# The top level: what was built, from what, and when.
for key in image platform digest built source_commit anchor packages; do
  if [ "$(jq -r --arg k "$key" 'has($k)' "$EVIDENCE")" = "true" ]; then
    ok "the evidence has the top-level key $key"
  else
    fail "the evidence has the top-level key $key" \
      "keys found: $(jq -r 'keys | join(", ")' "$EVIDENCE")" \
      "reproduce: jq -r 'keys | join(\", \")' $EVIDENCE"
  fi
done

# The evidence describes the image under test, not another image.
ev_platform="$(jq -r '.platform // ""' "$EVIDENCE")"
if [ "$ev_platform" = "$PLATFORM" ]; then
  ok "the platform of the evidence is the platform under test ($PLATFORM)"
else
  fail "the platform of the evidence is the platform under test" \
    "evidence: $ev_platform" \
    "under test: $PLATFORM" \
    "reproduce: jq -r .platform $EVIDENCE, and compare it with PLATFORM"
fi

ev_digest="$(jq -r '.digest // ""' "$EVIDENCE")"
img_digest="$(image_digest "$IMAGE")"
if [ -z "$img_digest" ]; then
  fail "the digest of the image is known here" \
    "neither the reference nor $RUNTIME image inspect gives a digest for $IMAGE" \
    "an image with no digest cannot be tied to its evidence" \
    "reproduce: $RUNTIME image inspect $IMAGE --format '{{ .RepoDigests }}'"
elif [ "$ev_digest" = "$img_digest" ]; then
  ok "the digest of the evidence is the digest of the image ($img_digest)"
else
  fail "the digest of the evidence is the digest of the image" \
    "evidence: $ev_digest" \
    "image: $img_digest" \
    "reproduce: jq -r .digest $EVIDENCE, and compare it with $RUNTIME image inspect $IMAGE"
fi

# The source commit ties the image to the tree that built it.
ev_commit="$(jq -r '.source_commit // ""' "$EVIDENCE")"
if [[ $ev_commit =~ ^[0-9a-f]{40}$ ]]; then
  ok "source_commit of the evidence is a full commit hash"
else
  fail "source_commit of the evidence is a full commit hash" "found: $ev_commit" \
    "reproduce: jq -r .source_commit $EVIDENCE; the build gives the 40 character hash"
fi

# ⛔ source_commit and built are the revision and created labels of the image,
# or unknown for a label that is absent or empty. An evidence file made again
# later, as the release does, names the build and not that later run.
ev_built="$(jq -r '.built // ""' "$EVIDENCE")"
rc=0
labels="$("$RUNTIME" image inspect "$IMAGE" --format '{{ json .Config.Labels }}' 2> "$work/inspect.err")" || rc=$?
if [ "$rc" -ne 0 ] || ! printf '%s' "$labels" | jq -e 'type == "object" or type == "null"' > /dev/null; then
  fail "the labels of the image can be read" \
    "$RUNTIME image inspect exited $rc and printed '${labels}'" \
    "stderr: $(tr -d '\r' < "$work/inspect.err" | awk 'NF { last = $0 } END { print last }')" \
    "reproduce: $RUNTIME image inspect $IMAGE --format '{{ json .Config.Labels }}'"
else
  label() {
    printf '%s' "$labels" | jq -r --arg k "$1" '(.[$k] // "") | if . == "" then "unknown" else . end'
  }
  want_commit="$(label org.opencontainers.image.revision)"
  want_built="$(label org.opencontainers.image.created)"
  if [ "$ev_commit" = "$want_commit" ] && [ "$ev_built" = "$want_built" ]; then
    ok "source_commit and built of the evidence are the revision and created labels of the image"
  else
    fail "source_commit and built of the evidence are the revision and created labels of the image" \
      "evidence: source_commit $ev_commit, built $ev_built" \
      "image labels: revision $want_commit, created $want_built" \
      "reproduce: jq -r '.source_commit, .built' $EVIDENCE; $RUNTIME image inspect $IMAGE --format '{{ json .Config.Labels }}'"
  fi
fi

#---------------------------------------------------------------------------#
# The evidence records each package that the image says is installed.
#
# ⛔ Not a comparison with package_count: gen-evidence derives package_count
# from .packages, so the two always agree. This asks pacman in the image for
# each name and version. So it finds an entry that gen-evidence dropped while
# it read the local database, and an evidence file whose versions do not
# describe this image.
#---------------------------------------------------------------------------#
rc=0
"$RUNTIME" run --rm --platform "$PLATFORM" "$IMAGE" pacman -Q > "$work/installed.raw" 2> "$work/pacman-q.err" || rc=$?
tr -d '\r' < "$work/installed.raw" | awk 'NF == 2' | LC_ALL=C sort > "$work/installed.txt"
jq -r '.packages[] | "\(.name) \(.version)"' "$EVIDENCE" | tr -d '\r' | LC_ALL=C sort > "$work/recorded.txt"
installed="$(awk 'END { print NR }' "$work/installed.txt")"
recorded="$(awk 'END { print NR }' "$work/recorded.txt")"
if [ "$rc" -ne 0 ] || [ "$installed" -eq 0 ]; then
  fail "the image gives its installed packages" \
    "$RUNTIME run exited $rc and gave $installed lines of name and version" \
    "stderr: $(tr -d '\r' < "$work/pacman-q.err" | awk 'NF { last = $0 } END { print last }')" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE pacman -Q"
else
  only_image="$(LC_ALL=C comm -23 "$work/installed.txt" "$work/recorded.txt" | awk 'NR <= 10 { printf "%s%s", sep, $0; sep = ", " }')"
  only_evidence="$(LC_ALL=C comm -13 "$work/installed.txt" "$work/recorded.txt" | awk 'NR <= 10 { printf "%s%s", sep, $0; sep = ", " }')"
  if [ -z "$only_image" ] && [ -z "$only_evidence" ]; then
    ok "the evidence records each of the $recorded packages that the image has installed, with its version"
  else
    fail "the evidence records each package that the image has installed, with its version" \
      "the image has $installed, the evidence records $recorded" \
      "in the image only (at most 10): ${only_image:-none}" \
      "in the evidence only (at most 10): ${only_evidence:-none}" \
      "gen-evidence reads /var/lib/pacman/local itself, so a fault there drops an entry with no message" \
      "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE pacman -Q | sort, then jq -r '.packages[] | \"\\(.name) \\(.version)\"' $EVIDENCE | sort"
  fi
fi

pkg_count="$(jq -r '.packages | length' "$EVIDENCE")"
if [ "$pkg_count" -gt 0 ]; then
  ok "the evidence records $pkg_count packages"
else
  fail "the evidence records at least one package" "packages: $pkg_count" \
    "reproduce: jq '.packages | length' $EVIDENCE"
fi

# Each package entry has all five facts.
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
  ok "each package entry has a name, a version, a positive size, a sha256 and a release date"
else
  fail "each package entry has a name, a version, a positive size, a sha256 and a release date" \
    "entries with a fact missing: $incomplete" \
    "reproduce: jq '.packages[] | select(.sha256 == \"-\" or .size == \"-\" or .released == \"-\")' $EVIDENCE"
fi

# The anchor names the anchor tag of the image, so it must be a recorded
# package.
anchor="$(jq -r '.anchor.name // ""' "$EVIDENCE")"
anchor_ver="$(jq -r '.anchor.version // ""' "$EVIDENCE")"
if [ -z "$anchor" ] || [ -z "$anchor_ver" ]; then
  fail "the anchor names a package and a version" \
    "anchor.name: $anchor, anchor.version: $anchor_ver" \
    "reproduce: jq -r .anchor $EVIDENCE, and scripts/resolve-anchor <arch> for the value it must have"
elif [ "$(jq -r --arg n "$anchor" --arg v "$anchor_ver" \
      '[ .packages[] | select(.name == $n and .version == $v) ] | length' "$EVIDENCE")" -gt 0 ]; then
  ok "the anchor $anchor $anchor_ver is a recorded package"
else
  fail "the anchor is a recorded package" \
    "anchor: $anchor $anchor_ver" \
    "the anchor tag is named after this version, so the evidence must record it" \
    "reproduce: jq -r '.packages[] | select(.name == \"$anchor\")' $EVIDENCE"
fi

summary
