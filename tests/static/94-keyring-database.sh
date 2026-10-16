#!/usr/bin/env bash
#
# scripts/check-keyring-pin finds the newest keyring package in the repository
# database of the port. It reads the servers of the mirror list of the port,
# and compares the pin with the package.
#
# The test makes a fixture port (tests/fixtures/94-keyring-database), two
# signing keys, keyring packages, and gzip databases under a file:// mirror.
# No network. The machine values come from GITHUB_OUTPUT, not from the text.
#
#   current        the database names the pinned file with the pinned sha256
#   CHANGED (5)    the database names the pinned file with another sha256
#   behind (3)     a newer package, same fingerprints, the old one served
#   GONE (4)       a newer package, the old one not served
#   changed set    a newer package that trusts one more fingerprint
#   untrusted (7)  a newer package that a key outside the pin signed
#   UNREACHABLE    no server answers
#   --apply        writes the new package into the pin and the tree
#   expiry         runs_out from the trusted lines of the pin
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

if ! need_tool gpg tar curl base64 sha256sum jq; then
  summary
  exit $?
fi

FIX="$(fixture_dir)"
work="$(work_dir)"
# The gpg agent of the fixture keys stops with the test.
cleanup() {
  local rc=0
  gpgconf --homedir "$work/gnupg" --kill all > "$work/kill.log" 2>&1 || rc=$?
  rm -rf "$work"
}
trap cleanup EXIT

# expect DESC WANT GOT REPRODUCE
expect() {
  if [ "$2" = "$3" ]; then
    ok "$1"
  else
    fail "$1" "expected: $2" "got:      $3" "reproduce: $4"
  fi
}

#---------------------------------------------------------------------------#
# Two signing keys: A, which the pin trusts, and B, which it does not.
#---------------------------------------------------------------------------#
export GNUPGHOME="$work/gnupg"
mkdir -p "$GNUPGHOME"
chmod 0700 "$GNUPGHOME"
for who in a b; do
  gpg --batch --quiet --pinentry-mode loopback --passphrase '' \
    --quick-gen-key "Fixture $who <$who@fixture.invalid>" ed25519 sign never > "$work/gen-$who.log" 2>&1
done
gpg --batch --with-colons --list-keys > "$work/keys.txt" 2> "$work/list.log"
fprs="$(awk -F: '$1 == "fpr" { print $10 }' "$work/keys.txt")"
FPR_A="$(printf '%s\n' "$fprs" | awk 'NR == 1')"
FPR_B="$(printf '%s\n' "$fprs" | awk 'NR == 2')"
if [ -z "$FPR_A" ] || [ -z "$FPR_B" ]; then
  fail "two fixture keys are made" "gpg said: $(tr '\n' ' ' < "$work/gen-a.log")" \
    "reproduce: gpg --batch --pinentry-mode loopback --passphrase '' --quick-gen-key 'x <x@x.invalid>' ed25519 sign never"
  summary
  exit 1
fi

OLD=fx-keyring-20260101-1-any.pkg.tar.gz
NEW=fx-keyring-20260201-1-any.pkg.tar.gz

# make_pkg OUT FPR...: a keyring package that carries and trusts FPR...
make_pkg() {
  local out="$1" d="$work/pkgdir" f
  shift
  rm -rf "$d"
  mkdir -p "$d/usr/share/pacman/keyrings"
  gpg --batch --export "$@" > "$d/usr/share/pacman/keyrings/fx.gpg"
  : > "$d/usr/share/pacman/keyrings/fx-trusted"
  for f in "$@"; do
    printf '%s:4:\n' "$f" >> "$d/usr/share/pacman/keyrings/fx-trusted"
  done
  : > "$d/usr/share/pacman/keyrings/fx-revoked"
  tar -czf "$out" -C "$d" usr
}

# sign FILE FPR: FILE.sig, a detached signature by FPR
sign() {
  gpg --batch --quiet --yes --pinentry-mode loopback --passphrase '' -u "$2" --detach-sign -o "$1.sig" "$1"
}

sha_of() {
  sha256sum "$1" | awk '{ print $1 }'
}

