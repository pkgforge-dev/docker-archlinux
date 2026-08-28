#!/usr/bin/env bash
#
# The release publishes every asset family for every architecture, or it
# publishes nothing.
#
# ⛔ The failure this guards is a release that looks complete. A release missing
# one architecture's rootfs is worse than no release at all: a consumer who
# checks the page sees seven entries and no statement that an eighth should be
# there. Everything below is discovered from the build matrix, so adding an
# architecture puts it under this check with no edit here.
#
# ⚠ This reads the workflow and runs the generators against fixtures. What it
# cannot check is whether a real run produces the assets, which is a question
# about eight builds and belongs to the run itself. HISTORY/releases.md records
# the run.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

WF_DIR="$REPO_ROOT/.github/workflows"
RELEASE="$WF_DIR/release.yml"
PACMAN_WF="$WF_DIR/pacman-static.yml"
BUILD_WF="$WF_DIR/build-deploy.yml"
NOTES="$REPO_ROOT/scripts/release-notes"
MANIFEST="$REPO_ROOT/scripts/gen-manifest"
BSET="$REPO_ROOT/scripts/gen-bootstrap-set"

for f in "$RELEASE" "$PACMAN_WF" "$NOTES" "$MANIFEST" "$BSET"; do
  if [ -f "$f" ]; then
    ok "${f#"$REPO_ROOT/"} exists"
  else
    fail "${f#"$REPO_ROOT/"} exists" "reproduce: ls ${f#"$REPO_ROOT/"}"
    summary
    exit 1
  fi
done

work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

#---------------------------------------------------------------------------#
# 1. One workflow owns the v* tag.
#
# ⛔ Two workflows triggering on the same tag and both calling gh release create
# is a race whose loser fails the run after the winner published. The release
# workflow owns the tag; pacman-static.yml is called by it.
#---------------------------------------------------------------------------#
taggers=""
for wf in "$WF_DIR"/*.yml; do
  awk '
    /^on:/ { on = 1; next }
    /^[a-z]/ && !/^on:/ { on = 0 }
    on && /tags:/ { intags = 1; next }
    intags && /v[*]/ { found = 1 }
    intags && /^[^ ]/ { intags = 0 }
    END { exit found ? 0 : 1 }
  ' "$wf" && taggers="$taggers $(basename "$wf")"
done

case "$(printf '%s' "$taggers" | awk '{ print NF }')" in
  1)
    if [ "$taggers" = " release.yml" ]; then
      ok "release.yml is the only workflow triggered by a v* tag"
    else
      fail "release.yml is the only workflow triggered by a v* tag" \
        "the tag is owned by:$taggers" \
        "reproduce: grep -A4 'tags:' .github/workflows/*.yml"
    fi
    ;;
  *)
    fail "release.yml is the only workflow triggered by a v* tag" \
      "workflows triggered by a v* tag:${taggers:- none}" \
      "two workflows publishing one tag race, and the loser fails after the winner published" \
      "reproduce: grep -A4 'tags:' .github/workflows/*.yml"
    ;;
esac

if grep -q 'workflow_call:' "$PACMAN_WF"; then
  ok "pacman-static.yml is callable, so the release does not duplicate its recipe"
else
  fail "pacman-static.yml is callable" \
    "release.yml uses it, and a second copy of the build would be a second thing to keep in step" \
    "reproduce: grep -n workflow_call .github/workflows/pacman-static.yml"
fi

#---------------------------------------------------------------------------#
# 2. The publish job is gated on everything, and only a tag reaches it.
#---------------------------------------------------------------------------#
publish_block="$(awk '
  /^  publish:$/ { injob = 1; next }
  /^  [a-z_-]+:$/ { injob = 0 }
  injob { print }
' "$RELEASE")"

if [ -z "$publish_block" ]; then
  fail "release.yml has a publish job" \
    "reproduce: grep -n 'publish:' .github/workflows/release.yml"
else
  needs="$(printf '%s\n' "$publish_block" | awk '/needs:/ { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }')"
  gated=1
  for j in guard pacman rootfs manifest; do
    printf '%s' "$needs" | grep -q "$j" || gated=0
  done
  if [ "$gated" = 1 ]; then
    ok "the publish job needs every producing job: $needs"
  else
    fail "the publish job needs every producing job" \
      "needs: $needs" \
      "⛔ a release missing one architecture looks complete, which is worse than no release" \
      "reproduce: sed -n '/^  publish:/,/^  [a-z]/p' .github/workflows/release.yml"
  fi

  if printf '%s\n' "$publish_block" | grep -q "startsWith(github.ref, 'refs/tags/v')"; then
    ok "only a v* tag reaches the publish job"
  else
    fail "only a v* tag reaches the publish job" \
      "without the guard a workflow_dispatch run would create a release" \
      "reproduce: sed -n '/^  publish:/,/^  [a-z]/p' .github/workflows/release.yml"
  fi

  if printf '%s\n' "$publish_block" | grep -q 'contents: write'; then
    ok "contents: write is declared on the publish job and nowhere above it"
  else
    fail "contents: write is declared on the publish job" \
      "reproduce: sed -n '/^  publish:/,/^  [a-z]/p' .github/workflows/release.yml"
  fi
fi

# ⛔ Least privilege: only the publishing job may write contents.
writers="$(awk '
  /^  [a-z_-]+:$/ { job = $0; sub(/:$/, "", job); sub(/^ +/, "", job) }
  /contents: write/ { print job }
' "$RELEASE" | LC_ALL=C sort -u | tr '\n' ' ')"
if [ "$writers" = "publish " ]; then
  ok "publish is the only job in release.yml with contents: write"
else
  fail "publish is the only job in release.yml with contents: write" \
    "jobs with it: ${writers:- none}" \
    "reproduce: grep -n 'contents: write' .github/workflows/release.yml"
fi

#---------------------------------------------------------------------------#
# 3. Every architecture in the build matrix is in the release matrix.
#
# ⛔ Discovered from build-deploy.yml, which is the authority on the set.
#---------------------------------------------------------------------------#
arches="$(awk '
  /^[[:space:]]*-[[:space:]]+docker_arch:/ {
    s = $0; sub(/^[^:]*:[[:space:]]*/, "", s); sub(/[[:space:]]*$/, "", s); print s
  }' "$BUILD_WF" | tr -d '\r' | LC_ALL=C sort -u)"
