#!/usr/bin/env bash
#
# Each keyring pin has its package in the tree, and the package is the pin.
#
# ⛔ A port deletes an old keyring package from its mirrors. So
# bootstrap/any/usr/local/bin/install-port-keyring reads the package from the
# tree, and the tree must have the bytes that the pin names.
#
# For each pin:
#   1. the pin has a mirror line, and the first mirror line is https
#   2. the package that the pin names is in bootstrap/keyrings/ under that name
#   3. its sha256 is the sha256 of the pin
#   4. its trusted set is the trusted set of the pin, with each expiry
# For the directory:
#   5. each package in it is one that a pin names
#
# 4 needs gpg (need_tool), and an archive reader for xz and zstd.
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

# field_all FILE KEY -> each value of KEY, in file order
field_all() {
  awk -F= -v k="$2" '
    $0 ~ /^[[:space:]]*#/ { next }
    $1 ~ "^[[:space:]]*" k "[[:space:]]*$" {
      sub(/^[^=]*=[[:space:]]*/, "")
      sub(/[[:space:]]+$/, "")
      print
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
need_tool gpg || can_read_keys=0

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

  # 1. The mirror lines
  mirrors="$(field_all "$pin" mirror)"
  first="$(awk 'NF { print; exit }' <<< "$mirrors")"
  case "$first" in
    https://*)
      ok "$rel has $(awk 'NF { n++ } END { print n + 0 }' <<< "$mirrors") mirror line(s), and the first is https"
      ;;
    *)
      fail "$rel has a mirror line, and the first is https" \
        "first mirror line: ${first:-none}" \
        "install-port-keyring and scripts/check-keyring-pin try the mirror lines in file order" \
        "reproduce: grep -n '^mirror' $rel"
      ;;
  esac

  # 2. The package is in the tree
  if [ ! -f "$DIR/$pkg" ]; then
    fail "$rel has its package in the tree" \
      "missing: bootstrap/keyrings/$pkg" \
      "the build reads the pinned package from the tree" \
      "reproduce: ls bootstrap/keyrings/$pkg; scripts/check-keyring-pin --apply $rel puts it there"
    continue
  fi
  ok "$rel has its package in the tree, $pkg"

  # 3. The sha256
  got="$(sha256sum "$DIR/$pkg" | cut -d' ' -f1)"
  if [ "$got" = "$want" ]; then
    ok "$pkg has the sha256 of the pin"
  else
    fail "$pkg has the sha256 of the pin" \
      "pin : $want" \
      "tree: $got" \
      "⛔ the pin or the file changed without the other" \
      "reproduce: sha256sum bootstrap/keyrings/$pkg"
    continue
  fi

  # 4. The trusted set in the package, with each expiry
  if [ "$can_read_keys" -eq 0 ]; then
    continue
  fi
  x="$work/${pkg%%.pkg.tar.*}"
  mkdir -p "$x"
  if ! unpack "$DIR/$pkg" "$x" > "$work/unpack.err" 2>&1; then
    fail "this host can read $pkg" \
      "$(awk 'NF { print; exit }' "$work/unpack.err")" \
      "reproduce: bsdtar -tf bootstrap/keyrings/$pkg"
    continue
  fi
  src="$x/usr/share/pacman/keyrings"
  if [ ! -f "$src/$keyring-trusted" ] || [ ! -f "$src/$keyring.gpg" ]; then
    fail "$pkg has the $keyring keyring" \
      "no $keyring-trusted or $keyring.gpg in usr/share/pacman/keyrings" \
      "reproduce: bsdtar -tf bootstrap/keyrings/$pkg"
    continue
  fi

  field_all "$pin" trusted | LC_ALL=C sort > "$work/pin.txt"
  gpg --batch --with-colons --fixed-list-mode --show-keys "$src/$keyring.gpg" 2> "$work/gpg.err" |
    awk -F: '
      $1 == "pub" { expires = $7; seen = 1; next }
      $1 == "fpr" && seen {
        if (expires == "") { print $10 " never" }
        else { print $10 " " strftime("%Y-%m-%d", expires + 0, 1) }
        seen = 0
      }' | LC_ALL=C sort > "$work/expiry.txt"
  cut -d: -f1 < "$src/$keyring-trusted" | awk 'NF' | LC_ALL=C sort |
    awk 'NR == FNR { e[$1] = $2; next } { print $1 " " (($1 in e) ? e[$1] : "no-key") }' \
      "$work/expiry.txt" - | LC_ALL=C sort > "$work/pkg.txt"

  # Compared as text: the Arch image of this suite has no cmp (diffutils).
  if [ "$(cat "$work/pin.txt")" = "$(cat "$work/pkg.txt")" ]; then
    ok "$pkg trusts the $(awk 'END { print NR + 0 }' "$work/pin.txt") fingerprints of $rel, with the pinned expiry"
  else
    fail "$pkg trusts the fingerprints of $rel, with the pinned expiry" \
      "only in the pin    : $(LC_ALL=C comm -23 "$work/pin.txt" "$work/pkg.txt" | tr '\n' ' ')" \
      "only in the package: $(LC_ALL=C comm -13 "$work/pin.txt" "$work/pkg.txt" | tr '\n' ' ')" \
      "the trusted lines are a set, and the whole set is the trust root" \
      "reproduce: bsdtar -xOf bootstrap/keyrings/$pkg usr/share/pacman/keyrings/$keyring-trusted"
  fi
done

if [ "$pins" -eq 0 ]; then
  fail "bootstrap/keyrings has at least one pin" \
    "no .pin file" \
    "reproduce: ls bootstrap/keyrings"
fi

# 5. Each package in the directory is one that a pin names
orphans=""
for f in "$DIR"/*.pkg.tar.*; do
  [ -e "$f" ] || continue
  b="$(basename "$f")"
  if ! grep -qxF -e "$b" <<< "$named"; then
    orphans="$orphans $b"
  fi
done
if [ -z "$orphans" ]; then
  ok "each keyring package in the tree is one that a pin names"
else
  fail "each keyring package in the tree is one that a pin names" \
    "no pin names:$orphans" \
    "a package left after a pin moved is a second trust root that nothing checks" \
    "reproduce: grep -h '^package' bootstrap/keyrings/*.pin; ls bootstrap/keyrings"
fi

summary
