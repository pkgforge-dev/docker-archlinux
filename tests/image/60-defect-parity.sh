#!/usr/bin/env bash
#
# The failure modes of the upstream tracker, asked of this image.
#
# archlinux/archlinux-docker keeps reports of faults in an Arch container.
# Each report is a question about this image: is the same fault here, and
# what stops it from coming back. Each assertion names the issue number of
# the report. docs/measurements.md gives the values measured for each one.
#
# ⚠ This file runs the image. The other image tests create a container and
# do not start it, so an image whose bootstrap installed nothing still fails
# with a clear assertion. File modes, extended attributes and locale
# generation cannot be read through cp onto a host that does not know them.
# scripts/gen-evidence runs the image before this test in each workflow, so
# an image that cannot run fails there first. When the run fails here, one
# assertion gives the words of the runtime.
#
# ⚠ The probe writes inside the container. It appends to /etc/locale.gen,
# generates a locale, and puts two files in /usr/bin/vendor_perl for section
# 9. The container is removed on exit, and the image does not change.
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
# It runs inside the image and prints key=value, one fact per line. A missing
# thing prints a value that says so, and the probe goes on: one absent path
# does not hide the facts after it.
#---------------------------------------------------------------------------#
cat > "$work/probe.sh" <<'PROBE'
set -u

emit() { printf '%s=%s\n' "$1" "$2"; }
count() { wc -l | tr -d '[:space:]'; }

# issue 106: extended attributes lost when the rootfs is unpacked.
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

# issue 70: a setuid bit lost between the package and the image.
if [ -e /usr/bin/passwd ]; then
  emit mode_passwd "$(ls -l /usr/bin/passwd | awk 'NR == 1 { print $1 }')"
else
  emit mode_passwd absent
fi
emit setuid_count "$(find / -xdev \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null | count)"

# issues 80 and 64: where the binaries of a package go, and what PATH holds.
emit link_usr_sbin "$(readlink /usr/sbin || echo none)"
emit link_sbin "$(readlink /sbin || echo none)"
emit link_bin "$(readlink /bin || echo none)"
emit path "$PATH"

# issues 67 and 56: failed to initialize alpm library.
if [ -d /var/lib/pacman ]; then emit pacman_db dir; else emit pacman_db absent; fi
if [ -d /var/lib/pacman/local ]; then emit pacman_local dir; else emit pacman_local absent; fi
emit pacman_query "$(pacman -Qq 2>/dev/null | count)"

# issue 60: /etc/hosts and /etc/resolv.conf of the runtime.
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

# issues 110 and 107: /etc/machine-id, and the profile scripts that read it.
if [ -f /etc/machine-id ]; then
  emit machine_id_bytes "$(wc -c < /etc/machine-id | tr -d '[:space:]')"
else
  emit machine_id_bytes absent
fi
emit profile_scripts "$(ls /etc/profile.d/*.sh 2>/dev/null | count)"
emit login_noise "$(bash -lc true 2>&1 >/dev/null | wc -c | tr -d '[:space:]')"

# issues 72, 59 and 24: a locale that cannot be generated.
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

# issue 18: pacman-key and the local signing key.
if [ -d /etc/pacman.d/gnupg/private-keys-v1.d ]; then
  emit lsign_keys "$(ls -A /etc/pacman.d/gnupg/private-keys-v1.d 2>/dev/null | count)"
else
  emit lsign_keys none
fi

# issue 23: pacman-key calls a tool that the image does not have.
absent_tools=""
for t in awk gpg gpgconf sed grep; do
  command -v "$t" >/dev/null 2>&1 || absent_tools="$absent_tools $t"
done
emit pacman_key_tools "${absent_tools:-all present}"

