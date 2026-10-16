# Use the image as a base image.
#
# Build with:
#   docker build -f examples/05-as-a-base-image.Dockerfile -t myapp .
#
# For another platform, with a user mode emulator on the host:
#   docker build --platform linux/arm64 -f examples/05-as-a-base-image.Dockerfile -t myapp .
#
# Pin by digest, not by tag. A tag moves; a digest is the content. Get the
# digest of the index that latest names now:
#   docker buildx imagetools inspect ghcr.io/pkgforge-dev/archlinux:latest --format '{{ .Manifest.Digest }}'
# Then write FROM ghcr.io/pkgforge-dev/archlinux@sha256:<digest>.
FROM ghcr.io/pkgforge-dev/archlinux:latest

# The image has no sync databases and no package cache. Sync and upgrade
# with the install, and empty the cache after it. ⚠ pacman -Sy with a
# package is a partial upgrade: the new package can need a newer library
# than the base image has.
RUN pacman -Syu --noconfirm --needed git base-devel \
    && find /var/cache/pacman/pkg -mindepth 1 -delete

# Signature checks are on. When a package does not verify, the key is
# missing; the check is not wrong:
#   pacman -Sy --noconfirm archlinux-keyring && pacman-key --populate
#
# ⛔ SigLevel = Never is not the fix.

# The image has every file of each package: man pages, documentation and
# every locale source. Generate a locale with locale-gen (see 04).

WORKDIR /work
CMD ["/usr/bin/bash"]
