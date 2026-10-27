#------------------------------------------------------------------------------------#
## Bootstrap
#
# This stage runs on the architecture of the builder. pacman installs the
# packages of the target architecture into /rootfs. The stage starts from the
# official Arch Linux image, pinned by digest, and never from an image of this
# repository.
#
# Build arguments:
#   BASE_IMAGE     the image of this stage. The build job can give the same
#                  digest from another registry, for example mirror.gcr.io.
#   TRANSPORT      worker or oci: the path to the GHCR mirror (scripts/pick-transport)
#   SKIP_SERVERS   LIST=SERVER pairs: servers the build does not read
#                  (scripts/check-mirror-lag)
#   IMAGE_VERSION  the version label, and VERSION_ID and IMAGE_VERSION of
#                  /etc/os-release
#   SOURCE_COMMIT, BUILD_DATE   the revision and created labels
# With no build argument (TRANSPORT=worker, SKIP_SERVERS empty), the build
# stage reads each list as rootfs/<arch> has it. The GHCR mirror is first,
# through the Worker. pacman reads each server after it directly.
#------------------------------------------------------------------------------------#
# scripts/check-image-pins reads the marker on the line above the pin.
# tag: latest
ARG BASE_IMAGE=docker.io/library/archlinux:latest@sha256:e82623936fa1a69700b48e98b058df6eaab18b737c27473a7234a40fdecb9413

FROM --platform=$BUILDPLATFORM ${BASE_IMAGE} AS bootstrap

ARG TARGETARCH
ARG TARGETVARIANT
ARG IMAGE_VERSION

COPY bootstrap/any /
COPY bootstrap/${TARGETARCH}${TARGETVARIANT} /
COPY bootstrap/keyrings /usr/local/share/docker-archlinux/keyrings

# pacman -r reads /etc/pacman.conf of this stage, never the one in the target
# root. So the config of the port goes to /etc of this stage too: it sets
# Architecture, the lists and SigLevel. It has no NoExtract rule.
COPY rootfs/${TARGETARCH}${TARGETVARIANT}/etc /etc

# The image ships the same files, so a consumer reads the config that built it.
COPY rootfs/any /rootfs
COPY rootfs/${TARGETARCH}${TARGETVARIANT} /rootfs

# ⛔ The next two steps change the config of this stage only, never /rootfs.
# With TRANSPORT=oci, pacman-oci reads the GHCR mirror from the registry, and
# the oci:// server is first in each list. Each SKIP_SERVERS pair removes one
# server from one list. The image ships every server, because a mirror that is
# behind follows upstream again after its next sync.
ARG TRANSPORT=worker
RUN use-transport "${TRANSPORT}"

ARG SKIP_SERVERS=""
RUN drop-server --pairs /etc/pacman.d "${SKIP_SERVERS}"

# Arch Linux ARM, the loong64 port and ArchPOWER sign with keys that
# archlinux-keyring does not have. This installs them from a pin in
# bootstrap/keyrings, so SigLevel stays Required. A port with no pin
# (amd64, riscv64) does not change the keyring.
RUN install-port-keyring

# bootstrap/<arch>/etc/bootstrap-packages.txt has one package name on each
# line and no comment: xargs gives a "#" to pacman as a package name.
# tests/static/90-package-lists.sh checks the lists.
RUN <<EOS
  set -eu
  if [ ! -s /etc/bootstrap-packages.txt ]; then
    echo "bootstrap: /etc/bootstrap-packages.txt is empty or missing" >&2
    exit 1
  fi
  xargs -r -a /etc/bootstrap-packages.txt pacstrap-docker /rootfs
EOS

# ⛔ Copy the databases that pacstrap used before the next step empties the
# directory. After the delete, this copies nothing.
#
# scripts/gen-evidence reads this copy, not a new download: a package can leave
# the repositories between the build and the evidence.
#
# /dbsnapshot is outside /rootfs, and the image stage copies only /rootfs, so the
# image does not change. This is a layer of its own before the layer that uses
# IMAGE_VERSION.
RUN <<EOS
  set -eu
  mkdir -p /dbsnapshot
  cp -a /rootfs/var/lib/pacman/sync/*.db /dbsnapshot/
EOS

RUN <<EOS
  set -eu
  # No package owns /etc/os-release, so the build writes it.
  write-os-release /rootfs "${IMAGE_VERSION}"
  # The first pacman -Sy of a consumer gets new databases. The directory stays,
  # as in the official image.
  find /rootfs/var/lib/pacman/sync -mindepth 1 -delete
EOS

#------------------------------------------------------------------------------------#
## The databases that the bootstrap used
#
# Built only with --target dbsnapshot. The image stage does not use it.
# The build job exports it with --output type=local and gives the directory to
# scripts/gen-evidence as DB_SNAPSHOT.
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
## pacman-key
# The image has the pacman keyring and no local signing key (lsign key), as the
# official image.
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
## Machine ID
# The post_install of systemd writes a machine ID. Each container from one tag
# would then have the same ID. machine-id(5) asks an image for an empty file:
# the container writes its own ID when it starts.
#
# The file stays, and it is empty. tests/image/60-defect-parity.sh checks both.
#------------------------------------------------------------------------------------#
RUN <<EOS
  set -eu
  : > /etc/machine-id
  # Stop when the file still has content.
  [ ! -s /etc/machine-id ]
EOS

#------------------------------------------------------------------------------------#
## Locale
# locale.conf and locale.gen come from rootfs/any, so only locale-gen runs here.
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
## Labels
#------------------------------------------------------------------------------------#
LABEL org.opencontainers.image.title="archlinux"
LABEL org.opencontainers.image.description="Multi-platform Arch Linux container images"
LABEL org.opencontainers.image.source="https://github.com/pkgforge-dev/docker-archlinux"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.version="${IMAGE_VERSION}"
LABEL org.opencontainers.image.revision="${SOURCE_COMMIT}"
LABEL org.opencontainers.image.created="${BUILD_DATE}"

#------------------------------------------------------------------------------------#
## Command
#------------------------------------------------------------------------------------#
CMD ["/usr/bin/bash"]
