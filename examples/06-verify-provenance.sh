#!/usr/bin/env bash
#
# Verify what built an image.
#
# Every build attaches a provenance attestation and an SBOM to the pushed
# manifest. They are stored as extra manifests in the index, which is why
# `imagetools inspect --raw` on an index shows entries whose platform is
# unknown/unknown.
set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/pkgforge-dev/archlinux:latest}"

# The index, including the attestation manifests.
docker buildx imagetools inspect "$IMAGE" --raw

# Just the platforms, with the attestation entries filtered out.
docker buildx imagetools inspect "$IMAGE" --raw \
  | jq -r '.manifests[].platform
           | select(.os != "unknown")
           | .os + "/" + .architecture + (if .variant then "/" + .variant else "" end)'

# The provenance for one platform: which repository, which commit, which
# workflow, and which builder.
docker buildx imagetools inspect "$IMAGE" --format '{{ json .Provenance }}' | jq .

# The source commit, cross-checked against the label the image carries.
docker buildx imagetools inspect "$IMAGE" --format '{{ json .Provenance }}' \
  | jq -r '.. | .["https://github.com/Attestations/GitHubHostedRunner@v1"]? // empty'
docker image inspect "$IMAGE" --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}'

# The SBOM, listing what the build recorded as present.
docker buildx imagetools inspect "$IMAGE" --format '{{ json .SBOM }}' | jq -r '.SPDX.packages | length'

# The labels are the quickest cross-check and need no attestation support.
docker image inspect "$IMAGE" --format '{{ json .Config.Labels }}' | jq .
