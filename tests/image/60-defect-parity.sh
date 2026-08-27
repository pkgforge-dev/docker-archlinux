#!/usr/bin/env bash
#
# The failure modes recorded on the upstream tracker, asked of this image.
#
# archlinux/archlinux-docker collects reports of things that went wrong in an
# Arch container. Each one is a question about this image: is the same thing
# true here, and does anything stop it coming back. The answers are measured in
# HISTORY/defect-parity.md, and the ones that must not regress are asserted
# here. Every assertion names the issue number it came from.
#
# ⚠ This file runs the image rather than inspecting it. The other image tests
# create a container without starting it, so an image whose bootstrap installed
# nothing still fails with a readable assertion. That is not available here:
# file modes, extended attributes and locale generation are not observable
# through cp onto a host that has no notion of them, and a check that only ran
# on Linux would pass on Windows for the wrong reason. scripts/gen-evidence
# already runs the image, and runs before this in CI, so an image that cannot
# execute has failed earlier. If the run fails here it is reported as one
# assertion carrying the runtime's own words.
#
# ⚠ The probe writes inside the container. It appends to /etc/locale.gen and
# generates a locale, and it puts two files in /usr/bin/vendor_perl to exercise
# the linker in section 9. The container is removed on exit, so nothing survives
# it and the image itself is never modified.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"
image_require

work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

#---------------------------------------------------------------------------#
# The probe
#
# It runs inside the image and prints key=value, one fact per line. A thing
# that is missing prints a value saying so instead of stopping, so one absent
# path cannot hide every answer below it.
#---------------------------------------------------------------------------#
cat > "$work/probe.sh" <<'PROBE'
set -u

emit() { printf '%s=%s\n' "$1" "$2"; }
count() { wc -l | tr -d '[:space:]'; }

# issue 106, extended attributes are not preserved on unpacking.
emit getfattr "$(command -v getfattr || echo absent)"
for f in /usr/bin/newuidmap /usr/bin/newgidmap; do
  key="cap_${f##*/}"
  if [ ! -e "$f" ]; then
    emit "$key" absent
  else
    v="$(getfattr --only-values -n security.capability "$f" 2>/dev/null | od -An -tx1 | tr -d '[:space:]')"
    emit "$key" "${v:-none}"
  fi
done

# issue 70, a setuid bit dropped between the package and the image.
if [ -e /usr/bin/passwd ]; then
  emit mode_passwd "$(ls -l /usr/bin/passwd | awk 'NR == 1 { print $1 }')"
else
  emit mode_passwd absent
fi
emit setuid_count "$(find / -xdev \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null | count)"

# issues 80 and 64, where a package's binaries land and what is on PATH.
emit link_usr_sbin "$(readlink /usr/sbin || echo none)"
emit link_sbin "$(readlink /sbin || echo none)"
emit link_bin "$(readlink /bin || echo none)"
emit path "$PATH"

# issues 67 and 56, failed to initialize alpm library.
if [ -d /var/lib/pacman ]; then emit pacman_db dir; else emit pacman_db absent; fi
if [ -d /var/lib/pacman/local ]; then emit pacman_local dir; else emit pacman_local absent; fi
emit pacman_query "$(pacman -Qq 2>/dev/null | count)"

# issue 60, the runtime's /etc/hosts and /etc/resolv.conf.
backups=""
for d in /var/lib/pacman/local/filesystem-*/files; do
  [ -f "$d" ] || continue
  backups="$(awk '/^%BACKUP%$/ { b = 1; next } /^%/ { b = 0 } b && NF { print $1 }' "$d")"
done
for p in etc/hosts etc/resolv.conf; do
  if printf '%s\n' "$backups" | awk -v p="$p" '$1 == p { f = 1 } END { exit !f }'; then
    emit "backup_${p##*/}" yes
  else
    emit "backup_${p##*/}" no
  fi
done

# issues 110 and 107, /etc/machine-id and the profile script that reads it.
if [ -f /etc/machine-id ]; then
  emit machine_id_bytes "$(wc -c < /etc/machine-id | tr -d '[:space:]')"
else
  emit machine_id_bytes absent
