#!/usr/bin/env bash
#
# No script that sets pipefail may use a pipeline shape that fails on a normal
# result.
#
# Two shapes, both measured rather than reasoned about:
#
#   seq 1 2000000 | head -n 40 | tail -1   rc 141. head closes the pipe, the
#                                          producer takes SIGPIPE, and pipefail
#                                          turns that into 141.
#   grep -c '^x' /dev/null                 rc 1. A count of zero is a failure
#                                          exit, so under set -e an assignment
#                                          from it stops the script.
#
# Both kill a script with no message at all, and both do it on an input that is
# perfectly normal. The second is worse: it stops the script before it can reach
# the error path written to handle exactly that case. That is what
# scripts/gen-mirrorlist did, where a count of zero servers stopped the function
# three lines above the die that would have explained it.
#
# ⚠ This is a text scan, so it reads what a line looks like rather than what the
# shell would do with it. Comments are stripped first. A pattern inside a
# diagnostic string is indistinguishable from a command here, so no diagnostic
# in this repository is written using either shape.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

# The consumer that closes the pipe early.
#
# ⚠ head only. tail has to read the whole stream to know which line is last, so
# it never closes the pipe early and never raises SIGPIPE in the producer.
early_close="[|][[:space:]]*head([[:space:]]|$)"

# The producer whose normal result is a failure exit. The leading dash is
# required: without it the flag pattern also matches an ordinary search term
# that happens to contain the letter c.
zero_is_failure="grep[[:space:]]+(-[a-zA-Z]*[[:space:]]+)*-[a-zA-Z]*c[a-zA-Z]*([[:space:]]|$)"

# strip_comments FILE -> the file with # comments removed, line numbers kept
strip_comments() {
  awk '{ sub(/(^|[[:space:]])#.*$/, ""); print }' "$1"
}

# scan FILE LABEL -> prints "path:line: text" for each trapped line
scan() {
  local file="$1" rel="$2"
  strip_comments "$file" | awk -v rel="$rel" -v a="$early_close" -v b="$zero_is_failure" '
    $0 ~ a || $0 ~ b {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      printf "%s:%d: %s\n", rel, NR, line
    }'
}

#---------------------------------------------------------------------------#
# 1. Shell scripts that enable pipefail
#---------------------------------------------------------------------------#
shell_files=""
for d in scripts tests bootstrap examples; do
  [ -d "$REPO_ROOT/$d" ] || continue
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    # Only files that actually turn pipefail on. A `set` command enabling it,
    # not the word appearing in prose.
    grep -qE '^[[:space:]]*set[[:space:]][^#]*pipefail' "$f" || continue
    shell_files="$shell_files$f
"
  done <<< "$(find "$REPO_ROOT/$d" -type f \( -name '*.sh' -o -perm -u+x \) | sort)"
done

scanned=0
trapped=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  scanned=$((scanned + 1))
  hits="$(scan "$f" "${f#"$REPO_ROOT/"}")"
  [ -z "$hits" ] || trapped="$trapped$hits
"
done <<< "$shell_files"

if [ "$scanned" -eq 0 ]; then
  fail "at least one script sets pipefail" \
    "none found, so this test asserted nothing" \
    "reproduce: grep -rlE '^[[:space:]]*set[[:space:]][^#]*pipefail' scripts tests"
elif [ -z "$trapped" ]; then
  ok "none of the $scanned pipefail scripts uses a pipeline that fails on a normal result"
else
  fail "none of the $scanned pipefail scripts uses a pipeline that fails on a normal result" \
    "head closing the pipe makes the producer take SIGPIPE, which pipefail reports as 141" \
    "counting with a grep flag exits 1 on zero, which under set -e stops the script silently" \
    "count lines with: awk '/pattern/ { n++ } END { print n + 0 }' FILE" \
    "limit output with: awk -v n=N 'NR <= n' instead of head -n N" \
    "reproduce: bash tests/run.sh static, which names each file and line"
  while IFS= read -r t; do
    [ -n "$t" ] && diag "$t"
  done <<< "$trapped"
fi

#---------------------------------------------------------------------------#
# 2. Workflow run blocks
#
# GitHub Actions runs `shell: bash` as `bash --noprofile --norc -eo pipefail`,
# so every run block is under both settings whether or not it says so itself.
#---------------------------------------------------------------------------#
wf_dir="$REPO_ROOT/.github/workflows"
wf_scanned=0
wf_trapped=""
if [ -d "$wf_dir" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    wf_scanned=$((wf_scanned + 1))
    hits="$(scan "$f" "${f#"$REPO_ROOT/"}")"
    [ -z "$hits" ] || wf_trapped="$wf_trapped$hits
"
  done <<< "$(find "$wf_dir" -type f -name '*.yml' | sort)"
fi

if [ "$wf_scanned" -eq 0 ]; then
  fail "at least one workflow was scanned" \
    "no .yml found under .github/workflows" \
    "reproduce: ls .github/workflows"
elif [ -z "$wf_trapped" ]; then
  ok "none of the $wf_scanned workflows uses a pipeline that fails on a normal result"
else
  fail "none of the $wf_scanned workflows uses a pipeline that fails on a normal result" \
    "run blocks execute under -eo pipefail even when the block does not set it" \
    "count lines with: awk '/pattern/ { n++ } END { print n + 0 }' FILE" \
    "reproduce: bash tests/run.sh static, which names each file and line"
  while IFS= read -r t; do
    [ -n "$t" ] && diag "$t"
  done <<< "$wf_trapped"
fi

summary
