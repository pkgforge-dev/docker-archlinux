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
# 6. The signed tag is pinned by object sha, and it is read.
#
# ⛔ The two release manager fingerprints sat in this pin unread until
# 2026-08-29. A pin carrying a fingerprint nothing checks is worse than one with
# no fingerprint at all: it reads as a verified signature to anyone skimming it,
# and while nothing read them the two names beside them were swapped without
# anything noticing.
#---------------------------------------------------------------------------#
tag_line="$(awk '$1 == "tag" { print; exit }' "$PIN")"
if [ -z "$tag_line" ]; then
  fail "the pin names the signed tag"     "expected a line: tag <name> <tag object sha>"     "reproduce: awk '\$1 == \"tag\"' bootstrap/pacman-static/sources.pin"
else
  fields="$(awk '$1 == "tag" { print NF; exit }' "$PIN")"
  obj="$(awk '$1 == "tag" { print $3; exit }' "$PIN")"
  if [ "$fields" = 3 ] && printf '%s' "$obj" | grep -qE '^[0-9a-f]{40}$'; then
    ok "the pin names the signed tag by name and by object sha"
  else
    fail "the pin names the signed tag by name and by object sha"       "got: $tag_line"       "⛔ a tag name can be moved and re-pushed, an object sha cannot"       "reproduce: awk '\$1 == \"tag\"' bootstrap/pacman-static/sources.pin"
  fi
fi

signers="$(awk '$1 == "signer" { n++ } END { print n + 0 }' "$PIN")"
badfp="$(awk '$1 == "signer" && $2 !~ /^[0-9A-F]{40}$/ { print $2 }' "$PIN")"
if [ "$signers" -ge 1 ] && [ -z "$badfp" ]; then
  ok "$signers signer fingerprints, each 40 uppercase hex characters"
else
  fail "every signer is a full 40 character fingerprint"     "count: $signers, malformed: ${badfp:-none}"     "⛔ a short key id is not an identity: it can be collided"     "reproduce: awk '\$1 == \"signer\"' bootstrap/pacman-static/sources.pin"
fi

keyservers="$(awk '$1 == "keyserver" { n++ } END { print n + 0 }' "$PIN")"
badks="$(awk '$1 == "keyserver" && $2 !~ /^hkps:\/\// { print $2 }' "$PIN")"
if [ "$keyservers" -ge 2 ] && [ -z "$badks" ]; then
  ok "$keyservers keyservers, all hkps, so one outage does not stop a release"
else
  fail "at least two hkps keyservers are pinned"     "count: $keyservers, not hkps: ${badks:-none}"     "one keyserver is one outage away from blocking every release"     "reproduce: awk '\$1 == \"keyserver\"' bootstrap/pacman-static/sources.pin"
fi

# ⛔ Each pin field has to have a reader. This is the assertion that would have
# caught the fingerprints being decorative.
for field in tag signer keyserver; do
  if grep -q "\"$field\"" "$BUILD" || grep -q "pin_field $field" "$BUILD"; then
    ok "scripts/build-pacman-static reads the $field records"
  else
    fail "scripts/build-pacman-static reads the $field records"       "the pin carries $field lines and nothing in the build looks at them"       "reproduce: grep -n $field scripts/build-pacman-static"
  fi
done

# The release workflow must refuse an asset whose tag was not verified.
PSWF="$REPO_ROOT/.github/workflows/pacman-static.yml"
if grep -q 'pacman_tag_verified_by' "$PSWF"; then
  ok "pacman-static.yml refuses an asset whose signed tag was not verified"
else
  fail "pacman-static.yml refuses an asset whose signed tag was not verified"     "NOT VERIFIED and SKIPPED are honest values, and neither may reach a release"     "reproduce: grep -n pacman_tag_verified_by .github/workflows/pacman-static.yml"
fi

#---------------------------------------------------------------------------#
# 7. Progress output never lands on stdout, because stdout is a return value.
#
# ⛔ This is the defect run 33206329907 found, the first time pacman-static.yml
# ran on a GitHub runner. `step` wrote to stdout; `ensure_zig` calls `step` and
# returns the path to zig through a command substitution; so ZIGBIN held the
# banner and the path, and every compiler wrapper written from it began
# `exec ==> zig x86_64-linux`. zlib's configure said "Missing or broken C
# compiler" and all eight architectures stopped there.
#
# ⚠ It never fired on the workstation: `ensure_zig` prints nothing once zig is
# already unpacked, which is every run after the first.
#---------------------------------------------------------------------------#
step_def="$(awk '/^step\(\)/ { print; exit }' "$BUILD")"
if [ -z "$step_def" ]; then
  fail "scripts/build-pacman-static defines step"     "reproduce: grep -n 'step()' scripts/build-pacman-static"
elif printf '%s' "$step_def" | grep -q '>&2'; then
  ok "step writes progress to stderr, so a captured function returns only its value"
else
  fail "step writes progress to stderr"     "found: $step_def"     "⛔ ensure_zig and src_of return a path through \$(...), and a step on stdout is captured with it"     "reproduce: grep -n 'step()' scripts/build-pacman-static"
fi

# Every function whose value is taken through a command substitution must print
# exactly one thing. Discovered from the captures, not listed.
captured="$(awk '
  match($0, /\$\((ensure_zig|src_of|fetch|arch_row|pin_field|ver_of)[ )]/) {
    s = substr($0, RSTART + 2)
    sub(/[ )].*$/, "", s)
    print s
  }' "$BUILD" | LC_ALL=C sort -u)"
n_captured="$(awk 'NF { n++ } END { print n + 0 }' <<< "$captured")"

leaky=""
while IFS= read -r fn; do
  [ -n "$fn" ] || continue
  # The function body, from its definition to the closing brace at column 0.
  body="$(awk -v f="^$fn\(\) \{" '$0 ~ f { inside = 1 } inside { print } inside && /^}/ { exit }' "$BUILD")"
  [ -n "$body" ] || continue
  # A bare echo or printf that is not a return value, not redirected, and not
  # inside a here-document, would be captured by the caller.
  if printf '%s
' "$body" | grep -qE '^[[:space:]]+(step|echo)[[:space:]]'      && ! printf '%s
' "$body" | grep -qE '^[[:space:]]+(step|echo)[^#]*>&2'; then
    case "$fn" in
      ensure_zig|src_of|fetch) leaky="$leaky $fn" ;;
    esac
  fi
done <<< "$captured"

if [ "$n_captured" -eq 0 ]; then
  fail "at least one function is captured through a command substitution"     "the scan found none, so this asserted nothing"     "reproduce: grep -n 'ensure_zig)' scripts/build-pacman-static"
elif [ -z "$leaky" ]; then
  ok "$n_captured captured functions, none writing progress to stdout"
else
  fail "no captured function writes progress to stdout"     "these do:$leaky"     "⛔ the caller takes stdout as the return value, so a banner becomes part of a path"     "reproduce: sed -n '/^ensure_zig/,/^}/p' scripts/build-pacman-static"
fi

# ⛔ A library build that discards its output reports a failure with no reason.
if grep -qE '(configure|make|Configure)[^|]*>/dev/null' "$BUILD"; then
  fail "no library build sends its output to /dev/null"     "a failing configure then ends the run with no message at all"     "the dispatch loop keeps a per library log and prints its tail on failure"     "reproduce: grep -n '>/dev/null' scripts/build-pacman-static"
else
  ok "no library build sends its output to /dev/null"
fi

#---------------------------------------------------------------------------#
# 8. The image build does not read the pin.
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
