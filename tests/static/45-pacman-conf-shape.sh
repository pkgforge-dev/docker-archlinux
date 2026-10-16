#!/usr/bin/env bash
#
# The pacman.conf files that ship agree with each other, with the port table,
# and with what consumers of the image expect.
#
# 30-signature-checking-on.sh checks SigLevel. This checks the rest:
#   1. #DisableSandboxFilesystem and #DisableSandboxSyscalls are there, as
#      comments: a consumer on a host without landlock can find them. Neither
#      is uncommented, because that turns the sandbox off for each consumer.
#   2. DownloadUser is not set. Consumer CI often fails when downloads run as
#      an unprivileged user.
#   3. Architecture is the pacman_arch of the port, and no two files have the
#      same one.
#   4. The [options] directives are the same in each file, apart from
#      Architecture.
#   5. The enabled repository sections are the repos of the port, in order.
#   6. The consumer contract: the first line with "SigLevel" is the global
#      SigLevel line (a consumer sed changes that line), the word multilib is
#      not in the file (a consumer enables a #[multilib] block), and there is
#      no uncommented NoExtract.
#   7. ⛔ No uncommented XferCommand. Only use-transport adds one, in the build
#      stage.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

PORTS="$REPO_ROOT/scripts/ports"
DIRECTIVES_MIN="${DIRECTIVES_MIN:-20}"

arches="$("$PORTS" list)"
if [ -z "$arches" ]; then
  fail "scripts/ports lists at least one port" "it printed nothing" \
    "reproduce: scripts/ports list"
  summary
  exit 1
fi

# options_directives FILE -> the setting lines of [options], commented ones
# too, without Architecture. ⚠ The block ends at the next section header, also
# a commented one such as #[core-testing].
options_directives() {
  awk '
    /^\[options\]/       { inblock = 1; next }
    inblock && /^#?\[/   { inblock = 0 }
    inblock && /^#?[A-Za-z]/ && $0 !~ /^Architecture/ { print }
  ' "$1" | tr -d '\r'
}

# architecture_of FILE -> the value of the first Architecture line
architecture_of() {
  awk -F= '
    /^[[:space:]]*Architecture[[:space:]]*=/ {
      gsub(/[[:space:]]/, "", $2)
      print $2
      exit
    }
  ' "$1" | tr -d '\r'
}