# db OUT ENTRY...: a gzip database. ENTRY is NAME:VERSION:FILENAME:SHA256:SIGFILE,
# SIGFILE "-" for no %PGPSIG%.
db() {
  local out="$1" d="$work/dbdir" e name ver file sum sig dirs=()
  shift
  rm -rf "$d"
  mkdir -p "$d"
  for e in "$@"; do
    IFS=: read -r name ver file sum sig <<< "$e"
    mkdir -p "$d/$name-$ver"
    {
      printf '%%FILENAME%%\n%s\n\n%%NAME%%\n%s\n\n%%VERSION%%\n%s\n\n' "$file" "$name" "$ver"
      printf '%%SHA256SUM%%\n%s\n\n' "$sum"
      if [ "$sig" != "-" ]; then
        printf '%%PGPSIG%%\n%s\n\n' "$(base64 -w0 < "$sig")"
      fi
    } > "$d/$name-$ver/desc"
    dirs+=("$name-$ver")
  done
  tar -czf "$out" -C "$d" "${dirs[@]}"
}

# The packages: the old one (A) and a new one with the same set (A). A new
# one that adds B, signed by A. A new one signed by B.
make_pkg "$work/old.pkg" "$FPR_A"
make_pkg "$work/new-same.pkg" "$FPR_A"
make_pkg "$work/new-added.pkg" "$FPR_A" "$FPR_B"
cp "$work/new-same.pkg" "$work/new-bsig.pkg"
sign "$work/new-same.pkg" "$FPR_A"
sign "$work/new-added.pkg" "$FPR_A"
sign "$work/new-bsig.pkg" "$FPR_B"
OLD_SHA="$(sha_of "$work/old.pkg")"

# setup CASE: the pin, the port, the rootfs and an empty mirror for one case.
# Sets M (the extra repository of the mirror) and P (the pin).
setup() {
  local c="$work/case-$1"
  rm -rf "$c"
  mkdir -p "$c/pins" "$c/mirror/core/os/fxarch" "$c/mirror/extra/os/fxarch"
  cp -R "$FIX/ports" "$c/ports"
  cp -R "$FIX/rootfs" "$c/rootfs"
  mkdir -p "$c/rootfs/fxport/etc/pacman.d"
  # shellcheck disable=SC2016 # $repo and $arch are pacman variables
  printf 'Server = file://%s/mirror/$repo/os/$arch\n' "$c" > "$c/rootfs/fxport/etc/pacman.d/mirrorlist"
  cp "$work/old.pkg" "$c/pins/$OLD"
  P="$c/pins/fx.pin"
  {
    printf '# A fixture pin.\n#\n# Adopted 2026-01-01. Measured against the fixture mirror.\n\n'
    printf 'keyring = fx\narch    = fxarch\nmirror  = file://%s/pinmirror\n' "$c"
    printf 'package = %s\nsha256  = %s\ntrusted = %s %s\n' "$OLD" "$OLD_SHA" "$FPR_A" "${EXPIRY:-never}"
  } > "$P"
  M="$c/mirror/extra/os/fxarch"
  # core has no keyring package; its decoy shares the name prefix.
  printf 'decoy\n' > "$work/decoy"
  db "$c/mirror/core/os/fxarch/core.db" \
    "fx-keyring-tools:1-1:fx-keyring-tools-1-1-any.pkg.tar.gz:$(sha_of "$work/decoy"):-" \
    "other:1-1:other-1-1-any.pkg.tar.gz:$(sha_of "$work/decoy"):-"
  CASE_DIR="$c"
}

# check [ARGS...]: run scripts/check-keyring-pin on P; sets rc and reads the
# step outputs into out_<key>
check() {
  rc=0
  : > "$CASE_DIR/github_output"
  # shellcheck disable=SC2016 # $arch and $repo are expanded by the script
  KEYRING_PIN_DIR="$CASE_DIR/pins" KEYRING_ROOTFS_DIR="$CASE_DIR/rootfs" PORTS_DIR="$CASE_DIR/ports" \
    KEYRING_FIRST_SERVER="file://$CASE_DIR/first/\$arch/\$repo" KEYRING_TODAY=2026-10-16 \
    GITHUB_OUTPUT="$CASE_DIR/github_output" \
    "$REPO_ROOT/scripts/check-keyring-pin" "$@" "$P" > "$CASE_DIR/out" 2>&1 || rc=$?
}

# out KEY -> the last value of KEY in GITHUB_OUTPUT
out() {
  awk -v k="$1" 'index($0, k "=") == 1 { v = substr($0, length(k) + 2) } END { print v }' "$CASE_DIR/github_output"
}

