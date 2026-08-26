#!/usr/bin/env bash
#
# Read the evidence file for a build.
#
# Each build publishes one evidence file per platform as a workflow artifact,
# named evidence-<docker arch>.json. It records what was in the image without
# needing the image: every package, its version, its download size, its
# installed size, its sha256 and its build date.
#
# Download the artifact for a run with:
#   gh run download <run-id> --repo pkgforge-dev/docker-archlinux --pattern 'evidence-*'
#
# Or generate one locally against any image:
#   scripts/gen-evidence amd64 ghcr.io/pkgforge-dev/archlinux:x86_64 linux/amd64 evidence-amd64.json
set -euo pipefail

EVIDENCE="${EVIDENCE:-evidence-amd64.json}"

# What was built, from what, and when.
jq '{image, platform, digest, built, source_commit, version_id, architecture, package_count}' "$EVIDENCE"

# The anchor, which is the pacman version the pinned tag family is named after.
jq -r '.anchor | "\(.name) \(.version)"' "$EVIDENCE"

# Every package, newest build first.
jq -r '.packages | sort_by(.released) | reverse | .[] | "\(.released)  \(.name) \(.version)"' "$EVIDENCE"

# Total download size and installed size.
jq -r '[.packages[].size] | add | "download bytes: \(.)"' "$EVIDENCE"
jq -r '[.packages[].installed_size] | add | "installed bytes: \(.)"' "$EVIDENCE"

# Is a specific package present, and at what version?
jq -r '.packages[] | select(.name == "openssl") | "\(.name) \(.version) \(.sha256)"' "$EVIDENCE"

# Diff two builds: what changed between them.
#   jq -r '.packages[] | "\(.name) \(.version)"' evidence-old.json | sort > /tmp/old
#   jq -r '.packages[] | "\(.name) \(.version)"' evidence-amd64.json | sort > /tmp/new
#   diff /tmp/old /tmp/new

# ⚠ A field upstream does not publish is written as a dash, never guessed.
# These are the entries to treat as unknown rather than as zero.
jq -r '[.packages[] | select(.released == "-" or .sha256 == "-")] | length' "$EVIDENCE"

# Verify a package you downloaded separately matches what the build recorded.
#   want="$(jq -r '.packages[] | select(.name == "bash") | .sha256' "$EVIDENCE")"
#   got="$(sha256sum bash-*.pkg.tar.zst | cut -d' ' -f1)"
#   [ "$want" = "$got" ]
