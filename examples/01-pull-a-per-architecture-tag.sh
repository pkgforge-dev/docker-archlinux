#!/usr/bin/env bash
#
# Pull the image of one port, not the multi-platform index.
#
# The tags of one port name one manifest. So the two pulls below get one
# digest.
#
# Run this on the host.
set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/pkgforge-dev/archlinux}"

# The uname -m name of the port.
docker pull --platform=linux/amd64 "$IMAGE:x86_64"

# The Docker name of the same port. The same manifest.
docker pull --platform=linux/amd64 "$IMAGE:amd64"

# One digest under two names.
docker image inspect "$IMAGE:x86_64" --format '{{ index .RepoDigests 0 }}'
docker image inspect "$IMAGE:amd64" --format '{{ index .RepoDigests 0 }}'

# The platforms of the index, with the attestation entries left out.
docker buildx imagetools inspect "$IMAGE:latest" --raw |
  jq -r '.manifests[].platform
         | select(.os != "unknown")
         | .os + "/" + .architecture + (if .variant then "/" + .variant else "" end)'

# ⚠ A tag of one port is an index with one platform, so the runtime still
# matches on platform. A pull of a foreign port with no --platform fails:
#
#   docker pull ghcr.io/pkgforge-dev/archlinux:aarch64      # on an x86_64 host
#   no image found in image index for architecture "amd64", variant "", OS "linux"
#
# ⚠ A container of a foreign port needs a user mode emulator in binfmt_misc
# on the host. In a clone of this repository, scripts/binfmt-register ARCH
# registers one from images pinned by digest.
docker pull --platform=linux/arm64 "$IMAGE:aarch64"
docker run --rm --platform=linux/arm64 "$IMAGE:aarch64" uname -m      # aarch64