n_arches="$(awk 'NF { n++ } END { print n + 0 }' <<< "$arches")"

release_arches="$(awk '
  /^[[:space:]]*-[[:space:]]+docker_arch:/ {
    s = $0; sub(/^[^:]*:[[:space:]]*/, "", s); sub(/[[:space:]]*$/, "", s); print s
  }' "$RELEASE" | tr -d '\r' | LC_ALL=C sort -u)"

if [ "$n_arches" -lt 1 ]; then
  fail "the build matrix names its architectures" \
    "reproduce: grep -n docker_arch .github/workflows/build-deploy.yml"
elif [ "$arches" = "$release_arches" ]; then
  ok "the release matrix names the same $n_arches architectures as the build matrix"
else
  fail "the release matrix names the same architectures as the build matrix" \
    "build:   $(printf '%s' "$arches" | tr '\n' ' ')" \
    "release: $(printf '%s' "$release_arches" | tr '\n' ' ')" \
    "an architecture in one and not the other publishes a release with a hole in it" \
    "reproduce: grep -n docker_arch .github/workflows/build-deploy.yml .github/workflows/release.yml"
fi

# The completeness check in the publish job must read the matrix rather than
# carry its own list.
if grep -q "docker_arch:/" "$RELEASE"; then
  ok "the completeness check reads the architecture set from the build matrix"
else
  fail "the completeness check reads the architecture set from the build matrix" \
    "a written-down list stops matching the day an architecture is added" \
    "reproduce: grep -n 'build-deploy.yml' .github/workflows/release.yml"
fi

