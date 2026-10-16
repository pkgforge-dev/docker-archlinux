#!/usr/bin/env bash
#
# The bootstrap package lists have package names and nothing else, and
# pacstrap-docker, which installs them, tries a failed download again.
#
# The Dockerfile runs `xargs -r -a /etc/bootstrap-packages.txt pacstrap-docker`.
# xargs has no comment syntax: a line that starts with # gives pacman a package
# named "#", and pacman stops with "target not found: #".
#
#   1. each bootstrap/*/etc/bootstrap-packages.txt has one valid name on each
#      line that is not blank
#   2. each port (scripts/ports list) has a list
#   3. a port whose Architecture a keyring pin names has that keyring package
#      in its list: the image checks its own updates after the build
#   4. pacstrap-docker starts pacman again when a download failed on every
#      server, up to PACSTRAP_TRIES attempts, and stops at once on any other
#      failure. A fake pacman, id, mknod and sleep are on PATH.
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

# A pacman package name, or a group name such as base.
VALID='^[a-z0-9][a-z0-9@._+-]*$'

#---------------------------------------------------------------------------#
# 1. Names only
#---------------------------------------------------------------------------#
count=0
while IFS= read -r list; do
  [ -n "$list" ] || continue
  rel="${list#"$REPO_ROOT/"}"
  count=$((count + 1))

  if [ ! -s "$list" ]; then
    fail "$rel is not empty" "an empty list installs nothing, and the image has no shell" \
      "reproduce: cat $rel"
    continue
  fi

  bad=""
  n=0
  lineno=0
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    # xargs drops a blank line.
    case "$line" in "") continue ;; esac
    n=$((n + 1))
    if ! [[ "$line" =~ $VALID ]]; then
      bad="$bad $rel:$lineno($line)"
    fi
  done < "$list"

  if [ -n "$bad" ]; then
    fail "$rel has only package names" \
      "not a package name:$bad" \
      "xargs has no comment syntax, so a # line gives pacman a package named #" \
      "reproduce: xargs -r -a $rel echo pacstrap-docker /rootfs"
  elif [ "$n" -eq 0 ]; then
    fail "$rel names at least one package" "the file has no line that is not blank" \
      "reproduce: cat $rel"
  else
    ok "$rel names $n package(s), each a valid name"
  fi
done <<< "$lists"

#---------------------------------------------------------------------------#
# 2. One list for each port
#---------------------------------------------------------------------------#
arches="$("$REPO_ROOT/scripts/ports" list)"
if [ -z "$arches" ]; then
  fail "scripts/ports lists at least one port" "it printed nothing" \
    "reproduce: scripts/ports list"
fi
while IFS= read -r arch; do
  [ -n "$arch" ] || continue
  if [ -f "$REPO_ROOT/bootstrap/$arch/etc/bootstrap-packages.txt" ]; then
    ok "bootstrap/$arch/etc/bootstrap-packages.txt exists"
  else
    fail "bootstrap/$arch/etc/bootstrap-packages.txt exists" \
      "ports/$arch.conf names the port, and it has no list" \
      "reproduce: ls bootstrap/$arch/etc/bootstrap-packages.txt"
  fi
done <<< "$arches"

#---------------------------------------------------------------------------#
# 3. The keyring package of each pin is in the list of each port it serves.
#
# ⛔ From bootstrap/keyrings/*.pin, not from a list here: a new pin needs no
# change to this test.
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
  fail "at least one keyring pin exists" "searched: $REPO_ROOT/bootstrap/keyrings" \
    "reproduce: ls bootstrap/keyrings/*.pin"
fi

# ⛔ The floor: a match of nothing would check nothing and fail nothing.
pairs=0
while IFS= read -r pin; do
  [ -n "$pin" ] || continue
  keyring="$(pin_field "$pin" keyring)"
  archs="$(pin_field "$pin" arch)"
  pin_rel="${pin#"$REPO_ROOT/"}"
  if [ -z "$keyring" ] || [ -z "$archs" ]; then
    fail "$pin_rel names a keyring and its architectures" \
      "keyring: ${keyring:-<unset>}, arch: ${archs:-<unset>}" \
      "reproduce: cat $pin_rel"
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
        fail "bootstrap/$dir names $keyring-keyring" \
          "there is no bootstrap/$dir/etc/bootstrap-packages.txt" \
          "reproduce: ls bootstrap/$dir/etc/bootstrap-packages.txt"
      elif grep -qxF "$keyring-keyring" "$list"; then
        ok "bootstrap/$dir names $keyring-keyring, from $pin_rel"
      else
        fail "bootstrap/$dir names $keyring-keyring" \
          "$pin_rel has Architecture = $pacman_arch, which rootfs/$dir sets" \
          "without it the image cannot check its own updates" \
          "reproduce: cat bootstrap/$dir/etc/bootstrap-packages.txt"
      fi
    done
  done
done <<< "$pins"

if [ "$pairs" -gt 0 ]; then
  ok "each pinned keyring matched $pairs port(s) that ship it"
else
  fail "each pinned keyring matches a port that ships it" \
    "no Architecture of a pacman.conf is in the arch list of a pin" \
    "reproduce: grep -n '^arch' bootstrap/keyrings/*.pin; grep -n Architecture rootfs/*/etc/pacman.conf"
fi

#---------------------------------------------------------------------------#
# 4. pacstrap-docker tries a failed download again, and nothing else
#
# The fake pacman reads one step of FAKE_DIR/plan for each call: "ok" exits
# 0, any other step prints FAKE_DIR/out.STEP and exits 1. The outputs are the
# lines pacman 7.1 gives for each failure.
#---------------------------------------------------------------------------#
STRAP="$REPO_ROOT/bootstrap/any/usr/local/bin/pacstrap-docker"
STRAP_REPRO="bash tests/static/90-package-lists.sh (the fake pacman is in a temporary directory)"
work="$(work_dir)"
trap 'rm -rf "$work"' EXIT
fake="$work/fake"
mkdir -p "$fake/bin"

