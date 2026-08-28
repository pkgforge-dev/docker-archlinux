#!/usr/bin/env bash
#
# Every shipped pacman.conf must agree with the others, and must keep the two choices
# that were made deliberately.
#
# `30-signature-checking-on.sh` covers SigLevel. This covers the rest of the
# [options] block, which governs how pacman behaves for every consumer of the
# image and is maintained as one hand-edited copy per architecture. Drift is the
# failure this exists to catch: a setting added to one architecture and
# forgotten on the rest produces a set of images that are no longer one
# release.
#
# The two deliberate choices, both measured in HISTORY/defect-parity.md:
#
#   DownloadUser            ⛔ not set, where stock pacman sets it to alpm.
#                           Dropping downloads to an unprivileged user breaks
#                           enough consumer CI that patching it back out is a
#                           common workaround.
#   DisableSandbox*         present as comments, where they were absent
#                           altogether. A consumer on a host without landlock
#                           needs the directive name to be findable. ⛔ Neither
#                           may be uncommented: that would turn the sandbox off
#                           for everybody.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

confs="$(find "$REPO_ROOT/rootfs" -type f -name pacman.conf | sort)"

if [ -z "$confs" ]; then
  fail "at least one shipped pacman.conf exists" \
    "searched: $REPO_ROOT/rootfs" \
    "reproduce: ls rootfs/*/etc/pacman.conf"
  summary
  exit 1
fi

#---------------------------------------------------------------------------#
# options_directives FILE -> the setting lines of the [options] block
#
# One per line, commented settings included, with the per architecture
# Architecture line removed so the files can be compared.
#
# ⚠ The block ends at the next section header whether or not it is commented
# out. `#[core-testing]` starts a repository section, and reading past it pulls
# that section's `#Include` into the options block on the one architecture that
# ships it.
#---------------------------------------------------------------------------#
options_directives() {
  awk '
    /^\[options\]/       { inblock = 1; next }
    inblock && /^#?\[/   { inblock = 0 }
    inblock && /^#?[A-Za-z]/ && $0 !~ /^Architecture/ { print }
  ' "$1" | tr -d '\r'
}

# architecture_of FILE -> the value of the single Architecture line
architecture_of() {
  awk -F= '
    /^[[:space:]]*Architecture[[:space:]]*=/ {
      gsub(/[[:space:]]/, "", $2)
      print $2
      exit
    }
  ' "$1" | tr -d '\r'
}

DIRECTIVES_MIN="${DIRECTIVES_MIN:-20}"

reference=""
reference_rel=""
architectures=""