# issue 80, and the answer of this image. The probe uses the mechanism: it
# puts a file where a perl package puts one, runs the script, and looks the
# name up as a consumer does.
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
  # A name that /usr/bin has. A link of it would hide the real binary from
  # each consumer: that must never happen.
  printf '#!/bin/sh\necho shadowed\n' > /usr/bin/vendor_perl/bash
  chmod 0755 /usr/bin/vendor_perl/bash
  "$LINKER" >/dev/null
  emit bindir_linked "$(command -v parity-probe-tool 2>/dev/null || echo none)"
  emit bindir_shadow "$(command -v bash 2>/dev/null || echo none)"
  # Remove the tool again. The link must go with it.
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
# Run the probe once. Each assertion below reads the same facts, so the image
# starts one time.
#---------------------------------------------------------------------------#
if ! "$RUNTIME" run --rm -i --platform "$PLATFORM" "$IMAGE" bash -s \
     < "$work/probe.sh" > "$work/facts" 2> "$work/err"; then
  fail "the probe runs inside $IMAGE on $PLATFORM" \
    "runtime said: $(tr -d '\r' < "$work/err" | awk 'NF { last = $0 } END { print last }')" \
    "each assertion of this file reads the output of the probe, so none of them ran" \
    "reproduce: $RUNTIME run --rm -i --platform $PLATFORM $IMAGE bash -s < the PROBE heredoc of this file"
  summary
  exit 1
fi

# fact KEY -> the value; empty when the probe printed no such key
fact() {
  awk -v k="$1" -F= '$1 == k { sub(/^[^=]*=/, ""); print; exit }' "$work/facts"
}

facts_seen="$(awk 'NF' "$work/facts" | wc -l | tr -d '[:space:]')"
if [ "$facts_seen" -gt 0 ]; then
  ok "the probe ran in $IMAGE on $PLATFORM and gave $facts_seen facts"
else
  fail "the probe gives facts from $IMAGE on $PLATFORM" \
    "it exited 0 and printed nothing, so each assertion below would read an empty value" \
    "reproduce: $RUNTIME run --rm -i --platform $PLATFORM $IMAGE bash -s < the PROBE heredoc of this file"
  summary
  exit 1
fi

#---------------------------------------------------------------------------#
# 1. Extended attributes stay through packing and unpacking. Upstream issue
#    106.
#
# newuidmap and newgidmap have security.capability in place of a setuid bit.
# Without the attribute the files are there and run, so nothing looks wrong
# until a rootless container in this one cannot map a uid.
#---------------------------------------------------------------------------#
if [ "$(fact getfattr)" = absent ]; then
  fail "getfattr is in the image, to read extended attributes" \
    "the attr package has it, and the bootstrap set installs it" \
    "without it this file cannot tell a missing attribute from a missing tool" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE command -v getfattr"
else
  ok "getfattr is at $(fact getfattr)"
fi

for f in newuidmap newgidmap; do
  v="$(fact "cap_$f")"
  case "$v" in
    absent)
      fail "/usr/bin/$f is in $IMAGE on $PLATFORM" \
        "the file is not there, so its capability cannot be read" \
        "the shadow package has it, and the bootstrap set installs shadow" \
        "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE ls -l /usr/bin/$f"
      ;;
    none | '')
      fail "/usr/bin/$f has the attribute security.capability" \
        "getfattr gave no value" \
        "the file runs and looks correct, and a rootless container in this one cannot map a uid" \
        "this is upstream issue 106: the attribute is lost when the rootfs is packed" \
        "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE getfattr -d -m - /usr/bin/$f"
      ;;
    *)
      ok "/usr/bin/$f has security.capability, $v"
      ;;
  esac
done

#---------------------------------------------------------------------------#
# 2. Setuid and setgid bits stay. Upstream issue 70.
#
# The same class as section 1: passwd with no setuid bit fails only when a
# user who is not root runs it.
#---------------------------------------------------------------------------#
mode="$(fact mode_passwd)"
case "$mode" in
  absent)
    fail "/usr/bin/passwd is in $IMAGE on $PLATFORM" \
      "the shadow package has it, and the bootstrap set installs shadow" \
      "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE ls -l /usr/bin/passwd"
    ;;
  *s*)
    ok "/usr/bin/passwd keeps its setuid bit, mode $mode"
    ;;
  *)
    fail "/usr/bin/passwd keeps its setuid bit" \
      "the mode is $mode" \
      "a user who is not root then gets: Authentication service cannot retrieve authentication info" \
      "this is upstream issue 70: the bit is lost between the package and the image" \
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
    "one file with its bit can be chance; a rootfs that loses them all is the fault" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE find / -xdev -perm -4000 -type f"
