#!/usr/bin/env bash
#
# Read the evidence file of an image.
#
# The evidence file of a port names each package in the image: its version,
# its download size, its installed size, its sha256 and its build date. A
# reader can then tell what is in an image without the image.
#
# Get it from one of these places:
#   the status site, the newest one of each port:
#     curl -sSfL --connect-timeout 15 --max-time 120 -o evidence-amd64.json \
#       https://pkgforge-dev.github.io/docker-archlinux/evidence/amd64.json
#   the artifact evidence-<arch> of a build run (rootfs-<arch>.json in it):
#     gh run download <run-id> --repo pkgforge-dev/docker-archlinux --pattern 'evidence-*'
#   the release asset rootfs-<arch>.json
#   a clone of this repository, for any image:
#     scripts/gen-evidence amd64 ghcr.io/pkgforge-dev/archlinux:x86_64 linux/amd64 evidence-amd64.json
#
# Run this on the host.
set -euo pipefail

EVIDENCE="${EVIDENCE:-evidence-amd64.json}"

# What was built, from what, and when.
jq '{image, platform, digest, built, source_commit, version_id, architecture, package_count}' "$EVIDENCE"

# The anchor: the pacman version that names the anchor tag.
jq -r '.anchor | "\(.name) \(.version)"' "$EVIDENCE"

# Each package, newest build first.
jq -r '.packages | sort_by(.released) | reverse | .[] | "\(.released)  \(.name) \(.version)"' "$EVIDENCE"

# ⚠ A value that upstream does not publish is a dash, never a guess. Count
# each such entry, and add only the sizes that are numbers.
jq -r '[.packages[] | select(.released == "-" or .sha256 == "-" or .size == "-")] | length' "$EVIDENCE"
jq -r '[.packages[].size | numbers] | add // 0 | "download bytes: \(.)"' "$EVIDENCE"
jq -r '[.packages[].installed_size | numbers] | add // 0 | "installed bytes: \(.)"' "$EVIDENCE"

# One package, and its version.
jq -r '.packages[] | select(.name == "openssl") | "\(.name) \(.version) \(.sha256)"' "$EVIDENCE"

# The difference between two builds:
#   jq -r '.packages[] | "\(.name) \(.version)"' evidence-old.json | sort > /tmp/old
#   jq -r '.packages[] | "\(.name) \(.version)"' evidence-amd64.json | sort > /tmp/new
#   diff /tmp/old /tmp/new

# Compare a package that you downloaded with what the build recorded:
#   want="$(jq -r '.packages[] | select(.name == "bash") | .sha256' "$EVIDENCE")"
#   got="$(sha256sum bash-*.pkg.tar.zst | cut -d' ' -f1)"
#   [ "$want" = "$got" ]