R="tests/static/94-keyring-database.sh builds the fixture; then scripts/check-keyring-pin PIN"

#---------------------------------------------------------------------------#
setup current
db "$M/extra.db" "fx-keyring:20260101-1:$OLD:$OLD_SHA:-"
check
expect "the database names the pinned package: current, read through the mirror list after the first server failed" \
  "0 0 database file://$CASE_DIR/mirror/extra/os/fxarch/extra.db" \
  "$rc $(out result) $(out source) $(out served_from)" "$R"
expect "the expiry: one usable key that never expires, runs_out no" "1 no" "$(out usable_count) $(out runs_out)" "$R"

EXPIRY=2026-12-01 setup soon
db "$M/extra.db" "fx-keyring:20260101-1:$OLD:$OLD_SHA:-"
check
expect "the only trusted key expires within a year: runs_out yes" "0 1 yes" "$rc $(out usable_count) $(out runs_out)" "$R"

EXPIRY=2026-01-01 setup expired
db "$M/extra.db" "fx-keyring:20260101-1:$OLD:$OLD_SHA:-"
check
expect "the only trusted key is expired: no usable key, runs_out yes" "0 0 yes" "$rc $(out usable_count) $(out runs_out)" "$R"

setup changed-bytes
db "$M/extra.db" "fx-keyring:20260101-1:$OLD:$(sha_of "$work/decoy"):-"
check
expect "the database names the pinned file with other bytes: exit 5" "5 5" "$rc $(out result)" "$R"

setup behind
cp "$work/new-same.pkg" "$M/$NEW"
cp "$work/new-same.pkg.sig" "$M/$NEW.sig"
cp "$work/old.pkg" "$M/$OLD"
db "$M/extra.db" "fx-keyring:20260201-1:$NEW:$(sha_of "$work/new-same.pkg"):-"
check
expect "a newer package with the same fingerprints, the old one served: exit 3, set same" \
  "3 $NEW same 200" "$rc $(out new_package) $(out trusted_set) $(out pinned_http)" "$R"

rm "$M/$OLD"
check
expect "the old package is not served: exit 4" "4 404" "$rc $(out pinned_http)" "$R"

check --apply
after="$(awk -F' *= *' '$1 == "package" || $1 == "sha256" { printf "%s ", $2 }' "$P")"
expect "--apply writes the new package and sha256 into the pin" \
  "$NEW $(sha_of "$work/new-same.pkg") " "$after" "$R --apply"
if [ -f "$CASE_DIR/pins/$NEW" ] && [ ! -e "$CASE_DIR/pins/$OLD" ] && grep -q '^# Adopted 2026-10-16\. ' "$P"; then
  ok "--apply moves the copy in the tree, and the Adopted date"
else
  fail "--apply moves the copy in the tree, and the Adopted date" \
    "pin directory: $(cd "$CASE_DIR/pins" && printf '%s ' *)" "reproduce: $R --apply"
fi
check
expect "after --apply the pin is current" "0 0" "$rc $(out result)" "$R"

setup added
cp "$work/new-added.pkg" "$M/$NEW"
cp "$work/old.pkg" "$M/$OLD"
db "$M/extra.db" "fx-keyring:20260201-1:$NEW:$(sha_of "$work/new-added.pkg"):$work/new-added.pkg.sig"
check
expect "a newer package that trusts one more key (signature from %PGPSIG%): exit 3, set changed, the key named" \
  "3 changed $FPR_B" "$rc $(out trusted_set) $(out trusted_added | tr -d ' ')" "$R"

setup untrusted
cp "$work/new-bsig.pkg" "$M/$NEW"
cp "$work/new-bsig.pkg.sig" "$M/$NEW.sig"
db "$M/extra.db" "fx-keyring:20260201-1:$NEW:$(sha_of "$work/new-bsig.pkg"):-"
check
expect "a newer package that a key outside the pin signed: exit 7" "7 7" "$rc $(out result)" "$R"
check --apply
expect "--apply refuses it and leaves the pin" "1 $OLD" "$rc $(awk -F' *= *' '$1 == "package" { print $2 }' "$P")" "$R --apply"

setup unreachable
rm -rf "$CASE_DIR/mirror"
check
expect "no server answers: exit 6" "6 6" "$rc $(out result)" "$R"

summary