fi

#---------------------------------------------------------------------------#
# 3. The merged /usr layout holds. Upstream issues 80 and 64.
#
# Issue 64 asks to take /usr/sbin, /sbin and /bin off PATH, because they are
# links. A tool that does not resolve links derives wrong paths from them.
# They stay on PATH here, as each consumer has always seen. So the
# assertion is the property those tools need: the links are there, and point
# where they must.
#---------------------------------------------------------------------------#
for entry in "usr_sbin:/usr/sbin:bin" "sbin:/sbin:usr/bin" "bin:/bin:usr/bin"; do
  key="${entry%%:*}"
  rest="${entry#*:}"
  where="${rest%%:*}"
  want="${rest#*:}"
  got="$(fact "link_$key")"
  if [ "$got" = "$want" ]; then
    ok "$where is a link to $want"
  else
    fail "$where is a link to $want" \
      "readlink gave: ${got:-nothing}" \
      "a build that makes one of these a real directory splits the binaries in two" \
      "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE ls -ld $where"
  fi
done

p="$(fact path)"
case ":$p:" in
  *:/usr/bin:*)
    ok "PATH has /usr/bin"
    ;;
  *)
    fail "PATH has /usr/bin" \
      "PATH is: ${p:-empty}" \
      "each binary of a package goes there, so without it nothing runs by name" \
      "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE printenv PATH"
    ;;
esac

#---------------------------------------------------------------------------#
# 4. The alpm library starts. Upstream issues 67 and 56.
#
# Both reports end in "failed to initialize alpm library, could not find or
# read directory /var/lib/pacman/". The directory must be there, and pacman
# must answer a query.
#---------------------------------------------------------------------------#
for entry in "pacman_db:/var/lib/pacman" "pacman_local:/var/lib/pacman/local"; do
  key="${entry%%:*}"
  where="${entry#*:}"
  if [ "$(fact "$key")" = dir ]; then
    ok "$where is a directory"
  else
    fail "$where is a directory" \
      "the probe found: $(fact "$key")" \
      "pacman then does not start: failed to initialize alpm library" \
      "this is upstream issues 67 and 56" \
      "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE ls -ld $where"
  fi
done

PACKAGES_MIN="${PACKAGES_MIN:-50}"
q="$(fact pacman_query)"
if [ "${q:-0}" -ge "$PACKAGES_MIN" ]; then
  ok "pacman starts and lists $q installed packages, minimum $PACKAGES_MIN"
else
  fail "pacman starts and lists at least $PACKAGES_MIN installed packages" \
    "it listed: ${q:-0}" \
    "a count of 0 is what a failed alpm start looks like from outside" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE pacman -Qq"
fi

#---------------------------------------------------------------------------#
# 5. The /etc/hosts and /etc/resolv.conf of the runtime stay through an
#    upgrade. Upstream issue 60.
#
# The container runtime mounts its own copies over both. The proposal
# upstream was NoExtract, and this image has no NoExtract rule. What keeps
# them is the backup rule of pacman: it leaves a %BACKUP% file whose content
# differs from the package. That is a property of the package, so the
# assertion is that the package still lists both.
#---------------------------------------------------------------------------#
for p in hosts resolv.conf; do
  if [ "$(fact "backup_$p")" = yes ]; then
    ok "/etc/$p is a pacman backup file, so an upgrade keeps the copy of the runtime"
  else
    fail "/etc/$p is a pacman backup file" \
      "the %BACKUP% section of the filesystem package does not list it" \
      "pacman then writes over the mounted copy of the runtime, or fails on it" \
      "this is upstream issue 60. ⛔ NoExtract is not the answer: the package database would list files that are not on disk" \
      "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE pacman -Qii filesystem"
  fi
