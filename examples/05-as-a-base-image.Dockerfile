# Use the image as a base.
#
# Build with:
#   docker build -f examples/05-as-a-base-image.Dockerfile -t myapp .
#
# Cross-architecture, with QEMU available:
#   docker build --platform linux/arm64 -f examples/05-as-a-base-image.Dockerfile -t myapp .

# Pin by digest, not by tag. A tag moves; a digest is the content.
# Resolve one with:
#   docker buildx imagetools inspect ghcr.io/pkgforge-dev/archlinux:v2026.05.15 --format '{{ .Manifest.Digest }}'
FROM ghcr.io/pkgforge-dev/archlinux:latest

# The package database is not shipped, because it is rebuilt on first use and
# would be stale by the time anyone pulled the image. Sync before installing.
RUN pacman -Sy --noconfirm --needed git base-devel \
    && rm -rf /var/cache/pacman/pkg/*

# Signature checking is on and stays on. If a package fails to verify, the key
# is missing rather than the check being wrong:
#   pacman -S --noconfirm archlinux-keyring && pacman-key --populate
#
# ⛔ SigLevel = Never is not the fix.

# Man pages, documentation and non-English locales are not extracted. If your
# image needs them, undo the rule and reinstall. See 03 and 04.

WORKDIR /work
CMD ["/usr/bin/bash"]