#---------------------------------------------------------------------------#
# 4. The generators, run against fixtures.
#---------------------------------------------------------------------------#
cat > "$work/ev.json" <<'EV'
{
  "image": "release:amd64",
  "platform": "linux/amd64",
  "digest": "sha256:aaaa",
  "built": "2026-08-29T00:00:00Z",
  "source_commit": "cccc",
  "version_id": "2026.08.29",
  "architecture": "x86_64",
  "docker_architecture": "amd64",
  "anchor": { "name": "pacman", "version": "7.1.0.r9.g54d9411-2" },
  "packages": [
    { "name": "zlib", "version": "1.3.1-2", "size": 100, "installed_size": 200, "sha256": "aa", "released": "2026-01-01" },
    { "name": "bash", "version": "5.3-1", "size": 300, "installed_size": 400, "sha256": "-", "released": "2026-01-02" }
  ],
  "package_count": 2
}
EV

if "$BSET" "$work/ev.json" "$work/set.txt" > /dev/null 2>&1; then
  lines="$(awk '!/^#/ && NF { n++ } END { print n + 0 }' "$work/set.txt")"
  unhashed="$(awk '/^# without a sha256/ { print $NF }' "$work/set.txt")"
  if [ "$lines" = 2 ] && [ "$unhashed" = 1 ]; then
    ok "gen-bootstrap-set writes one line per package and counts the unhashed ones"
  else
    fail "gen-bootstrap-set writes one line per package and counts the unhashed ones" \
      "got $lines package lines and $unhashed unhashed, expected 2 and 1" \
      "reproduce: scripts/gen-bootstrap-set <evidence.json> /tmp/set.txt"
  fi
  # ⛔ Sorted under LC_ALL=C, so two runs of one build are byte identical and a
  # diff between two releases is readable.
  if [ "$(awk '!/^#/ && NF { print $1 }' "$work/set.txt" | LC_ALL=C sort -c 2>&1)" = "" ]; then
    ok "gen-bootstrap-set output is sorted by package name"
  else
    fail "gen-bootstrap-set output is sorted by package name" \
      "reproduce: awk '!/^#/ && NF { print \$1 }' /tmp/set.txt | LC_ALL=C sort -c"
  fi
else
  fail "gen-bootstrap-set turns an evidence file into a package set" \
    "reproduce: scripts/gen-bootstrap-set <evidence.json> /tmp/set.txt"
fi

# ⛔ The header must agree with the body. gen-bootstrap-set counts what it wrote
# rather than what it meant to write, and this is that assertion from outside.
header_count="$(awk '/^# packages / { print $3 }' "$work/set.txt")"
body_count="$(awk '!/^#/ && NF { n++ } END { print n + 0 }' "$work/set.txt")"
if [ "$header_count" = "$body_count" ]; then
  ok "the bootstrap set header count matches the lines in it"
else
  fail "the bootstrap set header count matches the lines in it" \
    "header says $header_count, the file holds $body_count" \
    "a header saying 137 above a file holding 12 lines reads as complete" \
    "reproduce: awk '/^# packages /' /tmp/set.txt; awk '!/^#/ && NF' /tmp/set.txt | wc -l"
fi

# An evidence file with no packages is refused.
if jq '.package_count = 0 | .packages = []' "$work/ev.json" > "$work/empty.json" 2>/dev/null; then
  if "$BSET" "$work/empty.json" "$work/empty.txt" > /dev/null 2>&1; then
    fail "gen-bootstrap-set refuses an evidence file with no packages" \
      "it exited 0 and wrote a set describing an empty root" \
      "reproduce: jq '.package_count = 0' ev.json > e.json; scripts/gen-bootstrap-set e.json /tmp/o"
  else
    ok "gen-bootstrap-set refuses an evidence file with no packages"
  fi
fi

# gen-manifest reads the alias table from scripts/tag-names rather than
# repeating it, and recognises all three tag shapes.
printf 'latest\nv2030.01.01\nx86_64\naarch64-v2030.01.01\nppc64le-7.1.0.r9.g54d9411-2.2\npowerpc64le\n' \
  > "$work/tags.txt"