fi
emit profile_scripts "$(ls /etc/profile.d/*.sh 2>/dev/null | count)"
emit login_noise "$(bash -lc true 2>&1 >/dev/null | wc -c | tr -d '[:space:]')"

# issues 72, 59 and 24, a locale that cannot be generated.
emit charmaps "$(ls /usr/share/i18n/charmaps 2>/dev/null | count)"
emit locale_sources "$(ls /usr/share/i18n/locales 2>/dev/null | count)"
for l in ja_JP zh_CN ru_RU ko_KR; do
  if [ -f "/usr/share/i18n/locales/$l" ]; then
    emit "src_$l" present
  else
    emit "src_$l" absent
  fi
done
printf '%s\n' 'ja_JP.UTF-8 UTF-8' >> /etc/locale.gen
if locale-gen >/dev/null 2>&1; then emit locale_gen ok; else emit locale_gen failed; fi
emit locale_ja "$(locale -a 2>/dev/null | awk '$0 == "ja_JP.utf8" { n++ } END { print n + 0 }')"
emit locale_ja_charmap "$(LC_ALL=ja_JP.UTF-8 locale charmap 2>/dev/null)"
c_day="$(LC_ALL=C date +%A 2>/dev/null)"
ja_day="$(LC_ALL=ja_JP.UTF-8 date +%A 2>/dev/null)"
if [ -n "$ja_day" ] && [ "$c_day" != "$ja_day" ]; then
  emit locale_ja_applies yes
else
  emit locale_ja_applies no
fi

# issue 18, pacman-key and the local signing key.
if [ -d /etc/pacman.d/gnupg/private-keys-v1.d ]; then
  emit lsign_keys "$(ls -A /etc/pacman.d/gnupg/private-keys-v1.d 2>/dev/null | count)"
else
  emit lsign_keys none
fi

# issue 23, pacman-key calling a tool the image does not have.
absent_tools=""
for t in awk gpg gpgconf sed grep; do
  command -v "$t" >/dev/null 2>&1 || absent_tools="$absent_tools $t"
done
emit pacman_key_tools "${absent_tools:-all present}"

# issue 80, and what this image ships to answer it. The mechanism is exercised
# rather than described: a file is put where a perl package would put one, the
# script runs, and the name is looked up the way a consumer would.
LINKER=/usr/local/lib/docker-archlinux/bindir-links
if [ -f /etc/pacman.d/hooks/bindir-links.hook ]; then
  emit bindir_hook present
else
  emit bindir_hook absent
fi
if [ -x "$LINKER" ]; then
  emit bindir_script executable
elif [ -f "$LINKER" ]; then
  emit bindir_script "not executable"
else
  emit bindir_script absent
fi
if [ -x "$LINKER" ]; then
  mkdir -p /usr/bin/vendor_perl
  printf '#!/bin/sh\necho ok\n' > /usr/bin/vendor_perl/parity-probe-tool
  chmod 0755 /usr/bin/vendor_perl/parity-probe-tool
  # A name /usr/bin already owns. Linking this one would shadow the real
  # binary for every consumer, which is the thing that must never happen.
  printf '#!/bin/sh\necho shadowed\n' > /usr/bin/vendor_perl/bash
  chmod 0755 /usr/bin/vendor_perl/bash
  "$LINKER" >/dev/null
  emit bindir_linked "$(command -v parity-probe-tool 2>/dev/null || echo none)"
  emit bindir_shadow "$(command -v bash 2>/dev/null || echo none)"
  # Take the tool away again. The link has to go with it.
  rm -f /usr/bin/vendor_perl/parity-probe-tool
  "$LINKER" >/dev/null
  if [ -L /usr/local/bin/parity-probe-tool ] || [ -e /usr/local/bin/parity-probe-tool ]; then
    emit bindir_pruned no
  else
    emit bindir_pruned yes
  fi
else
  emit bindir_linked "not run"
  emit bindir_shadow "not run"
  emit bindir_pruned "not run"
fi
PROBE

