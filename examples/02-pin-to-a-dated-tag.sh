#!/usr/bin/env bash
#
# Pin a build so it does not move under you.
#
# Three things never move once published: a dated index tag, a dated
# single-architecture tag, and a digest. `latest` and the bare architecture
# names move on every build.
set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/pkgforge-dev/archlinux}"
DATE="${DATE:-2026.05.15}"

# A dated index tag. Resolves per platform, same as latest, but frozen.
docker pull "$IMAGE:v$DATE"

# A dated single-architecture tag.
docker pull "$IMAGE:x86_64-v$DATE"

# Pinned to the upstream pacman version that build contains, rather than to a
# date. Useful when what matters is the package set, not the build day.
docker run --rm "$IMAGE:v$DATE" pacman -Q pacman

# The strongest pin is the digest. It is the content, and no tag can be
# repointed at different bytes.
digest="$(docker buildx imagetools inspect "$IMAGE:v$DATE" --format '{{ .Manifest.Digest }}')"
echo "$IMAGE@$digest"
docker pull "$IMAGE@$digest"

# In a Dockerfile, pin by digest for the same reason.
echo "FROM $IMAGE@$digest"
