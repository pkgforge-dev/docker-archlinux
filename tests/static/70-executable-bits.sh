#!/usr/bin/env bash
#
# Everything invoked as a command must be executable in the index.
#
# The working tree is not the authority here. A file can be executable on a
# developer's machine and land in git at mode 100644, because Windows has no
# execute bit for git to record. CI then checks out a file it cannot run, and
# the failure is a bare "Permission denied" a long way from the cause.
#
# This reads git's index, not the filesystem, so it catches exactly that case.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

if ! command -v git >/dev/null; then
  fail "git is available" "this test reads the index with git ls-files" \
    "reproduce: command -v git"
  summary
  exit 1
fi

cd "$REPO_ROOT"

# Paths the workflows and the Dockerfile invoke as commands, plus the suites.
must_be_executable() {
  # every script in scripts/, which the workflows call directly
  if [ -d scripts ]; then
    find scripts -type f
  fi
  # bootstrap/any lands on PATH inside the build stage and is run by name
  if [ -d bootstrap/any/usr/local/bin ]; then
    find bootstrap/any/usr/local/bin -type f
  fi
  # rootfs/any ships into the image. The hook that runs this names the
  # interpreter, so it survives a lost bit, but its own header tells a reader
  # they may run it by hand and that path needs the mode to be right.
  if [ -d rootfs/any/usr/local/lib/docker-archlinux ]; then
    find rootfs/any/usr/local/lib/docker-archlinux -type f
  fi
  # the suite entry point, and every test file
  if [ -f tests/run.sh ]; then
    printf '%s\n' tests/run.sh
  fi
  find tests/static tests/image -maxdepth 1 -type f -name '*.sh'
}

targets="$(must_be_executable | sort -u)"
if [ -z "$targets" ]; then
  fail "there is something to check" "no scripts, bootstrap binaries or test files found" \
    "reproduce: ls scripts bootstrap/any/usr/local/bin tests/static tests/image"
  summary
  exit 1
fi

# Read into an array rather than relying on word splitting, so a path with a
# space in it stays one argument.
target_list=()
while IFS= read -r t; do
  [ -n "$t" ] || continue
  target_list+=("$t")
done <<< "$targets"

# git ls-files --stage prints: <mode> <object> <stage>\t<path>
modes="$(git ls-files --stage -- "${target_list[@]}")"

not_executable=""
untracked=""
while IFS= read -r path; do
  [ -n "$path" ] || continue
  mode="$(awk -v p="$path" -F'\t' '$2 == p { split($1, a, " "); print a[1]; exit }' <<< "$modes")"
  if [ -z "$mode" ]; then
    untracked="$untracked $path"
    continue
  fi
  case "$mode" in
    100755) ;;
    *) not_executable="$not_executable $path($mode)" ;;
  esac
done <<< "$targets"

count="$(awk 'NF' <<< "$targets" | wc -l | tr -d '[:space:]')"

if [ -z "$not_executable" ]; then
  ok "all $count invoked files are mode 100755 in the index"
else
  fail "every invoked file is executable in the index" \
    "not executable:$not_executable" \
    "the working tree can disagree with the index on Windows, and CI uses the index" \
    "fix with: git update-index --chmod=+x <path>" \
    "reproduce: git ls-files -s <path>, where a mode of 100644 is the defect"
fi

if [ -z "$untracked" ]; then
  ok "every invoked file is tracked by git"
else
  fail "every invoked file is tracked by git" \
    "untracked:$untracked" \
    "a file CI cannot check out cannot run" \
    "reproduce: git add <path>"
fi

summary