#---------------------------------------------------------------------------#
# Run it once. Every assertion below reads the same set of facts, so the image
# starts once however many things are checked.
#---------------------------------------------------------------------------#
if ! "$RUNTIME" run --rm -i --platform "$PLATFORM" "$IMAGE" bash -s \
     < "$work/probe.sh" > "$work/facts" 2> "$work/err"; then
  fail "the probe runs inside $IMAGE on $PLATFORM" \
    "runtime said: $(tr -d '\r' < "$work/err" | awk 'NF { last = $0 } END { print last }')" \
    "every assertion in this file reads the probe's output, so none of them ran" \
    "reproduce: $RUNTIME run --rm -i --platform $PLATFORM $IMAGE bash -s < the PROBE heredoc in this file"
  summary
  exit 1
fi

# fact KEY -> the value, or empty when the probe printed no such key
fact() {
  awk -v k="$1" -F= '$1 == k { sub(/^[^=]*=/, ""); print; exit }' "$work/facts"
}

facts_seen="$(awk 'NF' "$work/facts" | wc -l | tr -d '[:space:]')"
if [ "$facts_seen" -gt 0 ]; then
  ok "the probe ran in $IMAGE on $PLATFORM and returned $facts_seen facts"
else
  fail "the probe returns facts from $IMAGE on $PLATFORM" \
    "it exited 0 and printed nothing, so every assertion below would read an empty value" \
    "reproduce: $RUNTIME run --rm -i --platform $PLATFORM $IMAGE bash -s < the PROBE heredoc in this file"
  summary
  exit 1
fi

#---------------------------------------------------------------------------#
# 1. Extended attributes survive packing and unpacking. Upstream issue 106.
#
# newuidmap and newgidmap carry security.capability instead of a setuid bit.
# When the attribute is lost the files are still present and still executable,
# so nothing looks wrong until a rootless container inside this one fails to
# map a uid. The official image loses them, measured in
# HISTORY/defect-parity.md.
#---------------------------------------------------------------------------#
if [ "$(fact getfattr)" = absent ]; then
  fail "getfattr is available inside the image to read extended attributes" \
    "the attr package provides it, and the bootstrap set pulls it in" \
    "without it this file cannot tell a missing attribute from a missing tool" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE command -v getfattr"
else
  ok "getfattr is available at $(fact getfattr)"
fi

for f in newuidmap newgidmap; do
  v="$(fact "cap_$f")"
  case "$v" in
    absent)
      fail "/usr/bin/$f is present in $IMAGE on $PLATFORM" \
        "the file is not there at all, so its capability cannot be checked" \
        "shadow ships it and the bootstrap set installs shadow" \
        "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE ls -l /usr/bin/$f"
      ;;
    none | '')
      fail "/usr/bin/$f carries the security.capability attribute" \
        "getfattr returned no value for it" \
        "the file still runs and still looks correct, and a rootless container inside this one cannot map a uid" \
        "this is the class of upstream issue 106, the attribute dropped while packing the rootfs" \
        "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE getfattr -d -m - /usr/bin/$f"
      ;;
    *)
      ok "/usr/bin/$f carries security.capability, $v"
      ;;
  esac
done

#---------------------------------------------------------------------------#
# 2. Setuid and setgid bits survive. Upstream issue 70.
#
# The same class as the attributes above, one step more visible: passwd without
# its setuid bit fails only when a user who is not root runs it.
#---------------------------------------------------------------------------#
mode="$(fact mode_passwd)"
case "$mode" in
  absent)
    fail "/usr/bin/passwd is present in $IMAGE on $PLATFORM" \
      "shadow ships it and the bootstrap set installs shadow" \
      "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE ls -l /usr/bin/passwd"
    ;;
  *s*)
    ok "/usr/bin/passwd keeps its setuid bit, mode $mode"
    ;;
  *)
    fail "/usr/bin/passwd keeps its setuid bit" \
      "mode is $mode" \
      "a user who is not root then gets: Authentication service cannot retrieve authentication info" \
      "this is upstream issue 70, the bit dropped between the package and the image" \
      "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE ls -l /usr/bin/passwd"
    ;;
esac

SETUID_MIN="${SETUID_MIN:-10}"
n="$(fact setuid_count)"
if [ "${n:-0}" -ge "$SETUID_MIN" ]; then
  ok "$n files keep a setuid or setgid bit, minimum $SETUID_MIN"
