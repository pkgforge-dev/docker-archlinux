#!/usr/bin/env bash
#
# The bootstrap must not depend on an image this repository publishes.
#
# Build N+1 bootstrapping from build N means a defect in build N is inherited
# and cannot be recovered from. That is why the riscv64 CA bundle failure was
# permanent rather than transient. It also means the build cannot be reproduced
# by anyone who does not already trust this project's own output.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

DF="$REPO_ROOT/Dockerfile"

if [ ! -f "$DF" ]; then
  fail "Dockerfile exists" "expected: $DF"
  summary
  exit 1
fi

# The two names this repository publishes to. A FROM naming either is circular.
OWN_IMAGES='(^|/)pkgforge(-dev)?/archlinux(:|@|$)'

from_lines="$(grep_matches '^[[:space:]]*FROM[[:space:]]' "$DF")"

if [ -z "$from_lines" ]; then
  fail "Dockerfile has at least one FROM" "no uncommented FROM found in $DF"
  summary
  exit 1
fi

circular=0
unpinned=0

while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  lineno="${entry%%:*}"
  text="${entry#*:}"
  # FROM may carry flags such as --platform, so the image is the first
  # token after FROM that does not begin with a dash
  image="$(awk '{ for (j = 2; j <= NF; j++) if (substr($j, 1, 1) != "-") { print $j; exit } }' <<< "$text")"

  if printf '%s\n' "$image" | grep -qE "$OWN_IMAGES"; then
    fail "FROM does not reference an image this repository publishes" \
      "Dockerfile:$lineno names $image" \
      "build N+1 would bootstrap from build N, so a defect in N is inherited" \
      "reproduce: grep -nE '^[[:space:]]*FROM[[:space:]]' Dockerfile"
    circular=1
  fi

  if [ "$image" != "scratch" ] && ! printf '%s\n' "$image" | grep -qE '@sha256:[0-9a-f]{64}'; then
    fail "every base image is pinned by digest" \
      "Dockerfile:$lineno names $image" \
      "a tag is not a pin, see standing policy 10"
    unpinned=1
  fi
done <<< "$from_lines"

if [ "$circular" -eq 0 ]; then
  ok "no FROM references an image this repository publishes"
fi
if [ "$unpinned" -eq 0 ]; then
  ok "every non-scratch base image is pinned by digest"
fi

summary
