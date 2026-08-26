#!/usr/bin/env bash
#
# Bring back man pages, info pages and documentation.
#
# They are not deleted. They are never extracted, by the NoExtract lines in
# /etc/pacman.conf. Every package is installed normally and pacman still
# records every file it owns, so commenting the rule out and reinstalling
# restores them. Nothing here needs a different image.
#
# Run this inside the container.
set -euo pipefail

# Nothing to start with.
find /usr/share/man -type f | wc -l    # 0
find /usr/share/info -type f | wc -l   # 0
find /usr/share/doc -type f | wc -l    # 0

# 1. Stop excluding them.
sed -i 's|^NoExtract  = usr/share/man|#&|' /etc/pacman.conf
sed -i 's|^NoExtract  = usr/share/gtk-doc|#&|' /etc/pacman.conf

# 2. Reinstall. Everything already installed, so every page comes back.
# shellcheck disable=SC2046
# The word splitting is the point: pacman -Qq prints one package name per line
# and each has to arrive as its own argument.
pacman -Syu --noconfirm $(pacman -Qq)

find /usr/share/man -type f | wc -l    # thousands
find /usr/share/doc -type f | wc -l

# Just the man pages for one package is much faster than reinstalling
# everything, when that is all you need.
pacman -S --noconfirm coreutils
man --version

# The man-pages package itself is not installed by default and is where the
# section 2, 3 and 7 pages live.
pacman -S --noconfirm man-pages man-db
mandb
man ls