else
  fail "at least $SETUID_MIN files keep a setuid or setgid bit" \
    "counted: ${n:-0}" \
    "one file keeping its bit can be luck, a whole rootfs losing them is the defect" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE find / -xdev -perm -4000 -type f"
fi

#---------------------------------------------------------------------------#
# 3. The merged /usr layout holds. Upstream issues 80 and 64.
#
# Issue 64 asked for /usr/sbin, /sbin and /bin to be taken out of PATH, because
# they are symlinks and a tool that does not resolve symlinks derives wrong
# paths from them. They are still on PATH here, which is what every consumer
# has seen, so what is asserted is the property those tools depend on: the
# links exist and point where they are expected to.
#---------------------------------------------------------------------------#
for entry in "usr_sbin:/usr/sbin:bin" "sbin:/sbin:usr/bin" "bin:/bin:usr/bin"; do
  key="${entry%%:*}"
  rest="${entry#*:}"
  where="${rest%%:*}"
  want="${rest#*:}"
  got="$(fact "link_$key")"
  if [ "$got" = "$want" ]; then
    ok "$where is a symlink to $want"
  else
    fail "$where is a symlink to $want" \
      "readlink returned: ${got:-nothing}" \
      "a build that turns one of these into a real directory splits the binaries in two" \
      "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE ls -ld $where"
  fi
done

p="$(fact path)"
case ":$p:" in
  *:/usr/bin:*)
    ok "PATH carries /usr/bin"
    ;;
  *)
    fail "PATH carries /usr/bin" \
      "PATH is: ${p:-empty}" \
      "every binary a package installs lands there, so nothing is callable by name without it" \
      "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE printenv PATH"
    ;;
esac

#---------------------------------------------------------------------------#
# 4. The alpm library initialises. Upstream issues 67 and 56.
#
# Both reports end in "failed to initialize alpm library, could not find or
# read directory /var/lib/pacman/". The directory has to be there, and pacman
# has to get far enough to answer a query.
#---------------------------------------------------------------------------#
for entry in "pacman_db:/var/lib/pacman" "pacman_local:/var/lib/pacman/local"; do
  key="${entry%%:*}"
  where="${entry#*:}"
  if [ "$(fact "$key")" = dir ]; then
    ok "$where is a directory"
  else
    fail "$where is a directory" \
      "the probe found: $(fact "$key")" \
      "pacman then refuses to start with: failed to initialize alpm library" \
      "this is upstream issues 67 and 56" \
      "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE ls -ld $where"
  fi
done

PACKAGES_MIN="${PACKAGES_MIN:-50}"
q="$(fact pacman_query)"
if [ "${q:-0}" -ge "$PACKAGES_MIN" ]; then
  ok "pacman initialises and lists $q installed packages, minimum $PACKAGES_MIN"
else
  fail "pacman initialises and lists at least $PACKAGES_MIN installed packages" \
    "it listed: ${q:-0}" \
    "a count of zero is what a failed alpm init looks like from outside" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE pacman -Qq"
fi

#---------------------------------------------------------------------------#
# 5. The runtime's /etc/hosts and /etc/resolv.conf survive an upgrade.
# Upstream issue 60.
#
# The container runtime bind mounts its own versions over both. Upstream's
# proposal was to add them to NoExtract, which this repository reverted for
# other reasons, so what keeps them is pacman's backup handling: a file listed
# in %BACKUP% whose content differs from the package's is left alone. That is
# a property of the package, so the assertion is that the package still
# declares them.
#---------------------------------------------------------------------------#
for p in hosts resolv.conf; do
  if [ "$(fact "backup_$p")" = yes ]; then
    ok "/etc/$p is a pacman backup file, so an upgrade leaves the runtime's copy alone"
  else
    fail "/etc/$p is a pacman backup file" \
      "the filesystem package's %BACKUP% section does not list it" \
      "pacman then overwrites the runtime's bind mounted copy, or fails on it" \
      "this is upstream issue 60. ⛔ NoExtract is not the answer, see HISTORY/noextract-reverted.md" \
      "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE pacman -Qii filesystem"
  fi
done

