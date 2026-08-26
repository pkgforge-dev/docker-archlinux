#!/usr/bin/env bash
#
# Pull one architecture rather than the multi-architecture index.
#
# Each architecture answers to more than one tag name and they share one
# manifest, so the two pulls below fetch the same digest.
set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/pkgforge-dev/archlinux}"

# The uname -m spelling.
docker pull "$IMAGE:x86_64"

# The Docker platform spelling. Same manifest.
docker pull "$IMAGE:amd64"

# They are one digest under two names.
docker image inspect "$IMAGE:x86_64" --format '{{ index .RepoDigests 0 }}'
docker image inspect "$IMAGE:amd64" --format '{{ index .RepoDigests 0 }}'

# ⚠ A per-architecture tag is not a bare manifest. `imagetools create` wraps
# even a single digest in an index, and the platform is recorded in it, so the
# runtime still matches on platform. Pulling a foreign architecture tag without
# --platform fails:
#
#   docker pull ghcr.io/pkgforge-dev/archlinux:aarch64      # on an x86_64 host
#   no image found in image index for architecture "amd64", variant "", OS "linux"
#
# So --platform is required for the other three on an x86_64 host, and QEMU has
# to be installed to run them:
#
#   docker run --privileged --rm tonistiigi/binfmt --install all
docker pull --platform=linux/arm64 "$IMAGE:aarch64"
docker pull --platform=linux/arm/v7 "$IMAGE:armv7h"
docker pull --platform=linux/riscv64 "$IMAGE:riscv64"

docker run --rm --platform=linux/arm64 "$IMAGE:aarch64" uname -m      # aarch64
docker run --rm --platform=linux/riscv64 "$IMAGE:riscv64" uname -m    # riscv64