cat > "$fake/bin/pacman" <<'EOF'
#!/bin/sh
set -eu
n=$(($(cat "$FAKE_DIR/calls") + 1))
echo "$n" > "$FAKE_DIR/calls"
printf '%s\n' "$*" >> "$FAKE_DIR/args"
step="$(awk -v n="$n" 'NR == n' "$FAKE_DIR/plan")"
case "$step" in
  ok) exit 0 ;;
  '')
    echo "fake pacman: the plan has no step $n" >&2
    exit 99
    ;;
esac
cat "$FAKE_DIR/out.$step"
exit 1
EOF
cat > "$fake/bin/id" <<'EOF'
#!/bin/sh
echo 0
EOF
cat > "$fake/bin/mknod" <<'EOF'
#!/bin/sh
: > "$1"
EOF
cat > "$fake/bin/sleep" <<'EOF'
#!/bin/sh
printf '%s ' "$1" >> "$FAKE_DIR/sleeps"
EOF
chmod +x "$fake/bin/pacman" "$fake/bin/id" "$fake/bin/mknod" "$fake/bin/sleep"

cat > "$fake/out.db-curl" <<'EOF'
:: Synchronizing package databases...
error: failed retrieving file 'core.db' from mirror.example : Operation too slow. Less than 1 bytes/sec transferred the last 10 seconds
error: failed to synchronize all databases (download library error)
EOF
cat > "$fake/out.db-xfer" <<'EOF'
:: Synchronizing package databases...
error: failed to synchronize all databases (error invoking external downloader)
EOF
cat > "$fake/out.pkg-xfer" <<'EOF'
:: Retrieving packages...
warning: failed to retrieve some files
error: failed to commit transaction (error invoking external downloader)
Errors occurred, no packages were upgraded.
EOF
cat > "$fake/out.notfound" <<'EOF'
error: target not found: nosuch
EOF
cat > "$fake/out.db-sig" <<'EOF'
:: Synchronizing package databases...
error: core: missing required signature
error: failed to synchronize all databases (invalid or corrupted database (PGP signature))
EOF
cat > "$fake/out.recovered-sig" <<'EOF'
:: Retrieving packages...
error: failed retrieving file 'pacman-7.1.0-1-x86_64.pkg.tar.zst' from mirror.example : The requested URL returned error: 404
error: pacman: signature from "Example <example@example.org>" is invalid
error: failed to commit transaction (invalid or corrupted package (PGP signature))
Errors occurred, no packages were upgraded.
EOF

# strap DESC PLAN WANT_RC WANT_CALLS WANT_SLEEPS [ENV=VALUE ...] -> one run of
# pacstrap-docker ROOT base pacman. One assertion checks the exit status, the
# number of pacman calls and the delays.
strap() {
  local desc="$1" plan="$2" want_rc="$3" want_calls="$4" want_sleeps="$5" rc=0 calls sleeps
  shift 5
  rm -rf "$work/root"
  tr ' ' '\n' <<< "$plan" > "$fake/plan"
  echo 0 > "$fake/calls"
  : > "$fake/args"
  : > "$fake/sleeps"
  env PATH="$fake/bin:$PATH" FAKE_DIR="$fake" "$@" \
    bash "$STRAP" "$work/root" base pacman > "$work/strap.out" 2>&1 || rc=$?
  calls="$(cat "$fake/calls")"
  sleeps="$(cat "$fake/sleeps")"
  if [ "$rc" -eq "$want_rc" ] && [ "$calls" -eq "$want_calls" ] && [ "$sleeps" = "$want_sleeps" ]; then
    ok "$desc"
  else
    fail "$desc" \
      "want: exit $want_rc, $want_calls pacman call(s), delays '$want_sleeps'" \
      "got:  exit $rc, $calls pacman call(s), delays '$sleeps'" \
      "plan: $plan" \
      "it said: $(tr '\n' '|' < "$work/strap.out")" \
      "reproduce: $STRAP_REPRO"
  fi
}

strap "two failed downloads, then a pass: three attempts, exit 0" \
  "db-curl db-curl ok" 0 3 "20 40 "
args_want="-r $work/root -Sy --noconfirm base pacman"
args_got="$(awk 'END { print }' "$fake/args")"
check_eq "each attempt gives pacman the root and the packages" "$args_want" "$args_got" "$STRAP_REPRO"
strap "a database download that fails through the XferCommand is tried again" \
  "db-xfer ok" 0 2 "20 "
strap "a package download that fails through the XferCommand is tried again" \
  "pkg-xfer ok" 0 2 "20 "
strap "three failed downloads stop after the third attempt, exit 1" \
  "db-curl db-curl db-curl ok" 1 3 "20 40 "
strap "PACSTRAP_TRIES=1 makes one attempt" \
  "db-curl ok" 1 1 "" PACSTRAP_TRIES=1
strap "a package that no repository has stops at once" \
  "notfound ok" 1 1 ""
strap "a database with a bad signature stops at once" \
  "db-sig ok" 1 1 ""
strap "a download that the next server gave, then a bad signature, stops at once" \
  "recovered-sig ok" 1 1 ""
strap "a PACSTRAP_TRIES that is not a whole number from 1 is refused before pacman starts" \
  "ok" 1 0 "" PACSTRAP_TRIES=two

diag "checked $count package list(s)"
summary