#---------------------------------------------------------------------------#
# 6. A login shell is quiet, and /etc/machine-id is there. Upstream issues 107
# and 110.
#
# Issue 107 is a script under /etc/profile.d that fails on every login shell,
# so a consumer sees an error before every command. ⚠ The one it names,
# 80-systemd-osc-context.sh reading /etc/machine-id, is guarded by systemd
# itself since 261.2: the read sits behind [ -f /etc/machine-id ]. Measured in
# HISTORY/defect-parity.md. So what is asserted here is the class rather than
# that one script, and the count below is what keeps the quiet check from
# passing on an empty directory.
#
# Issue 110 needs /etc/machine-id present for dbus and systemd to start in a
# rootless container, and machine-id(5) needs it empty so each container
# provisions its own. Both halves are asserted, because the two obvious ways to
# get one of them wrong are deleting the file and leaving the build's ID in it.
# Measured in HISTORY/defect-parity.md.
#---------------------------------------------------------------------------#
PROFILE_SCRIPTS_MIN="${PROFILE_SCRIPTS_MIN:-1}"
scripts="$(fact profile_scripts)"
if [ "${scripts:-0}" -ge "$PROFILE_SCRIPTS_MIN" ]; then
  ok "$scripts scripts run on a login shell, minimum $PROFILE_SCRIPTS_MIN"
else
  fail "at least $PROFILE_SCRIPTS_MIN script runs on a login shell" \
    "counted: ${scripts:-0}" \
    "with none, the next assertion is quiet because nothing ran rather than because nothing failed" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE ls /etc/profile.d/"
fi

noise="$(fact login_noise)"
if [ "${noise:-1}" -eq 0 ]; then
  ok "a login shell writes nothing to stderr"
else
  fail "a login shell writes nothing to stderr" \
    "it wrote ${noise:-unknown} bytes" \
    "every script under /etc/profile.d runs on every login shell, so one that errors is seen before every command" \
    "this is the class of upstream issue 107" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE bash -lc true"
fi

mid="$(fact machine_id_bytes)"
case "$mid" in
  absent)
    fail "the image ships /etc/machine-id, and it is empty" \
      "the file is not there at all" \
      "dbus-broker and systemd then refuse to start in a rootless container, which is upstream issue 110" \
      "⚠ machine-id(5) asks an image for an empty file, not for no file" \
      "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE ls -l /etc/machine-id"
    ;;
  0)
    ok "/etc/machine-id is present and empty, so each container provisions its own"
    ;;
  *)
    fail "the image ships /etc/machine-id, and it is empty" \
      "it holds $mid bytes" \
      "an ID written at build time is shared by every container from this tag, on every host" \
      "machine-id(5) calls the value confidential, and sd_id128_get_machine_app_specific derives identifiers from it" \
      "the Dockerfile truncates it, so a value here means something wrote one after that" \
      "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE cat /etc/machine-id"
    ;;
esac

#---------------------------------------------------------------------------#
# 7. A locale outside the Latin alphabet generates. Upstream issues 72, 59
# and 24.
#
# Three reports over three years, all the same thing: the locale definitions
# were withheld, so locale-gen could build nothing the image did not already
# have. Nothing is withheld here, so ja_JP.UTF-8 has to generate with no
# preparation and then take effect.
#---------------------------------------------------------------------------#
CHARMAPS_MIN="${CHARMAPS_MIN:-100}"
LOCALE_SOURCES_MIN="${LOCALE_SOURCES_MIN:-300}"

c="$(fact charmaps)"
if [ "${c:-0}" -ge "$CHARMAPS_MIN" ]; then
  ok "/usr/share/i18n/charmaps holds $c charmaps, minimum $CHARMAPS_MIN"
else
  fail "/usr/share/i18n/charmaps holds at least $CHARMAPS_MIN charmaps" \
    "counted: ${c:-0}" \
    "the official image ships 2, which is what makes issue 72 unfixable there" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE ls /usr/share/i18n/charmaps"
fi

s="$(fact locale_sources)"
if [ "${s:-0}" -ge "$LOCALE_SOURCES_MIN" ]; then
  ok "/usr/share/i18n/locales holds $s locale definitions, minimum $LOCALE_SOURCES_MIN"
