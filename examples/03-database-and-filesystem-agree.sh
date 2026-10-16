#!/usr/bin/env bash
#
# Check that every path that pacman lists is on disk.
#
# The image has no NoExtract rule, so the file list of each package and the
# file system agree. A tool that walks `pacman -Ql` and checks each path then
# finds each one.
#
# ⚠ One listed path is absent: /var/lock, a link to ../run/lock. systemd
# makes /run/lock, and a container does not run systemd.
#
# Run this inside the container.
set -euo pipefail

# 1. Each path of the installed packages is there.
missing=0
while read -r p; do
  [ -e "$p" ] || { printf 'missing: %s\n' "$p"; missing=$((missing + 1)); }
done < <(pacman -Qlq)
printf 'paths listed : %s\n' "$(pacman -Qlq | wc -l)"
printf 'missing      : %s\n' "$missing"

# 2. The same for a package installed later. qt6-base has documentation
#    under /usr/share/doc.
pacman -Syu --noconfirm --needed qt6-base
pacman -Qlq qt6-base | while read -r p; do
  [ -e "$p" ] || printf 'missing: %s\n' "$p"
done
ls -l /usr/share/doc/qt6/global/template/images/Qt-logo.png

# 3. Man pages and info pages are there too.
find /usr/share/man -type f | wc -l
find /usr/share/info -type f | wc -l
