#!/usr/bin/env bash
#
# Every path pacman lists is on disk.
#
# This image ships no NoExtract rule, so a package's file list and the
# filesystem agree. That matters for any tool that walks `pacman -Ql` and checks
# each path, which is how the difference was found: an earlier build withheld
# documentation and a downstream consumer failed on the first missing path.
# See HISTORY/noextract-reverted.md.
#
# Run this inside the container.
set -euo pipefail

# 1. Everything the base install claims is there.
missing=0
while read -r p; do
  [ -e "$p" ] || { printf 'missing: %s\n' "$p"; missing=$((missing + 1)); }
done < <(pacman -Qlq)
printf 'paths listed : %s\n' "$(pacman -Qlq | wc -l)"
printf 'missing      : %s\n' "$missing"

# 2. The same holds for a package installed afterwards. qt6-base ships 167
#    paths under /usr/share/doc and is what the report was about.
pacman -Sy --noconfirm --needed qt6-base
pacman -Qlq qt6-base | while read -r p; do
  [ -e "$p" ] || printf 'missing: %s\n' "$p"
done
ls -l /usr/share/doc/qt6/global/template/images/Qt-logo.png

# 3. Man pages and info pages are present too.
find /usr/share/man -type f | wc -l
find /usr/share/info -type f | wc -l