else
  fail "/usr/share/i18n/locales holds at least $LOCALE_SOURCES_MIN locale definitions" \
    "counted: ${s:-0}" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE ls /usr/share/i18n/locales"
fi

for l in ja_JP zh_CN ru_RU ko_KR; do
  if [ "$(fact "src_$l")" = present ]; then
    ok "/usr/share/i18n/locales/$l is present"
  else
    fail "/usr/share/i18n/locales/$l is present" \
      "it is not there, so locale-gen cannot build $l.UTF-8" \
      "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE ls /usr/share/i18n/locales/$l"
  fi
done

if [ "$(fact locale_gen)" = ok ]; then
  ok "locale-gen runs after ja_JP.UTF-8 is appended to /etc/locale.gen"
else
  fail "locale-gen runs after ja_JP.UTF-8 is appended to /etc/locale.gen" \
    "it exited non-zero" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE bash -c 'echo ja_JP.UTF-8 UTF-8 >> /etc/locale.gen; locale-gen'"
fi

if [ "$(fact locale_ja)" = 1 ]; then
  ok "ja_JP.utf8 is listed by locale -a after generation"
else
  fail "ja_JP.utf8 is listed by locale -a after generation" \
    "locale -a matched it $(fact locale_ja) times" \
    "this is upstream issue 72, asked of this image" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE bash -c 'echo ja_JP.UTF-8 UTF-8 >> /etc/locale.gen; locale-gen; locale -a'"
fi

cm="$(fact locale_ja_charmap)"
if [ "$cm" = "UTF-8" ]; then
  ok "the generated ja_JP.UTF-8 reports charmap UTF-8"
else
  fail "the generated ja_JP.UTF-8 reports charmap UTF-8" \
    "it reported: ${cm:-nothing}" \
    "a locale that failed to load falls back and reports ANSI_X3.4-1968" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE bash -c 'echo ja_JP.UTF-8 UTF-8 >> /etc/locale.gen; locale-gen; LC_ALL=ja_JP.UTF-8 locale charmap'"
fi

if [ "$(fact locale_ja_applies)" = yes ]; then
  ok "ja_JP.UTF-8 changes what date prints, so the locale data is loaded"
else
  fail "ja_JP.UTF-8 changes what date prints" \
    "date printed the same weekday name under LC_ALL=C and under LC_ALL=ja_JP.UTF-8" \
    "a locale can be listed and still carry none of the data that makes it useful" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE bash -c 'echo ja_JP.UTF-8 UTF-8 >> /etc/locale.gen; locale-gen; LC_ALL=ja_JP.UTF-8 date +%A'"
fi

#---------------------------------------------------------------------------#
# 8. pacman-key. Upstream issues 18 and 23.
#
# ⛔ The local signing key is not distributed, deliberately. The build runs
# pacman-key --init and then removes private-keys-v1.d, so the image carries a
# populated public keyring and no private key. Shipping one would put the same
# secret in every consumer's image, and no other test would notice it arriving.
#
# ⚠ The visible cost is upstream issue 18: pacman-key --lsign-key fails until a
# consumer runs pacman-key --init themselves. That is the trade upstream made
# and this image copies, and it is the right way round.
#
# Issue 23 is the other half. pacman-key is a shell script that calls out to
# awk, gpg and others, and reports a missing one as a bare "command not found"
# from a line number.
#---------------------------------------------------------------------------#
keys="$(fact lsign_keys)"
if [ "$keys" = none ] || [ "$keys" = 0 ]; then
  ok "no private signing key is shipped in /etc/pacman.d/gnupg"
else
  fail "no private signing key is shipped in /etc/pacman.d/gnupg" \
    "private-keys-v1.d holds $keys file(s)" \
    "that key would be identical in every consumer's image, and it is a secret" \
    "the build runs pacman-key --init and then removes the directory" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE ls -la /etc/pacman.d/gnupg/private-keys-v1.d"
fi

tools="$(fact pacman_key_tools)"
if [ "$tools" = "all present" ]; then
  ok "every tool pacman-key calls out to is on PATH"
else
  fail "every tool pacman-key calls out to is on PATH" \
    "missing:$tools" \
    "pacman-key is a shell script, so a missing one surfaces as command not found from a line number" \
    "this is upstream issue 23, where the image lacked awk" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE pacman-key --list-keys"
