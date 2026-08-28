#!/usr/bin/env bash
#
# The static pacman is pinned, and it is pinned to the pacman this repository
# already publishes.
#
# ⛔ Two separate claims, and only the second is interesting. The first is that
# every input to the release binary carries a checksum or a commit, so nothing
# reaches a published asset unverified. The second is that the commit pinned
# there is the commit the image's own pacman is built from, which is what lets
# the binary and the image be shown to agree rather than asserted to.
#
# ⚠ Nothing here reaches the network. The anchor is a live value and changes
# when upstream moves; a test that measured it would fail for a reason outside
# this repository. .github/workflows/freshness-pacman-static.yml does that part
# and opens a pull request, which is where an upstream bump belongs.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

PIN="$REPO_ROOT/bootstrap/pacman-static/sources.pin"
BUILD="$REPO_ROOT/scripts/build-pacman-static"

if [ ! -f "$PIN" ]; then
  fail "the source pin exists" "expected: bootstrap/pacman-static/sources.pin" \
    "scripts/build-pacman-static fetches nothing that is not named there" \
    "reproduce: ls bootstrap/pacman-static/sources.pin"
  summary
  exit 1
fi

#---------------------------------------------------------------------------#
# 1. Every source record is complete.
#
# A record missing its hash is worse than a missing record: the build would
# fetch it and compare against an empty string.
#---------------------------------------------------------------------------#
bad="$(awk '
  $1 == "source" {
    n++
    if (NF != 5) { print $2 " has " NF " fields, expected 5"; next }
    if ($5 !~ /^[0-9a-f]{64}$/) { print $2 " sha256 is not 64 hex characters" }
    if ($4 !~ /^https:\/\//) { print $2 " is not fetched over https" }
  }
  END { if (n == 0) print "there are no source records at all" }
' "$PIN")"
if [ -z "$bad" ]; then
  count="$(awk '$1 == "source" { n++ } END { print n + 0 }' "$PIN")"
  ok "all $count pinned sources carry an https URL and a sha256"
else
  fail "all pinned sources carry an https URL and a sha256" \
    "$(printf '%s' "$bad" | tr '\n' '|')" \
    "the build compares what arrives against these, so an empty one verifies nothing" \
    "reproduce: awk '\$1 == \"source\"' bootstrap/pacman-static/sources.pin"
fi

#---------------------------------------------------------------------------#
# 2. The toolchain is pinned for every host the matrix can run on.
#---------------------------------------------------------------------------#
zig_bad="$(awk '
  $1 == "zig" {
    n++
    if (NF != 5) { print $3 " has " NF " fields, expected 5"; next }
    if ($5 !~ /^[0-9a-f]{64}$/) { print $3 " sha256 is not 64 hex characters" }
    seen[$3] = 1
  }
  END {
    if (n == 0) print "no zig is pinned at all"
    if (!("x86_64-linux" in seen)) print "no zig for x86_64-linux"
    if (!("aarch64-linux" in seen)) print "no zig for aarch64-linux"
  }
' "$PIN")"
if [ -z "$zig_bad" ]; then
  ok "zig is pinned by sha256 for both host architectures the matrix uses"
else
  fail "zig is pinned by sha256 for both host architectures the matrix uses" \
    "$(printf '%s' "$zig_bad" | tr '\n' '|')" \
    "vars.ARM64_RUNNER can move a job to an aarch64 runner, which needs its own tarball" \
    "reproduce: awk '\$1 == \"zig\"' bootstrap/pacman-static/sources.pin"
fi

#---------------------------------------------------------------------------#
# 3. pacman is pinned by commit, not by tag.
#
# ⛔ Policy 10. A tag moves, and v7.1.0 is an annotated tag object pointing nine
# commits behind what Arch ships, so pinning it would build a pacman that is in
# no published image.
#---------------------------------------------------------------------------#
commit="$(awk '$1 == "pacman" { print $2; exit }' "$PIN")"
if printf '%s' "$commit" | grep -qE '^[0-9a-f]{40}$'; then
  ok "pacman is pinned at a full 40 character commit"
else
  fail "pacman is pinned at a full 40 character commit" \
    "the pin says: ${commit:-nothing}" \
    "a short hash or a tag name is not a pin: both can come to mean another commit" \
    "reproduce: awk '\$1 == \"pacman\"' bootstrap/pacman-static/sources.pin"
fi

#---------------------------------------------------------------------------#
# 4. ⭐ The pinned commit is the one the published anchor names.
#
# The anchor tag family is <alias>-7.1.0.r9.g54d9411-<pkgrel>. The g54d9411 half
# is `git describe` output: the abbreviated commit the release was built from.
# So the static binary and the image's own pacman come from one commit, and this
# is the assertion that says so without asking the network.
#---------------------------------------------------------------------------#
describe="$(awk '$1 == "describe" { print $2; exit }' "$PIN")"
if [ -z "$describe" ]; then
  fail "the pin records the describe string the anchor is named after" \
    "no describe line in bootstrap/pacman-static/sources.pin" \
    "without it nothing connects the pinned commit to the published tag family" \
    "reproduce: awk '\$1 == \"describe\"' bootstrap/pacman-static/sources.pin"
else
  # The abbreviation is whatever the describe string carries after the g, so its
  # length is read rather than assumed. Arch uses 7 characters and upstream's
  # own meson uses 4, and a hardcoded 7 here would silently stop comparing.
  abbrev="$(printf '%s' "$describe" | awk -F'.g' 'NF > 1 { print $NF }')"
  if [ -z "$abbrev" ]; then
    fail "the describe string carries an abbreviated commit" \
      "read: $describe" \
      "expected something of the shape 7.1.0.r9.g54d9411" \
      "reproduce: awk '\$1 == \"describe\"' bootstrap/pacman-static/sources.pin"
  elif [ "${commit:0:${#abbrev}}" = "$abbrev" ]; then
    ok "the pinned commit $abbrev is the one the anchor family is named after"
  else
    fail "the pinned commit is the one the anchor family is named after" \
      "the pin's commit starts ${commit:0:${#abbrev}}, the describe string says $abbrev" \
      "⛔ these disagreeing means the release binary is not the pacman in any published image" \
      "reproduce: awk '\$1 == \"pacman\" || \$1 == \"describe\"' bootstrap/pacman-static/sources.pin"
  fi
fi

#---------------------------------------------------------------------------#
# 5. Every architecture the matrix builds has a row in the build script.
#
# ⛔ Read from the matrix, not from a list here. A release that carries seven of
# eight binaries looks complete and is not, and the missing one is discovered by
# whoever needed it.
#---------------------------------------------------------------------------#
WF="$REPO_ROOT/.github/workflows/build-deploy.yml"
if [ ! -f "$BUILD" ] || [ ! -f "$WF" ]; then
  fail "the build script and the matrix both exist" \
    "script: $BUILD" "workflow: $WF" \
    "reproduce: ls scripts/build-pacman-static .github/workflows/build-deploy.yml"
  summary
  exit 1
fi

matrix_arches="$(awk -F: '
  /^[[:space:]]*-[[:space:]]+docker_arch:/ {
    v = $2
    gsub(/[[:space:]]/, "", v)
    print v
  }' "$WF" | tr -d '\r' | LC_ALL=C sort)"

missing=""
while IFS= read -r a; do
  [ -n "$a" ] || continue
  if ! awk -v a="$a" '
      $0 ~ "^[[:space:]]*" a "\\)" { found = 1 }
      END { exit !found }' "$BUILD"; then
    missing="$missing $a"
  fi
done <<< "$matrix_arches"

if [ -z "$missing" ]; then
  n="$(awk 'NF { n++ } END { print n + 0 }' <<< "$matrix_arches")"
  ok "scripts/build-pacman-static has a target row for all $n matrix architectures"
else
  fail "scripts/build-pacman-static has a target row for every matrix architecture" \
    "missing:$missing" \
    "each needs a zig triple, an OpenSSL target, an ELF machine and an emulator name" \
    "reproduce: grep -n ') *echo' scripts/build-pacman-static"
fi

#---------------------------------------------------------------------------#
# 6. The image build does not read the pin.
#
# ⛔ The static binary is a release asset. If the Dockerfile ever fetched it,
# the image would gain a build time download of a binary, which is the exact
# thing policy 5 forbids, and the bootstrap would stop being reproducible from
# the official image alone.
#---------------------------------------------------------------------------#
leaks="$(grep -rln -e 'pacman-static' -e 'sources.pin' \
  "$REPO_ROOT/Dockerfile" "$REPO_ROOT/bootstrap/any" 2>/dev/null || true)"
if [ -z "$leaks" ]; then
  ok "neither the Dockerfile nor the bootstrap scripts name the static pacman"
else
  fail "neither the Dockerfile nor the bootstrap scripts name the static pacman" \
    "named in: $(printf '%s' "$leaks" | tr '\n' ' ')" \
    "an image that downloads a prebuilt binary at build time is not bootstrappable" \
    "reproduce: grep -rn pacman-static Dockerfile bootstrap/any"
fi

summary