if MANIFEST_TAGS_FILE="$work/tags.txt" "$MANIFEST" ghcr.io/x/y "$work/m.json" > /dev/null 2>&1; then
  got="$(jq -r '[.tags[] | select(.docker_architecture != null) | .tag] | sort | join(" ")' "$work/m.json")"
  want="aarch64-v2030.01.01 powerpc64le ppc64le-7.1.0.r9.g54d9411-2.2 x86_64"
  if [ "$got" = "$want" ]; then
    ok "gen-manifest assigns an architecture to every per architecture tag shape"
  else
    fail "gen-manifest assigns an architecture to every per architecture tag shape" \
      "got:  $got" \
      "want: $want" \
      "⚠ the rolling, dated and anchor shapes share a prefix and all three are per architecture" \
      "reproduce: MANIFEST_TAGS_FILE=<file> scripts/gen-manifest ghcr.io/x/y /tmp/m.json"
  fi

  anchors="$(jq -r '[.tags[] | select(.anchor != null) | .tag] | sort | join(" ")' "$work/m.json")"
  if [ "$anchors" = "ppc64le-7.1.0.r9.g54d9411-2.2" ]; then
    ok "gen-manifest reads an anchor only from the anchor tag shape"
  else
    fail "gen-manifest reads an anchor only from the anchor tag shape" \
      "tags with an anchor: ${anchors:-none}" \
      "⚠ aarch64-v2030.01.01 and aarch64-7.1.0.r9.g54d9411-2 share a prefix and only the second is an anchor" \
      "reproduce: MANIFEST_TAGS_FILE=<file> scripts/gen-manifest ghcr.io/x/y /tmp/m.json"
  fi

  index="$(jq -r '[.tags[] | select(.docker_architecture == null) | .tag] | sort | join(" ")' "$work/m.json")"
  if [ "$index" = "latest v2030.01.01" ]; then
    ok "gen-manifest leaves the two index tags without an architecture"
  else
    fail "gen-manifest leaves the two index tags without an architecture" \
      "got: ${index:-none}" \
      "reproduce: MANIFEST_TAGS_FILE=<file> scripts/gen-manifest ghcr.io/x/y /tmp/m.json"
  fi
else
  fail "gen-manifest runs against a tag list" \
    "reproduce: MANIFEST_TAGS_FILE=<file> scripts/gen-manifest ghcr.io/x/y /tmp/m.json"
fi

#---------------------------------------------------------------------------#
# 5. release-notes refuses a half present release.
#---------------------------------------------------------------------------#
mk_assets() {
  rm -rf "$work/a"
  mkdir -p "$work/a"
  printf 'binary\n' > "$work/a/pacman-static-amd64"
  jq -n '{arch:"amd64",elf_machine:"Advanced Micro Devices X86-64",size:1,
          sha256:"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
          reported_version:"Pacman v7.1.0",
          pacman_commit:"54d94116164b0b2202c6061c4a59c6f3e70820d8",
          pacman_describe_pinned:"7.1.0.r9.g54d9411"}' > "$work/a/pacman-static-amd64.json"
}

mk_assets
if "$NOTES" "$work/a" v0.0.0 > /dev/null 2>&1; then
  ok "release-notes writes a body for a binaries-only release"
else
  fail "release-notes writes a body for a binaries-only release" \
    "a release cut before the rootfs assets existed carries only binaries" \
    "reproduce: scripts/release-notes <dir> v0.0.0"
fi

mk_assets
printf 'x\n' | gzip > "$work/a/rootfs-amd64.tar.gz"
if "$NOTES" "$work/a" v0.0.0 > /dev/null 2>&1; then
  fail "release-notes refuses a rootfs with no evidence, package set or OCI archive" \
    "it wrote a body describing an incomplete release" \
    "reproduce: put only rootfs-amd64.tar.gz in a directory and run scripts/release-notes"
else
  ok "release-notes refuses a rootfs with no evidence, package set or OCI archive"
fi