fi

#---------------------------------------------------------------------------#
# 9. The answer this image ships for issue 80.
#
# Section 3 measured the defect. This checks the mechanism that fixes it, by
# using it rather than by reading it: a file is placed where a perl package
# would place one, the script runs, and the name is looked up the way a
# consumer looks one up.
#
# ⛔ The shadow case matters more than the link case. Linking a name /usr/bin
# already owns would change what an existing consumer's command resolves to,
# which policy 7 forbids outright. A mechanism that only ever adds is safe; one
# that can replace is not.
#---------------------------------------------------------------------------#
if [ "$(fact bindir_hook)" = present ]; then
  ok "/etc/pacman.d/hooks/bindir-links.hook ships in the image"
else
  fail "/etc/pacman.d/hooks/bindir-links.hook ships in the image" \
    "it is not there, so a package installing outside PATH stays unreachable by name" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE ls -l /etc/pacman.d/hooks/"
fi

case "$(fact bindir_script)" in
  executable)
    ok "/usr/local/lib/docker-archlinux/bindir-links is present and executable"
    ;;
  'not executable')
    fail "/usr/local/lib/docker-archlinux/bindir-links is executable" \
      "the file is there and the mode is wrong" \
      "the hook names an interpreter so it still runs, and a consumer running it by hand cannot" \
      "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE ls -l /usr/local/lib/docker-archlinux/bindir-links"
    ;;
  *)
    fail "/usr/local/lib/docker-archlinux/bindir-links is present" \
      "it is not in the image, and the hook that runs it is" \
      "⛔ that combination fails every transaction the consumer runs" \
      "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE ls -l /usr/local/lib/docker-archlinux/"
    ;;
esac

linked="$(fact bindir_linked)"
if [ "$linked" = /usr/local/bin/parity-probe-tool ]; then
  ok "an executable placed in a perl bindir becomes callable by name"
else
  fail "an executable placed in a perl bindir becomes callable by name" \
    "command -v returned: ${linked:-nothing}" \
    "this is upstream issue 80: podman run <image> exiftool has to work, not only bash -lc exiftool" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE bash -c 'mkdir -p /usr/bin/vendor_perl; printf \"#!/bin/sh\" > /usr/bin/vendor_perl/t; chmod 755 /usr/bin/vendor_perl/t; /usr/local/lib/docker-archlinux/bindir-links; command -v t'"
fi

shadow="$(fact bindir_shadow)"
case "$shadow" in
  /usr/local/bin/*)
    fail "the linker never shadows a name that already resolves" \
      "command -v bash returned: $shadow" \
      "⛔ a consumer's bash would now be a file this image linked, which policy 7 forbids" \
      "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE bash -c 'mkdir -p /usr/bin/vendor_perl; printf \"#!/bin/sh\" > /usr/bin/vendor_perl/bash; chmod 755 /usr/bin/vendor_perl/bash; /usr/local/lib/docker-archlinux/bindir-links; command -v bash'"
    ;;
  none | '' | 'not run')
    fail "the linker never shadows a name that already resolves" \
      "the probe reported: ${shadow:-nothing}" \
      "⛔ the check did not run, so this assertion proves nothing rather than proving safety" \
      "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE command -v bash"
    ;;
  *)
    ok "bash still resolves to $shadow with a same named file in a perl bindir"
    ;;
esac

if [ "$(fact bindir_pruned)" = yes ]; then
  ok "a link is pruned when the executable it points at goes away"
else
  fail "a link is pruned when the executable it points at goes away" \
    "the probe found: $(fact bindir_pruned)" \
    "a dangling link in /usr/local/bin shadows nothing and fails with a confusing error" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE bash -c 'mkdir -p /usr/bin/vendor_perl; printf \"#!/bin/sh\" > /usr/bin/vendor_perl/t; chmod 755 /usr/bin/vendor_perl/t; /usr/local/lib/docker-archlinux/bindir-links; rm /usr/bin/vendor_perl/t; /usr/local/lib/docker-archlinux/bindir-links; ls -l /usr/local/bin'"
fi

summary
