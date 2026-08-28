#!/usr/bin/env bash
#
# The bootstrap package lists must hold package names and nothing else.
#
# The Dockerfile runs `xargs -r -a /etc/bootstrap-packages.txt pacstrap-docker`.
# xargs has no comment syntax, so a line beginning with # arrives as a package
# named "#" and the rest of the line as further package names. pacman then fails
# with "target not found: #", a long way from the file that caused it.
#
# There is one list per architecture and they legitimately differ: a port that
# signs with its own keyring names that keyring, and the ports Arch itself
# builds do not.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

lists="$(find "$REPO_ROOT/bootstrap" -type f -name bootstrap-packages.txt | sort)"
if [ -z "$lists" ]; then
  fail "at least one bootstrap package list exists" "searched: $REPO_ROOT/bootstrap" \
    "reproduce: ls bootstrap/*/etc/bootstrap-packages.txt"
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
    fail "$rel is not empty" "an empty list installs nothing and the image has no shell" \
      "reproduce: cat $rel"
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
    fail "$rel names at least one package" "the file has no non-blank line" \
      "reproduce: cat $rel"
  else
    ok "$rel names $n package(s), all valid names"
  fi
done <<< "$lists"

# One list per architecture the build matrix covers. A missing one means an
# architecture builds with whatever the previous COPY left behind.
for arch in amd64 arm64 armv7 loong64 riscv64 ppc ppc64 ppc64le; do
  if [ -f "$REPO_ROOT/bootstrap/$arch/etc/bootstrap-packages.txt" ]; then
    ok "bootstrap/$arch/etc/bootstrap-packages.txt exists"
  else
    fail "bootstrap/$arch/etc/bootstrap-packages.txt exists" \
      "the build matrix has a $arch entry and there is no list for it" \
      "reproduce: ls bootstrap/$arch/etc/bootstrap-packages.txt"
  fi
done

#---------------------------------------------------------------------------#
# A port that signs with its own keyring needs that keyring inside the target
# root as well as on the build host, because the image has to verify its own
# updates after the build.
#
# ⛔ Derived from bootstrap/keyrings/*.pin, not listed here. A sixth port is a
# new pin file, and this picks it up with no edit. That is also why there is no
# arch-subset marker: no line below names an architecture.
#---------------------------------------------------------------------------#
pin_field() { # FILE KEY -> the value of the first KEY = line
  awk -F= -v k="$2" '
    $0 ~ /^[[:space:]]*#/ { next }
    $1 ~ "^[[:space:]]*" k "[[:space:]]*$" {
      sub(/^[^=]*=[[:space:]]*/, "")
      sub(/[[:space:]]+$/, "")
      print
      exit
    }' "$1"
}

architecture_of() { # pacman.conf -> its Architecture value
  awk -F= '/^[[:space:]]*Architecture[[:space:]]*=/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "$1"
}

pins="$(find "$REPO_ROOT/bootstrap/keyrings" -type f -name '*.pin' | sort)"
if [ -z "$pins" ]; then
  fail "at least one keyring pin exists"     "searched: $REPO_ROOT/bootstrap/keyrings"     "without a pin, no port that signs with its own keys can build under SigLevel = Required"     "reproduce: ls bootstrap/keyrings/*.pin"
fi

# ⛔ The floor. A derivation that matched nothing would report no failure and
# assert nothing, which is the shape this whole file exists to avoid.
pairs=0
while IFS= read -r pin; do
  [ -n "$pin" ] || continue
  keyring="$(pin_field "$pin" keyring)"
  archs="$(pin_field "$pin" arch)"
  pin_rel="${pin#"$REPO_ROOT/"}"
  if [ -z "$keyring" ] || [ -z "$archs" ]; then
    fail "$pin_rel names a keyring and the architectures it serves"       "keyring: ${keyring:-<unset>}, arch: ${archs:-<unset>}"       "reproduce: cat $pin_rel"
    continue
  fi

  for pacman_arch in $archs; do
    for conf in "$REPO_ROOT"/rootfs/*/etc/pacman.conf; do
      [ -e "$conf" ] || continue
      [ "$(architecture_of "$conf")" = "$pacman_arch" ] || continue
      dir="${conf#"$REPO_ROOT/rootfs/"}"
      dir="${dir%%/*}"
      list="$REPO_ROOT/bootstrap/$dir/etc/bootstrap-packages.txt"
      pairs=$((pairs + 1))
      if [ ! -f "$list" ]; then
        fail "bootstrap/$dir names $keyring-keyring"           "there is no bootstrap/$dir/etc/bootstrap-packages.txt at all"           "reproduce: ls bootstrap/$dir/etc/bootstrap-packages.txt"
      elif grep -qxF "$keyring-keyring" "$list"; then
        ok "bootstrap/$dir names $keyring-keyring, from $pin_rel"
      else
        fail "bootstrap/$dir names $keyring-keyring"           "$pin_rel serves Architecture = $pacman_arch, which rootfs/$dir sets"           "without it the image cannot verify its own updates after the build"           "reproduce: cat bootstrap/$dir/etc/bootstrap-packages.txt"
      fi
    done
  done
done <<< "$pins"

if [ "$pairs" -gt 0 ]; then
  ok "every pinned keyring was matched to $pairs architecture(s) that ship it"
else
  fail "every pinned keyring was matched to an architecture that ships it"     "no pacman.conf Architecture matched any pin's arch list, so nothing above was checked"     "reproduce: grep -n '^arch' bootstrap/keyrings/*.pin, then grep -n Architecture rootfs/*/etc/pacman.conf"
fi

diag "checked $count package list(s)"
summary
