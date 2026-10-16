#!/usr/bin/env bash
#
# Read what built an image.
#
# Each build attaches a provenance attestation and an SBOM to the pushed
# image. They are more manifests in the index, with the platform
# unknown/unknown.
#
# Run this on the host.
set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/pkgforge-dev/archlinux:latest}"

# The index, with the attestation manifests.
docker buildx imagetools inspect "$IMAGE" --raw

# The platforms only, with the attestation entries left out.
docker buildx imagetools inspect "$IMAGE" --raw |
  jq -r '.manifests[].platform
         | select(.os != "unknown")
         | .os + "/" + .architecture + (if .variant then "/" + .variant else "" end)'

# The provenance of each platform: the repository, the commit, the workflow
# and the builder.
docker buildx imagetools inspect "$IMAGE" --format '{{ json .Provenance }}' | jq .

# The SBOM: the number of packages that the build recorded. For an index of
# more than one platform, such as latest, .SBOM is a map keyed by platform.
# For one platform it is the SBOM itself.
docker buildx imagetools inspect "$IMAGE" --format '{{ json .SBOM }}' |
  jq -r 'if has("SPDX") then "\(.SPDX.packages | length)"
         else to_entries[] | "\(.key) \(.value.SPDX.packages | length)" end'

# The labels need no attestation support. The revision is the source commit.
docker pull "$IMAGE"
docker image inspect "$IMAGE" --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}'
docker image inspect "$IMAGE" --format '{{ json .Config.Labels }}' | jq .
