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

# The other three architectures. Running these on a different host
# architecture needs QEMU, which docker/setup-qemu-action installs in CI and
# `docker run --privileged --rm tonistiigi/binfmt --install all` installs
# locally.
docker pull "$IMAGE:aarch64"
docker pull "$IMAGE:armv7h"
docker pull "$IMAGE:riscv64"

# A per-architecture tag is a single manifest, so --platform is not needed to
# select it. It is still needed to run a foreign architecture.
docker run --rm --platform=linux/arm64 "$IMAGE:aarch64" uname -m
