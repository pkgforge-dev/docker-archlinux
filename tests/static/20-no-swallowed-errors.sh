#!/usr/bin/env bash
#
# Check that no code hides a failure.
#
# The constructs: continue-on-error, "|| true", "set +e", stderr sent to
# /dev/null, and stdout with stderr sent to /dev/null. Each one can turn a
# failed step into a green one with no message.
#
# Read: the workflows, the Dockerfile, scripts/, bootstrap/any/usr/local/bin,
# rootfs/any/usr/local/lib/docker-archlinux and tests/ (not tests/fixtures).
# A comment is not code: a line that starts with # and the text after " #"
# are not read.
#
# tests/policy/swallowed-errors.allow holds the exceptions, each with a
# reason. An exception that matches no line fails, so a dead one is removed.
#
# ⚠ The patterns below are written so this file does not match them.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

cd "$REPO_ROOT"
ALLOW=tests/policy/swallowed-errors.allow

PATTERNS='continue-on[-]error|[|][|][[:space:]]*true([[:space:];)]|$)|set[[:space:]]+[+]e|2>[[:space:]]*/dev[/]null|>[[:space:]]*/dev[/]null[[:space:]]+2>&1|&>[[:space:]]*/dev[/]null'

targets() {
  find .github/workflows -type f \( -name '*.yml' -o -name '*.yaml' \)
  [ ! -f Dockerfile ] || printf '%s\n' Dockerfile
  local d
  for d in scripts bootstrap/any/usr/local/bin rootfs/any/usr/local/lib/docker-archlinux; do
    [ ! -d "$d" ] || find "$d" -type f
  done
  find tests -path tests/fixtures -prune -o -type f -name '*.sh' -print
}

work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

mapfile -t files < <(targets | LC_ALL=C sort)
if [ "${#files[@]}" -lt 5 ]; then
  fail "there are files to read" "found ${#files[@]}" "reproduce: ls .github/workflows scripts tests"
  summary
  exit 1
fi

# The exceptions: path | fixed string in the line | reason.
allow_paths=()
allow_needles=()
allow_used=()
malformed=""
while IFS= read -r raw; do
  case "$raw" in '' | '#'*) continue ;; esac
  IFS='|' read -r path needle reason <<< "$raw"
  path="$(printf '%s' "$path" | awk '{ gsub(/^[ \t]+|[ \t]+$/, ""); print }')"
  needle="$(printf '%s' "$needle" | awk '{ gsub(/^[ \t]+|[ \t]+$/, ""); print }')"
  reason="$(printf '%s' "$reason" | awk '{ gsub(/^[ \t]+|[ \t]+$/, ""); print }')"
  if [ -z "$path" ] || [ -z "$needle" ] || [ -z "$reason" ]; then
    malformed="$malformed [$raw]"
    continue
  fi
  allow_paths+=("$path")
  allow_needles+=("$needle")
  allow_used+=(0)
done < "$ALLOW"
check_eq "each exception has a path, a fixed string and a reason" "" "$malformed" "grep -v '^#' $ALLOW"

# is_allowed PATH LINE: an exception covers LINE of PATH. Marks it used.
is_allowed() {
  local i=0
  while [ "$i" -lt "${#allow_paths[@]}" ]; do
    if [ "${allow_paths[$i]}" = "$1" ] && [ "${2#*"${allow_needles[$i]}"}" != "$2" ]; then
      allow_used[i]=1
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

# Each hit as FILE<TAB>LINE<TAB>TEXT, with comments removed first.
awk -v pat="$PATTERNS" '
  /^[[:space:]]*#/ { next }
  {
    line = $0
    sub(/[[:space:]]#.*$/, "", line)
    if (line ~ pat) { t = line; sub(/^[[:space:]]+/, "", t); print FILENAME "\t" FNR "\t" t }
  }' "${files[@]}" > "$work/hits"
hits=()
while IFS=$'\t' read -r f n text; do
  [ -n "$f" ] || continue
  is_allowed "$f" "$text" || hits+=("$f:$n: $text")
done < "$work/hits"

if [ "${#hits[@]}" -eq 0 ]; then
  ok "no construct hides a failure in ${#files[@]} files"
else
  fail "no construct hides a failure in ${#files[@]} files" "${hits[@]}" \
    "capture the status with rc=0; cmd || rc=\$?, and keep stderr where a reader sees it" \
    "or add an exception with a reason to $ALLOW" \
    "reproduce: grep -nE '$PATTERNS' FILE"
fi

dead=""
i=0
while [ "$i" -lt "${#allow_paths[@]}" ]; do
  [ "${allow_used[$i]}" -eq 1 ] || dead="$dead [${allow_paths[$i]} | ${allow_needles[$i]}]"
  i=$((i + 1))
done
check_eq "each exception still matches a line (${#allow_paths[@]} exceptions)" "" "$dead" \
  "grep -nF 'STRING' PATH for each line of $ALLOW"

summary
