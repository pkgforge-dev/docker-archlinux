#!/usr/bin/env bash
#
# The contract of the direct consumer of the image.
#
# pkgforge/devscripts Github/Runners/bootstrap/archlinux.sh builds
# pkgforge/archlinux-base: it runs this image and patches it with sed. Each
# patch is a statement about what this image contains. This file checks
# each one.
#
# The test reads files out of a container that it does not start. The suite
# runs on each port, and a foreign port may not run here.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"
image_require

work="$(work_dir)"
cid="$(img_open "$IMAGE" "$PLATFORM")"
# shellcheck disable=SC2064
trap "img_close '$cid'; rm -rf '$work'" EXIT

# repro PATH -> the command that copies PATH out of this image
repro() {
  printf '%s create --platform %s %s true, then %s cp CID:%s .' \
    "$RUNTIME" "$PLATFORM" "$IMAGE" "$RUNTIME" "$1"
}

#---------------------------------------------------------------------------#
# 1. The SigLevel patch acts on the first match.
#
# The consumer runs
#   sed '0,/^.*SigLevel\s*=.*/s//SigLevel = Never/' -i /etc/pacman.conf
# which changes the FIRST line that matches SigLevel. That must be the global
# line under [options]. LocalFileSigLevel matches the pattern too: above the
# global line, it would take the patch, and signature checks would stay on
# where the consumer expects them off.
#---------------------------------------------------------------------------#
if img_extract "$cid" /etc/pacman.conf "$work/pacman.conf" >/dev/null 2>>"$work/err"; then
  ok "/etc/pacman.conf is in $IMAGE on $PLATFORM"

  first="$(grep_matches 'SigLevel' "$work/pacman.conf" | awk 'NR == 1')"
  case "$first" in
    *'LocalFileSigLevel'* | *'RemoteFileSigLevel'*)
      fail "the first SigLevel line of /etc/pacman.conf is the global one" \
        "found: $first" \
        "the consumer patches the first match, so this line takes its patch" \
        "reproduce: $(repro /etc/pacman.conf), then grep -n SigLevel"
      ;;
    '')
      fail "/etc/pacman.conf has a SigLevel line" \
        "no line matches SigLevel" \
        "with none, the patch of the consumer does nothing and signature checks stay on" \
        "reproduce: $(repro /etc/pacman.conf), then grep -n SigLevel"
      ;;
    *)
      ok "the first SigLevel line is the global one: ${first#*:}"
      ;;
  esac

  # 2. Signature checks are on in the shipped config.
  if grep -qE '^[[:space:]]*SigLevel[[:space:]]*=[[:space:]]*Required' "$work/pacman.conf"; then
    ok "SigLevel is Required in the shipped /etc/pacman.conf"
  else
    fail "SigLevel is Required in the shipped /etc/pacman.conf" \
      "found: $(grep_matches '^[[:space:]]*SigLevel' "$work/pacman.conf" | awk 'NR == 1')" \
      "reproduce: $(repro /etc/pacman.conf), then grep -E '^SigLevel'"
  fi

  #-------------------------------------------------------------------------#
  # 3. No multilib block.
  #
  # The consumer uncomments a #[multilib] block. This image has none, so that
  # sed changes nothing. A block here would turn on a repository in the image
  # of the consumer. This assertion makes that a change that a person sees.
  #-------------------------------------------------------------------------#
  hits="$(grep_matches 'multilib' "$work/pacman.conf")"
  if [ -z "$hits" ]; then
    ok "/etc/pacman.conf has no multilib block"
  else
    fail "/etc/pacman.conf has no multilib block" \
      "found: $(printf '%s' "$hits" | tr '\n' ' ')" \
      "the consumer uncomments this block, so a block here turns multilib on in its image" \
      "to add it, change this test and say so in the commit" \
      "reproduce: $(repro /etc/pacman.conf), then grep -n multilib"
  fi
else
  fail "/etc/pacman.conf is in $IMAGE on $PLATFORM" \
    "runtime said: $(tr -d '\r' < "$work/err" | tail -1)" \
    "reproduce: $(repro /etc/pacman.conf)"
fi