# sections_of FILE -> the enabled sections other than [options], on one line
sections_of() {
  awk '
    /^[[:space:]]*\[/ {
      s = $0; sub(/^[[:space:]]*\[/, "", s); sub(/\].*$/, "", s)
      if (s != "options") printf "%s%s", (n++ ? " " : ""), s
    }
    END { print "" }' "$1" | tr -d '\r'
}

reference=""
reference_rel=""
architectures=""

while IFS= read -r arch; do
  [ -n "$arch" ] || continue
  rel="rootfs/$arch/etc/pacman.conf"
  conf="$REPO_ROOT/$rel"
  if [ ! -f "$conf" ]; then
    fail "$rel exists" "ports/$arch.conf names the port" "reproduce: ls $rel"
    continue
  fi

  # 1. The sandbox directives: there, and commented
  missing=""
  for d in DisableSandboxFilesystem DisableSandboxSyscalls; do
    if [ -z "$(grep_matches "^#${d}[[:space:]]*$" "$conf")" ]; then
      missing="$missing $d"
    fi
  done
  if [ -z "$missing" ]; then
    ok "$rel has both DisableSandbox directives, commented"
  else
    fail "$rel has both DisableSandbox directives, commented" \
      "missing:$missing" \
      "a consumer on a host without landlock cannot find a directive that is not in the file" \
      "reproduce: grep -n DisableSandbox $rel"
  fi
  enabled="$(grep_matches '^[[:space:]]*DisableSandbox' "$conf")"
  if [ -z "$enabled" ]; then
    ok "$rel keeps the pacman sandbox on"
  else
    fail "$rel keeps the pacman sandbox on" \
      "found uncommented: $(tr '\n' ' ' <<< "$enabled")" \
      "reproduce: grep -nE '^[[:space:]]*DisableSandbox' $rel"
  fi

  # 2. DownloadUser
  du="$(grep_matches '^[[:space:]]*DownloadUser' "$conf")"
  if [ -z "$du" ]; then
    ok "$rel does not set DownloadUser"
  else
    fail "$rel does not set DownloadUser" \
      "found: $(tr '\n' ' ' <<< "$du")" \
      "reproduce: grep -nE '^[[:space:]]*DownloadUser' $rel"
  fi

  # 3. Architecture
  got="$(architecture_of "$conf")"
  want="$("$PORTS" get "$arch" pacman_arch)"
  if [ -n "$got" ] && [ "$got" = "$want" ]; then
    ok "$rel sets Architecture = $got, the pacman_arch of ports/$arch.conf"
    architectures="$architectures$got
"
  else
    fail "$rel sets Architecture to the pacman_arch of ports/$arch.conf" \
      "pacman.conf: ${got:-nothing}, ports/$arch.conf: $want" \
      "reproduce: grep -n Architecture $rel; scripts/ports get $arch pacman_arch"
  fi

  # 4. The [options] directives
  dirs="$(options_directives "$conf")"
  n="$(awk 'NF { c++ } END { print c + 0 }' <<< "$dirs")"
  if [ -z "$reference_rel" ]; then
    reference="$dirs"
    reference_rel="$rel"
    # ⛔ Without this floor, two empty extractions compare equal.
    if [ "$n" -ge "$DIRECTIVES_MIN" ]; then
      ok "$rel is the reference [options] block, $n directives, at least $DIRECTIVES_MIN"
    else
      fail "the reference [options] block has at least $DIRECTIVES_MIN directives" \
        "read $n from $rel" \
        "reproduce: awk '/^\\[options\\]/,/^#?\\[[a-z]/' $rel"
    fi
  elif [ "$dirs" = "$reference" ]; then
    ok "$rel has the [options] directives of $reference_rel"
  else
    fail "$rel has the [options] directives of $reference_rel" \
      "the blocks differ (Architecture is not compared); each difference is below" \
      "reproduce: diff <(awk '/^\\[options\\]/,/^#?\\[[a-z]/' $reference_rel) <(awk '/^\\[options\\]/,/^#?\\[[a-z]/' $rel)"
    while IFS= read -r line; do
      [ -n "$line" ] && diag "only in $reference_rel: $line"
    done <<< "$(comm -23 <(LC_ALL=C sort <<< "$reference") <(LC_ALL=C sort <<< "$dirs"))"
    while IFS= read -r line; do
      [ -n "$line" ] && diag "only in $rel: $line"
    done <<< "$(comm -13 <(LC_ALL=C sort <<< "$reference") <(LC_ALL=C sort <<< "$dirs"))"
  fi

  # 5. The repository sections
  got="$(sections_of "$conf")"
  want="$("$PORTS" get "$arch" repos)"
  if [ "$got" = "$want" ]; then
    ok "$rel enables [${got// /], [}], the repos of ports/$arch.conf"
  else
    fail "$rel enables the repos of ports/$arch.conf, in order" \
      "pacman.conf: $got" \
      "ports/$arch.conf: $want" \
      "reproduce: grep -n '^\\[' $rel; scripts/ports get $arch repos"
  fi

  # 6. The consumer contract
  first_sig="$(awk '/SigLevel/ { print; exit }' "$conf" | tr -d '\r')"
  if [ -n "$(awk '/^SigLevel[[:space:]]*=/' <<< "$first_sig")" ]; then
    ok "$rel: the first line with SigLevel is the global SigLevel"
  else
    fail "$rel: the first line with SigLevel is the global SigLevel" \
      "the first line with SigLevel: ${first_sig:-none}" \
      "a consumer runs sed '0,/^.*SigLevel\\s*=.*/s//SigLevel = Never/', which changes the first such line" \
      "reproduce: grep -n SigLevel $rel"
  fi
  if [ -z "$(grep_matches 'multilib' "$conf")" ]; then
    ok "$rel does not have the word multilib"
  else
    fail "$rel does not have the word multilib" \
      "found: $(grep_matches 'multilib' "$conf" | tr '\n' ' ')" \
      "a consumer enables a #[multilib] block, which this image has never had" \
      "reproduce: grep -n multilib $rel"
  fi
  if [ -z "$(grep_matches '^[[:space:]]*NoExtract' "$conf")" ]; then
    ok "$rel has no NoExtract rule"
  else
    fail "$rel has no NoExtract rule" \
      "found: $(grep_matches '^[[:space:]]*NoExtract' "$conf" | tr '\n' ' ')" \
      "with a rule, pacman -Ql lists files that are not on the disk" \
      "reproduce: grep -n NoExtract $rel"
  fi

  # 7. XferCommand
  if [ -z "$(grep_matches '^[[:space:]]*XferCommand' "$conf")" ]; then
    ok "$rel has no XferCommand"
  else
    fail "$rel has no XferCommand" \
      "found: $(grep_matches '^[[:space:]]*XferCommand' "$conf" | tr '\n' ' ')" \
      "only use-transport adds one, in the build stage" \
      "reproduce: grep -n XferCommand $rel"
  fi
done <<< "$arches"

# 3. No two files have the same Architecture.
total="$(awk 'NF { n++ } END { print n + 0 }' <<< "$architectures")"
distinct="$(awk 'NF && !s[$0]++ { n++ } END { print n + 0 }' <<< "$architectures")"
if [ "$total" -gt 0 ] && [ "$total" -eq "$distinct" ]; then
  ok "the $total pacman.conf files have $distinct different architectures"
else
  fail "each pacman.conf has a different architecture" \
    "$total files, $distinct values: $(tr '\n' ' ' <<< "$architectures")" \
    "reproduce: grep -n Architecture rootfs/*/etc/pacman.conf"
fi

# Each pacman.conf in rootfs/ belongs to a port.
strays=""
while IFS= read -r conf; do
  [ -n "$conf" ] || continue
  a="${conf#"$REPO_ROOT/rootfs/"}"
  a="${a%%/*}"
  grep -qxF -e "$a" <<< "$arches" || strays="$strays ${conf#"$REPO_ROOT/"}"
done <<< "$(find "$REPO_ROOT/rootfs" -type f -name pacman.conf | LC_ALL=C sort)"
if [ -z "$strays" ]; then
  ok "each pacman.conf in rootfs/ belongs to a port"
else
  fail "each pacman.conf in rootfs/ belongs to a port" \
    "no ports/<arch>.conf for:$strays" \
    "reproduce: scripts/ports list; ls rootfs/*/etc/pacman.conf"
fi

summary
