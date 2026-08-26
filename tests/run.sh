#!/usr/bin/env bash
#
# Test entry point.
#
#   tests/run.sh static            repository tree, no container runtime needed
#   tests/run.sh image             needs IMAGE and PLATFORM
#   tests/run.sh all               both
#
# Image suite:
#   IMAGE=ghcr.io/pkgforge-dev/archlinux:latest PLATFORM=linux/riscv64 tests/run.sh image
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

suite="${1:-static}"

case "$suite" in
  static | image) suites="$suite" ;;
  all) suites="static image" ;;
  *)
    echo "usage: tests/run.sh [static|image|all]" >&2
    exit 2
    ;;
esac

if printf '%s\n' "$suites" | grep -qw image; then
  : "${IMAGE:?the image suite needs IMAGE set}"
  : "${PLATFORM:?the image suite needs PLATFORM set, for example linux/riscv64}"
fi

failed_files=0
total_files=0

for s in $suites; do
  for t in "$REPO_ROOT/tests/$s"/*.sh; do
    [ -e "$t" ] || continue
    total_files=$((total_files + 1))
    printf '\n# ===== %s/%s =====\n' "$s" "$(basename "$t")"
    if ! bash "$t"; then
      failed_files=$((failed_files + 1))
    fi
  done
done

printf '\n# ===== summary =====\n'
if [ "$total_files" -eq 0 ]; then
  printf '# no test files found for suite: %s\n' "$suites"
  exit 1
fi
printf '# test files: %d, failed: %d\n' "$total_files" "$failed_files"
[ "$failed_files" -eq 0 ]
