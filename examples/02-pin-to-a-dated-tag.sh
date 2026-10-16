#!/usr/bin/env bash
#
# Pin a build, so that it does not move.
#
# Four things never move after they are published: a dated index tag, a
# dated tag of one port, an anchor tag of one port, and a digest. latest and
# the tags of a port with no suffix move with each build.
#
# DATE is the date of a published index tag. With no DATE, the script takes
# the newest one from manifest.json of the newest release.
#
# Run this on the host.
set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/pkgforge-dev/archlinux}"
MANIFEST_URL="${MANIFEST_URL:-https://github.com/pkgforge-dev/docker-archlinux/releases/latest/download/manifest.json}"

if [ -z "${DATE:-}" ]; then
  DATE="$(curl -sSfL --connect-timeout 15 --max-time 120 "$MANIFEST_URL" |
    jq -r '[.tags[].tag | select(test("^v[0-9]{4}\\.[0-9]{2}\\.[0-9]{2}$"))] | sort | last | ltrimstr("v")')"
fi
echo "date: $DATE"

# A dated index tag. It resolves per platform, as latest does, and never moves.
docker pull "$IMAGE:v$DATE"

# A dated tag of one port.
docker pull --platform=linux/amd64 "$IMAGE:x86_64-v$DATE"

# The pacman version of that build. The anchor tag <tag>-<anchor> names the
# first image with this version.
anchor="$(docker run --rm --platform=linux/amd64 "$IMAGE:x86_64-v$DATE" pacman -Q pacman | awk '{ print $2 }')"
echo "anchor tag: $IMAGE:x86_64-$anchor"

# The digest is the content. No tag can point it at other bytes.
digest="$(docker buildx imagetools inspect "$IMAGE:v$DATE" --format '{{ .Manifest.Digest }}')"
echo "$IMAGE@$digest"
docker pull "$IMAGE@$digest"

# In a Dockerfile, pin by digest for the same reason.
echo "FROM $IMAGE@$digest"