mk_assets
rm -f "$work/a/pacman-static-amd64.json"
if "$NOTES" "$work/a" v0.0.0 > /dev/null 2>&1; then
  fail "release-notes refuses a binary with no evidence file" \
    "reproduce: remove one .json from an asset directory and run scripts/release-notes"
else
  ok "release-notes refuses a binary with no evidence file"
fi

# ⛔ A checksum file that lists itself cannot verify.
mk_assets
"$NOTES" "$work/a" v0.0.0 > /dev/null 2>&1 || true
if [ -f "$work/a/SHA256SUMS" ]; then
  if grep -q 'SHA256SUMS' "$work/a/SHA256SUMS"; then
    fail "SHA256SUMS does not list itself" \
      "reproduce: grep SHA256SUMS <dir>/SHA256SUMS"
  else
    ok "SHA256SUMS does not list itself"
  fi
else
  fail "release-notes writes SHA256SUMS into the asset directory" \
    "reproduce: scripts/release-notes <dir> v0.0.0 && ls <dir>/SHA256SUMS"
fi

#---------------------------------------------------------------------------#
# 6. Every gen-evidence call in a workflow names its container runtime.
#
# ⛔ The runner image carries both docker and podman, and gen-evidence's
# detection prefers podman. Every image in these workflows is built with docker
# and lives in docker's store, so podman does not find it and tries to pull the
# local tag from Docker Hub and quay.io:
#
#   Trying to pull docker.io/library/release:amd64...
#   Error: reading manifest amd64 in docker.io/library/release
#
# Measured in run 33211181473. build-deploy.yml already set it; three other
# workflows did not, and only one of them had ever run on an image built that
# way. ⚠ The failure is loud but it names a registry, so it reads as a network
# problem rather than as a runtime mix-up.
#---------------------------------------------------------------------------#
calls=0
unset_runtime=""
for wf in "$WF_DIR"/*.yml; do
  [ -e "$wf" ] || continue
  # ⚠ Comments are stripped, and a printf is skipped. Two freshness workflows
  # build their pull request body with printf and name the script inside it, in
  # backticks. That is prose a reader types, not a call this repository makes,
  # and counting it reports a missing runtime on a line that runs nothing.
  hits="$(awk '
    { line = $0; sub(/(^|[[:space:]])#.*$/, "", line) }
    line ~ /printf/ { next }
    line ~ /scripts.gen-evidence/ { print NR }
  ' "$wf")"
  while IFS= read -r lineno; do
    [ -n "$lineno" ] || continue
    calls=$((calls + 1))
    # The runtime may be set on the same command, on a continued line above it,
    # or in the step's env: block. All three are covered by reading the 25 lines
    # before the call.
    #
    # ⛔ Comments are stripped here too. Each of these calls now carries a
    # comment above it explaining why the runtime is set, and a lookback that
    # reads comments is satisfied by the explanation rather than by the setting.
    # That is the same defect twice in one file: prose read as configuration.
    if ! awk -v n="$lineno" '
           NR >= n - 25 && NR <= n {
             line = $0
             sub(/(^|[[:space:]])#.*$/, "", line)
             print line
           }' "$wf" | grep -q 'CONTAINER_RUNTIME'; then
      unset_runtime="$unset_runtime $(basename "$wf"):$lineno"
    fi
  done <<< "$hits"
done

if [ "$calls" -eq 0 ]; then
  fail "at least one workflow runs scripts/gen-evidence" \
    "the scan found none, so this asserted nothing" \
    "reproduce: grep -n 'scripts/gen-evidence' .github/workflows/*.yml"
elif [ -z "$unset_runtime" ]; then
  ok "all $calls gen-evidence calls in workflows set CONTAINER_RUNTIME"
else
  fail "all $calls gen-evidence calls in workflows set CONTAINER_RUNTIME" \
    "without it:$unset_runtime" \
    "⛔ the runner has podman and docker, and the image is only in docker's store" \
    "reproduce: grep -n -B25 'scripts/gen-evidence' .github/workflows/*.yml"
fi

summary