done

#---------------------------------------------------------------------------#
# 6. A login shell is quiet, and /etc/machine-id is there. Upstream issues
#    107 and 110.
#
# Issue 107 is a script under /etc/profile.d that fails on each login shell,
# so a consumer sees an error before each command. ⚠ The script it names,
# 80-systemd-osc-context.sh, reads /etc/machine-id only when the file exists
# (systemd 261.2). So the assertion is the class, not that one script. The
# count of scripts keeps the quiet check from passing on an empty directory.
#
# Issue 110 needs /etc/machine-id for dbus and systemd in a rootless
# container. machine-id(5) asks an image for an empty file, so each
# container writes its own. Both halves are checked: the two faults are a
# deleted file and the ID of the build left in it.
#---------------------------------------------------------------------------#
PROFILE_SCRIPTS_MIN="${PROFILE_SCRIPTS_MIN:-1}"
scripts="$(fact profile_scripts)"
if [ "${scripts:-0}" -ge "$PROFILE_SCRIPTS_MIN" ]; then
  ok "$scripts scripts run on a login shell, minimum $PROFILE_SCRIPTS_MIN"
else
  fail "at least $PROFILE_SCRIPTS_MIN script runs on a login shell" \
    "counted: ${scripts:-0}" \
    "with none, the next assertion passes because nothing ran, not because nothing failed" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE ls /etc/profile.d/"
fi

noise="$(fact login_noise)"
if [ "${noise:-1}" -eq 0 ]; then
  ok "a login shell writes nothing to stderr"
else
  fail "a login shell writes nothing to stderr" \
    "it wrote ${noise:-unknown} bytes" \
    "each script under /etc/profile.d runs on each login shell, so one that fails shows before each command" \
    "this is the class of upstream issue 107" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE bash -lc true"
fi

mid="$(fact machine_id_bytes)"
case "$mid" in
  absent)
    fail "the image has /etc/machine-id, and it is empty" \
      "the file is not there" \
      "dbus-broker and systemd then do not start in a rootless container: upstream issue 110" \
      "⚠ machine-id(5) asks an image for an empty file, not for no file" \
      "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE ls -l /etc/machine-id"
    ;;
  0)
    ok "/etc/machine-id is there and empty, so each container writes its own"
    ;;
  *)
    fail "the image has /etc/machine-id, and it is empty" \
      "it holds $mid bytes" \
      "an ID written at build time is the ID of each container of this tag, on each host" \
      "machine-id(5) calls the value confidential, and sd_id128_get_machine_app_specific derives IDs from it" \
      "the Dockerfile empties the file, so a value here was written after that step" \
      "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE cat /etc/machine-id"
    ;;
esac

#---------------------------------------------------------------------------#
# 7. A locale outside the Latin alphabet generates. Upstream issues 72, 59
#    and 24.
#
# Three reports of one fault: the image had no locale sources, so locale-gen
# could make nothing new. This image has every source, so ja_JP.UTF-8 must
# generate with no preparation, and then apply.
#---------------------------------------------------------------------------#
CHARMAPS_MIN="${CHARMAPS_MIN:-100}"
LOCALE_SOURCES_MIN="${LOCALE_SOURCES_MIN:-300}"

c="$(fact charmaps)"
if [ "${c:-0}" -ge "$CHARMAPS_MIN" ]; then
  ok "/usr/share/i18n/charmaps holds $c charmaps, minimum $CHARMAPS_MIN"
else
  fail "/usr/share/i18n/charmaps holds at least $CHARMAPS_MIN charmaps" \
    "counted: ${c:-0}" \
    "the official image has 2, so issue 72 has no fix there" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE ls /usr/share/i18n/charmaps"
fi

s="$(fact locale_sources)"
if [ "${s:-0}" -ge "$LOCALE_SOURCES_MIN" ]; then
  ok "/usr/share/i18n/locales holds $s locale sources, minimum $LOCALE_SOURCES_MIN"
