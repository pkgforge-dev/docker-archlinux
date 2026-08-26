#------------------------------------------------------------------------------------#
## Bootstrap
#
# This stage runs on the builder's own architecture and tells pacman which
# architecture to install for, so the packages are the target's and nothing here
# is emulated. It starts from official Arch pinned by digest, never from an image
# this repository publishes, so a build does not inherit the previous build's
# defects and can be reproduced without trusting this project's own output.
#------------------------------------------------------------------------------------#
FROM --platform=$BUILDPLATFORM docker.io/library/archlinux@sha256:b860afd5823683f7ea389ba5f00d812f4fe55f6f286dea329d2abeefa535e309 AS bootstrap

ARG TARGETARCH
ARG TARGETVARIANT
ARG IMAGE_VERSION

COPY bootstrap/any /
COPY bootstrap/${TARGETARCH}${TARGETVARIANT} /
COPY bootstrap/keyrings/archlinuxarm.pin /usr/local/share/docker-archlinux/archlinuxarm.pin

# pacman -r reads /etc/pacman.conf from the running host, never from the target
# root, so the per architecture config has to be installed here. It carries
# Architecture, the mirrors and NoExtract, which is what makes all three take
# effect during the bootstrap.
COPY rootfs/${TARGETARCH}${TARGETVARIANT}/etc /etc

# The same files ship in the image, so a consumer reads and changes the config
# that actually built it.
COPY rootfs/any /rootfs
COPY rootfs/${TARGETARCH}${TARGETVARIANT} /rootfs

# Arch Linux ARM signs with a key archlinux-keyring does not carry. This trusts
# it from a pinned fingerprint, which is what lets SigLevel stay Required.
RUN install-alarm-keyring

RUN <<EOS
  set -eu
  if [ ! -s /etc/bootstrap-packages.txt ]; then
    echo "bootstrap: /etc/bootstrap-packages.txt is empty or missing" >&2
    exit 1
  fi
  xargs -r -a /etc/bootstrap-packages.txt pacstrap-docker /rootfs
EOS

RUN <<EOS
  set -eu
  # No package owns /etc/os-release, so the build writes it.
  write-os-release /rootfs "${IMAGE_VERSION}"
  # The synced databases are rebuilt by the consumer's first pacman -Sy. The
  # directory stays, because that is what the published image has.
  find /rootfs/var/lib/pacman/sync -mindepth 1 -delete
EOS

#------------------------------------------------------------------------------------#
## The image
#------------------------------------------------------------------------------------#
FROM scratch

ARG IMAGE_VERSION
ARG SOURCE_COMMIT
ARG BUILD_DATE

COPY --from=bootstrap /rootfs /

#------------------------------------------------------------------------------------#
## Initialize
# Set up pacman-key without distributing the lsign key
# See https://gitlab.archlinux.org/archlinux/archlinux-docker/-/blob/301942f9e5995770cb5e4dedb4fe9166afa4806d/README.md#principles
# Source: https://gitlab.archlinux.org/archlinux/archlinux-docker/-/blob/301942f9e5995770cb5e4dedb4fe9166afa4806d/Makefile#L22
#------------------------------------------------------------------------------------#
RUN <<EOS
  set -eu
  pacman-key --init
  pacman-key --populate
  rm -rf /etc/pacman.d/gnupg/openpgp-revocs.d /etc/pacman.d/gnupg/private-keys-v1.d
  rm -f /etc/pacman.d/gnupg/pubring.gpg~
  find /etc/pacman.d/gnupg -maxdepth 1 -name 'S.gpg-agent*' -delete
EOS

#------------------------------------------------------------------------------------#
## Locale
# locale.conf and locale.gen ship from rootfs/any, so only the generation runs
# here. Appending the same lines again would put each entry in the file twice.
#------------------------------------------------------------------------------------#
RUN <<EOS
  set -eu
  echo "LC_ALL=en_US.UTF-8" >> /etc/environment
  locale-gen
  locale -a | grep -qx 'en_US.utf8'
EOS

ENV LANG="en_US.UTF-8"
ENV LANGUAGE="en_US:en"
ENV LC_ALL="en_US.UTF-8"

#------------------------------------------------------------------------------------#
## Provenance
#------------------------------------------------------------------------------------#
LABEL org.opencontainers.image.title="archlinux"
LABEL org.opencontainers.image.description="Multi-platform Arch Linux container images"
LABEL org.opencontainers.image.source="https://github.com/pkgforge-dev/docker-archlinux"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.version="${IMAGE_VERSION}"
LABEL org.opencontainers.image.revision="${SOURCE_COMMIT}"
LABEL org.opencontainers.image.created="${BUILD_DATE}"

#------------------------------------------------------------------------------------#
## Entrypoint
#------------------------------------------------------------------------------------#
CMD ["/usr/bin/bash"]
