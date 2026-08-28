#!/usr/bin/env bash
#
# The contract the direct consumer depends on.
#
# pkgforge/devscripts Github/Runners/bootstrap/archlinux.sh builds
# pkgforge/archlinux-base by running this image and patching it with sed. Every
# patch it makes is a statement about what this image contains, and none of
# those statements was checked anywhere until now. The script is studied in
# HISTORY/references/devscripts-archlinux.md, which carries the line numbers.
#
# The image is inspected rather than run, because the suite runs against every
# architecture the matrix builds and a foreign one cannot execute.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"
image_require

work="$(work_dir)"
cid="$(img_open "$IMAGE" "$PLATFORM")"
# shellcheck disable=SC2064
trap "img_close '$cid'; rm -rf '$work'" EXIT

# repro PATH -> the command that puts PATH from this image on the host
repro() {
  printf '%s create --platform %s %s true, then %s cp CID:%s .' \
    "$RUNTIME" "$PLATFORM" "$IMAGE" "$RUNTIME" "$1"
}

#---------------------------------------------------------------------------#
# 1. The SigLevel patch is positional.
#
# archlinux.sh line 24 is
#   sed '0,/^.*SigLevel\s*=.*/s//SigLevel = Never/' -i /etc/pacman.conf
# which rewrites the FIRST line matching SigLevel. That must be the global
# setting under [options]. LocalFileSigLevel also matches the pattern, so if it
# ever moved above the global line the consumer would silently keep signature
# checking on where it expects it off.
#---------------------------------------------------------------------------#
if img_extract "$cid" /etc/pacman.conf "$work/pacman.conf" >/dev/null 2>>"$work/err"; then
  ok "/etc/pacman.conf exists in $IMAGE on $PLATFORM"

  first="$(grep_matches 'SigLevel' "$work/pacman.conf" | awk 'NR == 1')"
  case "$first" in
    *'LocalFileSigLevel'* | *'RemoteFileSigLevel'*)
      fail "the first SigLevel line in /etc/pacman.conf is the global one" \
        "found instead: $first" \
        "the direct consumer patches the first match, so this redirects its patch" \
        "see HISTORY/references/devscripts-archlinux.md, finding 2" \
        "reproduce: $(repro /etc/pacman.conf), then grep -n SigLevel"
      ;;
    '')
      fail "/etc/pacman.conf carries a SigLevel line" \
        "no line matched SigLevel at all" \
        "with none, the consumer's patch is a no-op and signature checking stays on" \
        "reproduce: $(repro /etc/pacman.conf), then grep -n SigLevel"
      ;;
    *)
      ok "the first SigLevel line is the global one: ${first#*:}"
      ;;
  esac

  # 2. Signature checking is on in the shipped config. Policy 5.
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
  # archlinux.sh line 26 uncomments a #[multilib] block. This image has never
  # carried one, so that sed has always been a no-op here. Adding the block
  # would switch a repository on in the consumer's image that has never been on,
  # which policy 7 forbids doing silently. This assertion makes adding it a
  # deliberate change rather than a quiet one.
  #-------------------------------------------------------------------------#
  hits="$(grep_matches 'multilib' "$work/pacman.conf")"
  if [ -z "$hits" ]; then
    ok "/etc/pacman.conf carries no multilib block, as the consumer has always seen"
  else
    fail "/etc/pacman.conf carries no multilib block" \
      "found: $(printf '%s' "$hits" | tr '\n' ' ')" \
      "the direct consumer uncomments this block, so adding it enables multilib downstream" \
      "if this is deliberate, update this test and say so in the commit" \
      "reproduce: $(repro /etc/pacman.conf), then grep -n multilib"
  fi
else
  fail "/etc/pacman.conf exists in $IMAGE on $PLATFORM" \
    "runtime said: $(tr -d '\r' < "$work/err" | tail -1)" \
    "reproduce: $(repro /etc/pacman.conf)"
fi

#---------------------------------------------------------------------------#
# 4. The keyring is populated.
#
# archlinux.sh line 17 runs a full pacman -Syu as its first operation, seven
# lines before it sets SigLevel = Never. That upgrade verifies signatures, so an
# image with no trusted keys fails the consumer on its first command.
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
    "pacman-key --init and --populate must run in the build" \
    "reproduce: $(repro /etc/pacman.d/gnupg/pubring.gpg)"
fi

#---------------------------------------------------------------------------#
# 5. locale-gen and the data it needs are present.
#
# archlinux.sh lines 43 to 45 append to /etc/locale.gen and run locale-gen,
# which reads the charmaps and locale definitions under usr/share/i18n. An
# image missing either generates no locale at all, and the consumer's own build
# fails on the line after. The image ships no NoExtract rule, so the whole tree
# is on disk. HISTORY/noextract-reverted.md.
#---------------------------------------------------------------------------#
if img_extract "$cid" /usr/bin/locale-gen "$work/locale-gen" >/dev/null 2>>"$work/err"; then
  ok "locale-gen is present"
else
  fail "locale-gen is present" \
    "runtime said: $(tr -d '\r' < "$work/err" | tail -1)" \
    "the direct consumer runs locale-gen after appending to /etc/locale.gen" \
    "reproduce: $(repro /usr/bin/locale-gen)"
fi

if img_extract "$cid" /usr/share/i18n/charmaps/UTF-8.gz "$work/UTF-8.gz" >/dev/null 2>>"$work/err"; then
  size="$(wc -c < "$work/UTF-8.gz" | tr -d '[:space:]')"
  if [ "$size" -gt 0 ]; then
    ok "the UTF-8 charmap is present ($size bytes)"
  else
    fail "the UTF-8 charmap is present" "the file is $size bytes" \
      "reproduce: $(repro /usr/share/i18n/charmaps/UTF-8.gz)"
  fi
else
  fail "the UTF-8 charmap is present" \
    "runtime said: $(tr -d '\r' < "$work/err" | tail -1)" \
    "locale-gen reads this file, so an image without it generates no locale" \
    "reproduce: $(repro /usr/share/i18n/charmaps/UTF-8.gz)"
fi

#---------------------------------------------------------------------------#
# 6. Root cannot log in without a password.
#
# archlinux/archlinux-docker scripts/make-rootfs.sh:76 rewrites root:: to root:!
# citing CVE-2019-5021. Arch's filesystem package ships root:* so the defect is
# not present here, and this assertion is what keeps it that way.
#---------------------------------------------------------------------------#
if img_extract "$cid" /etc/shadow "$work/shadow" >/dev/null 2>>"$work/err"; then
  # awk on the file, not grep_matches, because the field positions matter here
  # and grep_matches prefixes a line number.
  rootline="$(awk '/^root:/ && !seen { print; seen = 1 }' "$work/shadow")"
  hash="$(printf '%s' "$rootline" | cut -d: -f2)"
  case "$hash" in
    '')
      fail "root has no empty password field in /etc/shadow" \
        "found: $rootline" \
        "an empty second field lets any process become root with no password" \
        "this is the CVE-2019-5021 shape, see archlinux-docker make-rootfs.sh:76" \
        "reproduce: $(repro /etc/shadow), then grep '^root:'"
      ;;
    *)
      ok "root's password field is set to '$hash', so password login is refused"
      ;;
  esac
else
  fail "/etc/shadow exists in $IMAGE on $PLATFORM" \
    "runtime said: $(tr -d '\r' < "$work/err" | tail -1)" \
    "reproduce: $(repro /etc/shadow)"
fi

summary
