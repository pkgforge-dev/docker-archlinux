#!/usr/bin/env bash
#
# Every keyring pin carries its package, and the package is the pin.
#
# ⛔ A port deletes a superseded keyring package from its mirror. A build that
# could only fetch its pin by name failed every day the pin was behind: loong64
# from 2026-09-06. bootstrap/any/usr/local/bin/install-port-keyring now reads
# the package from the tree, so the tree has to carry it, and carry the bytes
# the pin names. HISTORY/outage-2026-09.md.
#
# Asserted per pin:
#   1. the package the pin names is in bootstrap/keyrings/ under that name
#   2. it hashes to the pin's sha256
#   3. its trusted set is the pin's trusted set, and every expiry matches
# and over the directory:
#   4. no package sits there that no pin names
#
# ⚠ 3 needs gpg and an archive reader that knows xz and zstd. A host without
# them says which assertion it skipped.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

DIR="$REPO_ROOT/bootstrap/keyrings"

# field FILE KEY -> the value of the first KEY = line, comments ignored
field() {
  awk -F= -v k="$2" '
    $0 ~ /^[[:space:]]*#/ { next }
    $1 ~ "^[[:space:]]*" k "[[:space:]]*$" {
      sub(/^[^=]*=[[:space:]]*/, "")
      sub(/[[:space:]]+$/, "")
      print
      exit
    }' "$1" | tr -d '\r'
}

# unpack ARCHIVE DIR -> 0 when the archive was read
unpack() {
  if command -v bsdtar > /dev/null; then
    bsdtar -xf "$1" -C "$2"
  else
    tar -xf "$1" -C "$2"
  fi
}

can_read_keys=1
command -v gpg > /dev/null || can_read_keys=0

work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

pins=0
named=""
for pin in "$DIR"/*.pin; do
  [ -e "$pin" ] || continue
  pins=$((pins + 1))
  rel="${pin#"$REPO_ROOT/"}"
  keyring="$(field "$pin" keyring)"
  pkg="$(field "$pin" package)"
  want="$(field "$pin" sha256)"
  named="$named$pkg
"

  # 1. present
  if [ ! -f "$DIR/$pkg" ]; then
    fail "$rel has its package in the tree" \
      "missing: bootstrap/keyrings/$pkg" \
      "the build reads the pinned package from the tree, because a port deletes a superseded one from its mirror" \
      "reproduce: ls bootstrap/keyrings/$pkg, and scripts/check-keyring-pin --apply $rel to fetch it"
    continue
  fi
  ok "$rel has its package in the tree, $pkg"

  # 2. the bytes the pin names
  got="$(sha256sum "$DIR/$pkg" | cut -d' ' -f1)"
  if [ "$got" = "$want" ]; then
    ok "$pkg hashes to the pin's sha256"
  else
    fail "$pkg hashes to the pin's sha256" \
      "pin says: $want" \
      "tree has: $got" \
      "⛔ either the pin or the file was edited without the other" \
      "reproduce: sha256sum bootstrap/keyrings/$pkg"
    continue
  fi

  # 3. the trusted set inside it is the pinned set, with the pinned dates
  if [ "$can_read_keys" -eq 0 ]; then
    diag "skipped for $pkg: gpg is not on PATH, so the key material cannot be read"
    continue
  fi
  x="$work/${pkg%%.pkg.tar.*}"
  mkdir -p "$x"
  if ! unpack "$DIR/$pkg" "$x" > "$work/unpack.err" 2>&1; then
    diag "skipped for $pkg: this host cannot read the archive: $(awk 'NF { print; exit }' "$work/unpack.err")"
    continue
  fi
  src="$x/usr/share/pacman/keyrings"
  if [ ! -f "$src/$keyring-trusted" ] || [ ! -f "$src/$keyring.gpg" ]; then
    fail "$pkg carries the $keyring keyring" \
      "no $keyring-trusted or $keyring.gpg under usr/share/pacman/keyrings" \
      "reproduce: bsdtar -tf bootstrap/keyrings/$pkg"
    continue
  fi

  awk -F= '$0 !~ /^[[:space:]]*#/ && $1 ~ /^[[:space:]]*trusted[[:space:]]*$/ {
             sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); print }' "$pin" \
    | tr -d '\r' | LC_ALL=C sort > "$work/pin.txt"
  gpg --batch --with-colons --fixed-list-mode --show-keys "$src/$keyring.gpg" 2> "$work/gpg.err" \
    | awk -F: '
        $1 == "pub" { expires = $7; seen = 1; next }
        $1 == "fpr" && seen {
          if (expires == "") { print $10 " never" }
          else { print $10 " " strftime("%Y-%m-%d", expires + 0, 1) }
          seen = 0
        }' | LC_ALL=C sort > "$work/expiry.txt"
  cut -d: -f1 < "$src/$keyring-trusted" | awk 'NF' | LC_ALL=C sort \
    | awk 'NR == FNR { e[$1] = $2; next } { print $1 " " (($1 in e) ? e[$1] : "no-key") }' \
        "$work/expiry.txt" - | LC_ALL=C sort > "$work/pkg.txt"

  # Compared as text. cmp is in diffutils, which the Arch image this suite also
  # runs in does not carry.
  if [ "$(cat "$work/pin.txt")" = "$(cat "$work/pkg.txt")" ]; then
    ok "$pkg trusts exactly the $(awk 'END { print NR + 0 }' "$work/pin.txt") fingerprints $rel pins, with the pinned expiry dates"
  else
    fail "$pkg trusts exactly what $rel pins" \
      "only in the pin    : $(LC_ALL=C comm -23 "$work/pin.txt" "$work/pkg.txt" | tr '\n' ' ')" \
      "only in the package: $(LC_ALL=C comm -13 "$work/pin.txt" "$work/pkg.txt" | tr '\n' ' ')" \
      "the trusted lines are a set, and the whole set is the trust root" \
      "reproduce: bsdtar -xOf bootstrap/keyrings/$pkg usr/share/pacman/keyrings/$keyring-trusted"
  fi
done

if [ "$pins" -eq 0 ]; then
  fail "bootstrap/keyrings holds at least one pin" \
    "no .pin file found" \
    "reproduce: ls bootstrap/keyrings"
fi

# 4. nothing carried that no pin names
orphans=""
for f in "$DIR"/*.pkg.tar.*; do
  [ -e "$f" ] || continue
  b="$(basename "$f")"
  if ! printf '%s' "$named" | awk -v b="$b" '$0 == b { found = 1 } END { exit found ? 0 : 1 }'; then
    orphans="$orphans $b"
  fi
done
if [ -z "$orphans" ]; then
  ok "every keyring package in the tree is one a pin names"
else
  fail "every keyring package in the tree is one a pin names" \
    "not named by any pin:$orphans" \
    "a package left behind by a pin bump is a second trust root that nothing reads and nothing checks" \
    "reproduce: grep -h '^package' bootstrap/keyrings/*.pin, and ls bootstrap/keyrings"
fi

summary
