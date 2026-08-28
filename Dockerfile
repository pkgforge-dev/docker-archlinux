#------------------------------------------------------------------------------------#
## Bootstrap
#
# This stage runs on the builder's own architecture and tells pacman which
# architecture to install for, so the packages are the target's and nothing here
# is emulated. It starts from official Arch pinned by digest, never from an image
# this repository publishes, so a build does not inherit the previous build's
# defects and can be reproduced without trusting this project's own output.
#------------------------------------------------------------------------------------#
# scripts/check-image-pins reads the marker below and compares this digest
# against what that tag resolves to now. A Dockerfile instruction takes no
# trailing comment, so the marker sits on its own line directly above.
# tag: latest
FROM --platform=$BUILDPLATFORM docker.io/library/archlinux@sha256:b860afd5823683f7ea389ba5f00d812f4fe55f6f286dea329d2abeefa535e309 AS bootstrap

ARG TARGETARCH
ARG TARGETVARIANT
ARG IMAGE_VERSION

COPY bootstrap/any /
COPY bootstrap/${TARGETARCH}${TARGETVARIANT} /
COPY bootstrap/keyrings /usr/local/share/docker-archlinux/keyrings

# pacman -r reads /etc/pacman.conf from the running host, never from the target
# root, so the per architecture config has to be installed here. It carries
# Architecture, the mirrors and NoExtract, which is what makes all three take
# effect during the bootstrap.
COPY rootfs/${TARGETARCH}${TARGETVARIANT}/etc /etc

# The same files ship in the image, so a consumer reads and changes the config
# that actually built it.
COPY rootfs/any /rootfs
COPY rootfs/${TARGETARCH}${TARGETVARIANT} /rootfs

# Arch Linux ARM and the loong64 port sign with keys archlinux-keyring does not
# carry. This trusts them from a pinned set of fingerprints and expiry dates,
# which is what lets SigLevel stay Required. An architecture no pin serves,
# amd64 and riscv64, exits 0 without touching the keyring.
RUN install-port-keyring

# bootstrap/<arch>/etc/bootstrap-packages.txt is one package name per line and
# carries no comments, because xargs has no comment syntax: a leading # would
# arrive as a package named "#". tests/static/90-package-lists.sh enforces that.
RUN <<EOS
  set -eu
  if [ ! -s /etc/bootstrap-packages.txt ]; then
    echo "bootstrap: /etc/bootstrap-packages.txt is empty or missing" >&2
    exit 1
  fi
  xargs -r -a /etc/bootstrap-packages.txt pacstrap-docker /rootfs
EOS

# ⛔ The databases pacstrap resolved against, copied out before the next step
# empties the directory. Order is the whole point: after the delete this would
# export nothing and every later check would still pass.
#
# scripts/gen-evidence reads these rather than fetching its own. A package
# superseded upstream between this build and the evidence run is installed here
# and absent from every current database, and evidence with a hole in it is
# worse than none. HISTORY/evidence-race.md.
#
# This is its own layer, ahead of the one that uses IMAGE_VERSION, so the
# snapshot is cached with the install rather than with the version string.
#
# /dbsnapshot is outside /rootfs and the image stage copies /rootfs only, so the
# image carries nothing new. Measured: the same 33086 paths and the same 137
# packages before and after. HISTORY/evidence-race.md.
RUN <<EOS
  set -eu
  mkdir -p /dbsnapshot
  cp -a /rootfs/var/lib/pacman/sync/*.db /dbsnapshot/
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
## The databases the bootstrap resolved against
#
# Built only with --target dbsnapshot. Nothing in the image stage depends on it,
# so an ordinary build never materialises it and the image is unaffected.
#
# The build job exports it with --output type=local and hands the directory to
# scripts/gen-evidence as DB_SNAPSHOT. That is what removes the race between
# what the build installed and what the repositories carry minutes later.
#------------------------------------------------------------------------------------#
FROM scratch AS dbsnapshot

COPY --from=bootstrap /dbsnapshot /

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
## Machine identity
# systemd's post_install runs systemd-machine-id-setup, so the bootstrap leaves a
# real machine ID behind and every container from one published tag would carry
# the same one. machine-id(5) asks an image for an empty file: the container
# provisions its own on start, and sd_id128_get_machine_app_specific derives
# application identifiers from it, so a shared value is a shared seed.
#
# The file stays. Removing it is its own defect, measured in
# HISTORY/defect-parity.md, and tests/image/60-defect-parity.sh asserts both
# halves: present, and empty.
#------------------------------------------------------------------------------------#
RUN <<EOS
  set -eu
  : > /etc/machine-id
  # A truncate that silently did nothing would leave the ID in the image and
  # still report success.
  [ ! -s /etc/machine-id ]
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
