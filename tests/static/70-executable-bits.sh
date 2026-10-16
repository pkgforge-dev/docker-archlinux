#!/usr/bin/env bash
#
# Check the file modes in the git index.
#
# CI checks out the modes of the index, not of a work tree. Windows has no
# execute bit, so a script can work on one machine and land at 100644.
#
#   - each file with a #! line is 100755, and each 100755 file has one
#   - each file that a workflow or the Dockerfile runs by path is tracked and
#     100755: scripts/*, bootstrap/any/usr/local/bin/*,
#     rootfs/any/usr/local/lib/docker-archlinux/*, tests/run.sh and
#     tests/{static,image,network}/*.sh
#   - a sourced file is tracked, 100644, and has no #! line. A sourced file
#     is scripts/*.sh or tests/lib/*.sh: a script has no extension.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

cd "$REPO_ROOT"
if ! need_tool git; then
  rc=0
  summary || rc=$?
  exit "$rc"
fi
work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

rc=0
git ls-files --stage -z > "$work/index" || rc=$?
if [ "$rc" -ne 0 ]; then
  fail "git reads the index" "git ls-files exited $rc" "reproduce: git ls-files --stage"
  summary
  exit 1
fi

SOURCED=" $(find scripts tests/lib -maxdepth 1 -type f -name '*.sh' | LC_ALL=C sort | tr '\n' ' ')"

declare -A mode=()
while IFS= read -r -d '' entry; do
  m="${entry%% *}"
  path="${entry#*$'\t'}"
  mode[$path]="$m"
done < "$work/index"

# first_two PATH: set FIRST to the first two characters of PATH, or less.
# read is a builtin, so a check of every tracked file starts no process.
first_two() {
  local rc=0
  FIRST=""
  IFS= read -r -n 2 FIRST < "$1" || rc=$?
  [ "$rc" -le 1 ] || echo "70-executable-bits: read of $1 exited $rc" >&2
}

# 1. #! line and mode agree, over every tracked file.
disagree=""
n=0
for path in "${!mode[@]}"; do
  [ -f "$path" ] || continue
  case " $SOURCED " in *" $path "*) continue ;; esac
  case "${mode[$path]}" in
    100644 | 100755) ;;
    *) continue ;;
  esac
  n=$((n + 1))
  first_two "$path"
  if [ "$FIRST" = '#!' ] && [ "${mode[$path]}" != 100755 ]; then
    disagree="$disagree $path(#! line, ${mode[$path]})"
  elif [ "$FIRST" != '#!' ] && [ "${mode[$path]}" = 100755 ]; then
    disagree="$disagree $path(no #! line, 100755)"
  fi
done
check_eq "each of $n tracked files has a #! line exactly when it is 100755" "" "$disagree" \
  "git ls-files -s PATH; fix with git update-index --chmod=+x PATH (or -x)"

# 2. The files run by path. Python bytecode is not run by path, and git
# ignores it (.gitignore).
mapfile -t run_by_path < <({
  for d in scripts bootstrap/any/usr/local/bin rootfs/any/usr/local/lib/docker-archlinux; do
    [ ! -d "$d" ] || find "$d" -type f -not -path '*/__pycache__/*' -not -name '*.pyc'
  done
  [ ! -f tests/run.sh ] || printf '%s\n' tests/run.sh
  for d in tests/static tests/image tests/network; do
    [ ! -d "$d" ] || find "$d" -maxdepth 1 -type f -name '*.sh'
  done
} | LC_ALL=C sort)
untracked=""
not_exec=""
for path in "${run_by_path[@]}"; do
  case " $SOURCED " in *" $path "*) continue ;; esac
  if [ -z "${mode[$path]:-}" ]; then
    untracked="$untracked $path"
  elif [ "${mode[$path]}" != 100755 ]; then
    not_exec="$not_exec $path(${mode[$path]})"
  fi
done
check_eq "each of ${#run_by_path[@]} files run by path is tracked" "" "$untracked" \
  "git add PATH; CI cannot run a file that is not in the commit"
check_eq "each file run by path is 100755 in the index" "" "$not_exec" \
  "git ls-files -s PATH; fix with git update-index --chmod=+x PATH"
# ⛔ git add -A must not stage bytecode: CI would then find a file under
# scripts/ that is not 100755.
not_ignored=""
for path in scripts/__pycache__/status-render.cpython-314.pyc examples/x.pyc; do
  rc=0
  git check-ignore -q --no-index "$path" || rc=$?
  [ "$rc" -eq 0 ] || not_ignored="$not_ignored $path(check-ignore exit $rc)"
done
check_eq "git ignores python bytecode" "" "$not_ignored" \
  "git check-ignore -v --no-index scripts/__pycache__/status-render.cpython-314.pyc examples/x.pyc"

# 3. The sourced files.
bad=""
n_sourced=0
for path in $SOURCED; do
  n_sourced=$((n_sourced + 1))
  if [ ! -f "$path" ]; then
    bad="$bad $path(absent)"
  elif [ -z "${mode[$path]:-}" ]; then
    bad="$bad $path(not tracked)"
  elif [ "${mode[$path]}" != 100644 ]; then
    bad="$bad $path(${mode[$path]})"
  else
    first_two "$path"
    [ "$FIRST" != '#!' ] || bad="$bad $path(#! line)"
  fi
done
[ "$n_sourced" -gt 0 ] || bad="no scripts/*.sh or tests/lib/*.sh found"
check_eq "each of $n_sourced sourced files is tracked, 100644, with no #! line" "" "$bad" \
  "git ls-files -s$SOURCED; head -n 1$SOURCED"

summary