while IFS= read -r conf; do
  [ -n "$conf" ] || continue
  rel="${conf#"$REPO_ROOT/"}"

  #-------------------------------------------------------------------------#
  # 1. The sandbox directives are present, and are comments.
  #-------------------------------------------------------------------------#
  missing=""
  for d in DisableSandboxFilesystem DisableSandboxSyscalls; do
    if [ -z "$(grep_matches "^#${d}[[:space:]]*$" "$conf")" ]; then
      missing="$missing $d"
    fi
  done
  if [ -z "$missing" ]; then
    ok "$rel carries both DisableSandbox directives, commented"
  else
    fail "$rel carries both DisableSandbox directives, commented" \
      "missing:$missing" \
      "a consumer on a host without landlock cannot find a directive that is not in the file" \
      "this is the shape of upstream issue 58, a commented default dropped" \
      "reproduce: grep -n DisableSandbox $rel"
  fi

  enabled="$(grep_matches '^[[:space:]]*DisableSandbox' "$conf")"
  if [ -z "$enabled" ]; then
    ok "$rel leaves the pacman sandbox on"
  else
    fail "$rel leaves the pacman sandbox on" \
      "found uncommented: $(printf '%s' "$enabled" | tr '\n' ' ')" \
      "uncommenting either turns the sandbox off for every consumer of the image" \
      "policy 5 says reduce the surface, and pacman 7.1.0 needs neither" \
      "reproduce: grep -nE '^[[:space:]]*DisableSandbox' $rel"
  fi

  #-------------------------------------------------------------------------#
  # 2. DownloadUser stays unset. Recorded choice, not an oversight.
  #-------------------------------------------------------------------------#
  du="$(grep_matches '^[[:space:]]*DownloadUser' "$conf")"
  if [ -z "$du" ]; then
    ok "$rel does not set DownloadUser"
  else
    fail "$rel does not set DownloadUser" \
      "found: $(printf '%s' "$du" | tr '\n' ' ')" \
      "stock pacman sets it to alpm and consumer CI breaks on it often enough that patching it out is a common workaround" \
      "if this is deliberate, update this test and the comment in the config and say so in the commit" \
      "reproduce: grep -nE '^[[:space:]]*DownloadUser' $rel"
  fi

  #-------------------------------------------------------------------------#
  # 3. Exactly one Architecture, and no two files claim the same one.
  #-------------------------------------------------------------------------#
  arch="$(architecture_of "$conf")"
  if [ -z "$arch" ] || [ "$arch" = auto ]; then
    fail "$rel sets Architecture to one named architecture" \
      "found: ${arch:-nothing}" \
      "pacman -r reads this file to decide what to install, so auto installs the builder's architecture into the target root" \
      "reproduce: grep -n Architecture $rel"
  else
    ok "$rel sets Architecture = $arch"
    architectures="$architectures$arch
"
  fi

  #-------------------------------------------------------------------------#
  # 4. The options block agrees with the first file read.
  #-------------------------------------------------------------------------#
  dirs="$(options_directives "$conf")"
  n="$(printf '%s\n' "$dirs" | awk 'NF' | wc -l | tr -d '[:space:]')"
  if [ -z "$reference_rel" ]; then
    reference="$dirs"
    reference_rel="$rel"
    # ⛔ Without this floor the comparison below is free to pass on nothing. An
    # extraction that returns an empty list for every file makes them all
    # compare equal, and the test reports a pass per file having read no directive
    # at all.
    if [ "$n" -ge "$DIRECTIVES_MIN" ]; then
      ok "$rel is the reference options block, $n directives, minimum $DIRECTIVES_MIN"
    else
      fail "the reference options block holds at least $DIRECTIVES_MIN directives" \
        "read $n from $rel" \
        "the comparisons below pass on two empty lists, so a broken extraction reports success" \
        "reproduce: bash tests/static/45-pacman-conf-shape.sh, and read what it counted"
    fi
  elif [ "$dirs" = "$reference" ]; then
    ok "$rel has the same options directives as $reference_rel"
  else
    fail "$rel has the same options directives as $reference_rel" \
      "the [options] blocks differ, so the architectures no longer build the same way" \
      "Architecture is excluded from this comparison, and the repository sections are not compared at all" \
      "the two lists are printed below, one line per directive" \
      "reproduce: bash tests/static/45-pacman-conf-shape.sh, which names every directive that differs"
    while IFS= read -r line; do
      [ -n "$line" ] && diag "only in $reference_rel: $line"
    done <<< "$(comm -23 <(printf '%s\n' "$reference" | LC_ALL=C sort) <(printf '%s\n' "$dirs" | LC_ALL=C sort))"
    while IFS= read -r line; do
      [ -n "$line" ] && diag "only in $rel: $line"
    done <<< "$(comm -13 <(printf '%s\n' "$reference" | LC_ALL=C sort) <(printf '%s\n' "$dirs" | LC_ALL=C sort))"
  fi
done <<< "$confs"

#---------------------------------------------------------------------------#
# 5. No architecture is claimed twice.
#
# Several files that all say x86_64 build one image several times and publish it
# under several names, which no other test in the suite would notice.
#---------------------------------------------------------------------------#
total="$(printf '%s\n' "$architectures" | awk 'NF' | wc -l | tr -d '[:space:]')"
distinct="$(printf '%s\n' "$architectures" | awk 'NF' | LC_ALL=C sort -u | wc -l | tr -d '[:space:]')"
if [ "$total" -gt 0 ] && [ "$total" -eq "$distinct" ]; then
  ok "the $total shipped configs name $distinct distinct architectures"
else
  fail "each shipped config names a different architecture" \
    "$total configs, $distinct distinct values: $(printf '%s' "$architectures" | tr '\n' ' ')" \
    "two files naming one architecture builds the same image twice and publishes it under both names" \
    "reproduce: grep -n Architecture rootfs/*/etc/pacman.conf"
fi

summary