else
  fail "/usr/share/i18n/locales holds at least $LOCALE_SOURCES_MIN locale sources" \
    "counted: ${s:-0}" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE ls /usr/share/i18n/locales"
fi

for l in ja_JP zh_CN ru_RU ko_KR; do
  if [ "$(fact "src_$l")" = present ]; then
    ok "/usr/share/i18n/locales/$l is there"
  else
    fail "/usr/share/i18n/locales/$l is there" \
      "it is not there, so locale-gen cannot make $l.UTF-8" \
      "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE ls /usr/share/i18n/locales/$l"
  fi
done

if [ "$(fact locale_gen)" = ok ]; then
  ok "locale-gen runs after ja_JP.UTF-8 is added to /etc/locale.gen"
else
  fail "locale-gen runs after ja_JP.UTF-8 is added to /etc/locale.gen" \
    "it exited with a status that is not 0" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE bash -c 'echo ja_JP.UTF-8 UTF-8 >> /etc/locale.gen; locale-gen'"
fi

if [ "$(fact locale_ja)" = 1 ]; then
  ok "locale -a lists ja_JP.utf8 after the generation"
else
  fail "locale -a lists ja_JP.utf8 after the generation" \
    "locale -a gave it $(fact locale_ja) times" \
    "this is upstream issue 72, asked of this image" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE bash -c 'echo ja_JP.UTF-8 UTF-8 >> /etc/locale.gen; locale-gen; locale -a'"
fi

cm="$(fact locale_ja_charmap)"
if [ "$cm" = "UTF-8" ]; then
  ok "the generated ja_JP.UTF-8 gives the charmap UTF-8"
else
  fail "the generated ja_JP.UTF-8 gives the charmap UTF-8" \
    "it gave: ${cm:-nothing}" \
    "a locale that does not load falls back and gives ANSI_X3.4-1968" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE bash -c 'echo ja_JP.UTF-8 UTF-8 >> /etc/locale.gen; locale-gen; LC_ALL=ja_JP.UTF-8 locale charmap'"
fi

if [ "$(fact locale_ja_applies)" = yes ]; then
  ok "ja_JP.UTF-8 changes what date prints, so the locale data loads"
else
  fail "ja_JP.UTF-8 changes what date prints" \
    "date printed the same day name with LC_ALL=C and with LC_ALL=ja_JP.UTF-8" \
    "a locale can be listed and still have none of its data" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE bash -c 'echo ja_JP.UTF-8 UTF-8 >> /etc/locale.gen; locale-gen; LC_ALL=ja_JP.UTF-8 date +%A'"
fi

#---------------------------------------------------------------------------#
# 8. pacman-key. Upstream issues 18 and 23.
#
# ⛔ The image has no local signing key. The build runs pacman-key --init,
# then removes private-keys-v1.d. So the image has a populated public keyring
# and no private key. A shipped key would be one secret in the image of each
# consumer.
#
# ⚠ The cost is upstream issue 18: pacman-key --lsign-key fails until the
# consumer runs pacman-key --init. The official image makes the same choice.
#
# Issue 23: pacman-key is a shell script that calls awk, gpg and others. A
# missing one shows as a bare "command not found" with a line number.
#---------------------------------------------------------------------------#
keys="$(fact lsign_keys)"
if [ "$keys" = none ] || [ "$keys" = 0 ]; then
  ok "the image has no private signing key in /etc/pacman.d/gnupg"
else
  fail "the image has no private signing key in /etc/pacman.d/gnupg" \
    "private-keys-v1.d holds $keys file(s)" \
    "that key would be the same in the image of each consumer, and it is a secret" \
    "the build runs pacman-key --init and then removes the directory" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE ls -la /etc/pacman.d/gnupg/private-keys-v1.d"
fi

tools="$(fact pacman_key_tools)"
if [ "$tools" = "all present" ]; then
  ok "each tool that pacman-key calls is on PATH"
else
  fail "each tool that pacman-key calls is on PATH" \
    "missing:$tools" \
    "pacman-key is a shell script, so a missing tool shows as command not found with a line number" \
    "this is upstream issue 23: the image had no awk" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE pacman-key --list-keys"