#---------------------------------------------------------------------------#
# 4. The keyring is populated.
#
# The first command of the consumer is pacman -Syu, before it sets
# SigLevel = Never. That upgrade checks signatures, so an image with no
# trusted key fails the consumer at its first command.
#---------------------------------------------------------------------------#
if img_extract "$cid" /etc/pacman.d/gnupg/pubring.gpg "$work/pubring.gpg" >/dev/null 2>>"$work/err"; then
  size="$(wc -c < "$work/pubring.gpg" | tr -d '[:space:]')"
  if [ "$size" -gt 0 ]; then
    ok "the pacman keyring is populated ($size bytes of pubring.gpg)"
  else
    fail "the pacman keyring is populated" \
      "pubring.gpg is $size bytes" \
      "reproduce: $(repro /etc/pacman.d/gnupg/pubring.gpg)"
  fi
else
  fail "the pacman keyring is populated" \
    "runtime said: $(tr -d '\r' < "$work/err" | tail -1)" \
    "the build must run pacman-key --init and --populate" \
    "reproduce: $(repro /etc/pacman.d/gnupg/pubring.gpg)"
fi

#---------------------------------------------------------------------------#
# 5. locale-gen and its data are there.
#
# The consumer appends to /etc/locale.gen and runs locale-gen, which reads
# the charmaps and the locale sources under usr/share/i18n. Without them it
# generates no locale, and the next line of the consumer fails. The image
# has no NoExtract rule, so the whole tree is on disk.
#---------------------------------------------------------------------------#
if img_extract "$cid" /usr/bin/locale-gen "$work/locale-gen" >/dev/null 2>>"$work/err"; then
  ok "locale-gen is in the image"
else
  fail "locale-gen is in the image" \
    "runtime said: $(tr -d '\r' < "$work/err" | tail -1)" \
    "the consumer runs locale-gen after it appends to /etc/locale.gen" \
    "reproduce: $(repro /usr/bin/locale-gen)"
fi

if img_extract "$cid" /usr/share/i18n/charmaps/UTF-8.gz "$work/UTF-8.gz" >/dev/null 2>>"$work/err"; then
  size="$(wc -c < "$work/UTF-8.gz" | tr -d '[:space:]')"
  if [ "$size" -gt 0 ]; then
    ok "the UTF-8 charmap is in the image ($size bytes)"
  else
    fail "the UTF-8 charmap is in the image" "the file is $size bytes" \
      "reproduce: $(repro /usr/share/i18n/charmaps/UTF-8.gz)"
  fi
else
  fail "the UTF-8 charmap is in the image" \
    "runtime said: $(tr -d '\r' < "$work/err" | tail -1)" \
    "locale-gen reads this file, so without it no locale is generated" \
    "reproduce: $(repro /usr/share/i18n/charmaps/UTF-8.gz)"
fi

#---------------------------------------------------------------------------#
# 6. Root cannot log in with no password.
#
# archlinux/archlinux-docker scripts/make-rootfs.sh:76 changes root:: to
# root:! (CVE-2019-5021). The filesystem package of Arch sets root:*, and
# this assertion keeps it so.
#---------------------------------------------------------------------------#
if img_extract "$cid" /etc/shadow "$work/shadow" >/dev/null 2>>"$work/err"; then
  # awk on the file, not grep_matches: the field positions matter here, and
  # grep_matches puts a line number first.
  rootline="$(awk '/^root:/ && !seen { print; seen = 1 }' "$work/shadow")"
  hash="$(printf '%s' "$rootline" | cut -d: -f2)"
  case "$hash" in
    '')
      fail "the password field of root in /etc/shadow is not empty" \
        "found: $rootline" \
        "an empty second field lets any process become root with no password" \
        "this is the shape of CVE-2019-5021, see archlinux-docker make-rootfs.sh:76" \
        "reproduce: $(repro /etc/shadow), then grep '^root:'"
      ;;
    *)
      ok "the password field of root is '$hash', so a password login is refused"
      ;;
  esac
else
  fail "/etc/shadow is in $IMAGE on $PLATFORM" \
    "runtime said: $(tr -d '\r' < "$work/err" | tail -1)" \
    "reproduce: $(repro /etc/shadow)"
fi

summary
