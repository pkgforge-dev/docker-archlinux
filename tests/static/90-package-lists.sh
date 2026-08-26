#!/usr/bin/env bash
#
# The bootstrap package lists must hold package names and nothing else.
#
# The Dockerfile runs `xargs -r -a /etc/bootstrap-packages.txt pacstrap-docker`.
# xargs has no comment syntax, so a line beginning with # arrives as a package
# named "#" and the rest of the line as further package names. pacman then fails
# with "target not found: #", a long way from the file that caused it.
#
# There is one list per architecture and they legitimately differ: the two ARM
# ports need the Arch Linux ARM keyring and the other two do not.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

lists="$(find "$REPO_ROOT/bootstrap" -type f -name bootstrap-packages.txt | sort)"
if [ -z "$lists" ]; then
  fail "at least one bootstrap package list exists" "searched: $REPO_ROOT/bootstrap"
  summary
  exit 1
fi

# A pacman package name. Also allows a group name, which is what base is.
VALID='^[a-z0-9][a-z0-9@._+-]*$'

count=0
while IFS= read -r list; do
  [ -n "$list" ] || continue
  rel="${list#"$REPO_ROOT/"}"
  count=$((count + 1))

  if [ ! -s "$list" ]; then
    fail "$rel is not empty" "an empty list installs nothing and the image has no shell"
    continue
  fi

  bad=""
  n=0
  lineno=0
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    # A blank line is harmless: xargs drops it. Anything else must be a name.
    case "$line" in "") continue ;; esac
    n=$((n + 1))
    if ! printf '%s' "$line" | grep -qE "$VALID"; then
      bad="$bad $rel:$lineno($line)"
    fi
  done < "$list"

  if [ -n "$bad" ]; then
    fail "$rel holds only package names" \
      "not a package name:$bad" \
      "xargs has no comment syntax, so a # line becomes a package named #" \
      "reproduce: xargs -r -a $rel echo pacstrap-docker /rootfs"
  elif [ "$n" -eq 0 ]; then
    fail "$rel names at least one package" "the file has no non-blank line"
  else
    ok "$rel names $n package(s), all valid names"
  fi
done <<< "$lists"

# One list per architecture the build matrix covers. A missing one means an
# architecture builds with whatever the previous COPY left behind.
for arch in amd64 arm64 armv7 riscv64; do
  if [ -f "$REPO_ROOT/bootstrap/$arch/etc/bootstrap-packages.txt" ]; then
    ok "bootstrap/$arch/etc/bootstrap-packages.txt exists"
  else
    fail "bootstrap/$arch/etc/bootstrap-packages.txt exists" \
      "the build matrix has a $arch entry and there is no list for it"
  fi
done

# The two ARM ports need the Arch Linux ARM keyring in the target root, because
# the packages there are signed by a key archlinux-keyring does not carry.
for arch in arm64 armv7; do
  list="$REPO_ROOT/bootstrap/$arch/etc/bootstrap-packages.txt"
  [ -f "$list" ] || continue
  if grep -qxF 'archlinuxarm-keyring' "$list"; then
    ok "bootstrap/$arch names archlinuxarm-keyring"
  else
    fail "bootstrap/$arch names archlinuxarm-keyring" \
      "without it the image cannot verify its own updates after the build" \
      "reproduce: cat bootstrap/$arch/etc/bootstrap-packages.txt"
  fi
done

diag "checked $count package list(s)"
summary