fi

#---------------------------------------------------------------------------#
# 9. The answer of this image to issue 80.
#
# Section 3 measures the fault. This section uses the mechanism that fixes
# it: the probe puts a file where a perl package puts one, runs the script,
# and looks the name up as a consumer does.
#
# ⛔ The shadow case matters more than the link case. A link of a name that
# /usr/bin has would change what an existing command of a consumer resolves
# to. A mechanism that only adds names is safe; one that can replace is not.
#---------------------------------------------------------------------------#
if [ "$(fact bindir_hook)" = present ]; then
  ok "/etc/pacman.d/hooks/bindir-links.hook is in the image"
else
  fail "/etc/pacman.d/hooks/bindir-links.hook is in the image" \
    "it is not there, so a package that installs outside PATH cannot be run by name" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE ls -l /etc/pacman.d/hooks/"
fi

case "$(fact bindir_script)" in
  executable)
    ok "/usr/local/lib/docker-archlinux/bindir-links is there and executable"
    ;;
  'not executable')
    fail "/usr/local/lib/docker-archlinux/bindir-links is executable" \
      "the file is there, and its mode is wrong" \
      "the hook names an interpreter, so it still runs; a consumer cannot run the script by hand" \
      "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE ls -l /usr/local/lib/docker-archlinux/bindir-links"
    ;;
  *)
    fail "/usr/local/lib/docker-archlinux/bindir-links is there" \
      "it is not in the image, and the hook that runs it is" \
      "⛔ that pair fails each transaction of the consumer" \
      "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE ls -l /usr/local/lib/docker-archlinux/"
    ;;
esac

linked="$(fact bindir_linked)"
if [ "$linked" = /usr/local/bin/parity-probe-tool ]; then
  ok "an executable in a perl bindir can be run by name"
else
  fail "an executable in a perl bindir can be run by name" \
    "command -v gave: ${linked:-nothing}" \
    "this is upstream issue 80: podman run <image> exiftool must work, not only bash -lc exiftool" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE bash -c 'mkdir -p /usr/bin/vendor_perl; printf \"#!/bin/sh\" > /usr/bin/vendor_perl/t; chmod 755 /usr/bin/vendor_perl/t; /usr/local/lib/docker-archlinux/bindir-links; command -v t'"
fi

shadow="$(fact bindir_shadow)"
case "$shadow" in
  /usr/local/bin/*)
    fail "the linker never hides a name that already resolves" \
      "command -v bash gave: $shadow" \
      "⛔ the bash of a consumer would now be a file that this image linked" \
      "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE bash -c 'mkdir -p /usr/bin/vendor_perl; printf \"#!/bin/sh\" > /usr/bin/vendor_perl/bash; chmod 755 /usr/bin/vendor_perl/bash; /usr/local/lib/docker-archlinux/bindir-links; command -v bash'"
    ;;
  none | '' | 'not run')
    fail "the linker never hides a name that already resolves" \
      "the probe gave: ${shadow:-nothing}" \
      "⛔ the check did not run, so this assertion shows nothing" \
      "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE command -v bash"
    ;;
  *)
    ok "bash still resolves to $shadow with a file of the same name in a perl bindir"
    ;;
esac

if [ "$(fact bindir_pruned)" = yes ]; then
  ok "a link goes when the executable it names goes"
else
  fail "a link goes when the executable it names goes" \
    "the probe found: $(fact bindir_pruned)" \
    "a link with no target in /usr/local/bin hides nothing and gives a confusing error" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE bash -c 'mkdir -p /usr/bin/vendor_perl; printf \"#!/bin/sh\" > /usr/bin/vendor_perl/t; chmod 755 /usr/bin/vendor_perl/t; /usr/local/lib/docker-archlinux/bindir-links; rm /usr/bin/vendor_perl/t; /usr/local/lib/docker-archlinux/bindir-links; ls -l /usr/local/bin'"
fi

summary
