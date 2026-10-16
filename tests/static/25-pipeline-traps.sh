#!/usr/bin/env bash
#
# Check that no script under pipefail uses a pipeline that fails on a normal
# input.
#
# Two shapes:
#   producer | head, | grep -q, | grep -m, | awk '... { exit }'
#       The reader stops early and closes the pipe. A producer that is still
#       writing gets SIGPIPE, and pipefail turns that into status 141.
#       Measured: seq 1 2000000 | head -n 40 | tail -1 gives 141.
#   grep -c
#       A count of zero is exit status 1, so under set -e an assignment from
#       it stops the script before the code that handles zero.
#       Measured: grep -c '^x' /dev/null gives 1.
#
# Read: each file under scripts, tests (not tests/fixtures), bootstrap and
# examples that runs set ... pipefail, and each workflow. A workflow run:
# block runs as bash -eo pipefail (tests/static/51-workflow-policy.sh checks
# shell: bash). Comments are not read.
#
# ⚠ This reads text. A pattern inside a message string counts as code, so no
# message uses one of these shapes.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

cd "$REPO_ROOT"

# The readers that stop early. The patterns do not match their own text.
early_close='[|][[:space:]]*(head([[:space:]]|$)|grep[[:space:]]+(-[A-Za-z]*[[:space:]]+)*-[A-Za-z]*[qm])|[|][[:space:]]*awk[^|]*[{;][[:space:]]*exit[[:space:]]*[};]'
# grep with -c in its flags. The dash is part of the pattern, so a search
# term with the letter c does not match.
zero_is_failure='grep[[:space:]]+(-[a-zA-Z]*[[:space:]]+)*-[a-zA-Z]*c[a-zA-Z]*([[:space:]]|$)'

# scan FILE...: print "FILE:LINE: TEXT" for each line with a trap.
scan() {
  awk -v a="$early_close" -v b="$zero_is_failure" '
    {
      line = $0
      sub(/(^|[[:space:]])#.*$/, "", line)
      if (line ~ a || line ~ b) {
        t = line
        sub(/^[[:space:]]+/, "", t)
        printf "%s:%d: %s\n", FILENAME, FNR, t
      }
    }' "$@"
}

#---------------------------------------------------------------------------#
# Shell files that turn pipefail on
#---------------------------------------------------------------------------#
shell_files=()
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if grep -Eq '^[[:space:]]*set[[:space:]][^#]*pipefail' "$f"; then
    shell_files+=("$f")
  fi
done <<< "$(for d in scripts tests bootstrap examples; do
  [ ! -d "$d" ] || find "$d" -path tests/fixtures -prune -o -type f -print
done | LC_ALL=C sort)"

if [ "${#shell_files[@]}" -eq 0 ]; then
  fail "at least one script sets pipefail" "found none, so this checked nothing" \
    "reproduce: grep -rlE '^[[:space:]]*set[[:space:]][^#]*pipefail' scripts tests"
else
  trapped="$(scan "${shell_files[@]}")"
  if [ -z "$trapped" ]; then
    ok "none of ${#shell_files[@]} pipefail scripts ends a pipeline early or counts with grep -c"
  else
    fail "none of ${#shell_files[@]} pipefail scripts ends a pipeline early or counts with grep -c" \
      "$trapped" \
      "read the whole stream and decide at the end: awk 'NR == 1' in place of head -n 1" \
      "count with: awk '/pattern/ { n++ } END { print n + 0 }' FILE" \
      "reproduce: grep -nE '$early_close' FILE"
  fi
fi

#---------------------------------------------------------------------------#
# Workflow run: blocks
#---------------------------------------------------------------------------#
mapfile -t wfs < <(find .github/workflows -type f \( -name '*.yml' -o -name '*.yaml' \) | LC_ALL=C sort)
if [ "${#wfs[@]}" -eq 0 ]; then
  fail "at least one workflow was read" "no .github/workflows/*.yml" "reproduce: ls .github/workflows"
else
  trapped="$(scan "${wfs[@]}")"
  if [ -z "$trapped" ]; then
    ok "none of ${#wfs[@]} workflows ends a pipeline early or counts with grep -c"
  else
    fail "none of ${#wfs[@]} workflows ends a pipeline early or counts with grep -c" \
      "$trapped" \
      "a run: block runs under -eo pipefail even when it does not set it" \
      "reproduce: grep -nE '$early_close' FILE"
  fi
fi

summary
