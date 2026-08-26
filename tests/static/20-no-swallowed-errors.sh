#!/usr/bin/env bash
#
# No build step may hide a failure.
#
# The published image went 59 days stale behind green runs. Every link in that
# chain was a construct in this list: continue-on-error on the build step,
# 2>/dev/null on the bootstrap, and || true making a step that installed
# nothing report success.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

ALLOW="$REPO_ROOT/tests/policy/swallowed-errors.allow"

# Patterns that make a failure invisible. Extended regex.
PATTERNS='continue-on-error|\|\|[[:space:]]*true|set[[:space:]]+\+e|2>[[:space:]]*/dev/null'

scan_targets() {
  if [ -d "$REPO_ROOT/.github/workflows" ]; then
    find "$REPO_ROOT/.github/workflows" -type f \( -name '*.yml' -o -name '*.yaml' \) | sort
  fi
  if [ -f "$REPO_ROOT/Dockerfile" ]; then
    printf '%s\n' "$REPO_ROOT/Dockerfile"
  fi
  # Every executable script, whatever it is named. The scripts in this
  # repository carry no .sh suffix, so matching on the extension would let them
  # escape the scan entirely.
  local d
  for d in scripts bootstrap/any/usr/local/bin; do
    if [ -d "$REPO_ROOT/$d" ]; then
      find "$REPO_ROOT/$d" -type f | sort
    fi
  done
}

targets="$(scan_targets)"
if [ -z "$targets" ]; then
  fail "there is something to scan" "no workflows, Dockerfile or scripts found" \
    "reproduce: ls .github/workflows Dockerfile scripts"
  summary
  exit 1
fi

# Load the allowlist. Track which entries are used so a dead one is caught.
allow_paths=()
allow_needles=()
allow_used=()
if [ -f "$ALLOW" ]; then
  while IFS= read -r raw; do
    case "$raw" in '' | '#'*) continue ;; esac
    path="$(printf '%s\n' "$raw" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$1); print $1}')"
    needle="$(printf '%s\n' "$raw" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')"
    reason="$(printf '%s\n' "$raw" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$3); print $3}')"
    if [ -z "$path" ] || [ -z "$needle" ] || [ -z "$reason" ]; then
      fail "every allowlist entry has a path, a pattern and a reason" \
        "malformed: $raw" \
        "expected: path | fixed string | reason" \
        "reproduce: cat tests/policy/swallowed-errors.allow"
      continue
    fi
    allow_paths+=("$path")
    allow_needles+=("$needle")
    allow_used+=(0)
  done < "$ALLOW"
fi

is_allowed() { # rel line -> 0 when an entry covers it, marking that entry used
  local rel="$1" line="$2" i=0
  while [ "$i" -lt "${#allow_paths[@]}" ]; do
    if [ "${allow_paths[$i]}" = "$rel" ] && [ "${line#*"${allow_needles[$i]}"}" != "$line" ]; then
      allow_used[i]=1
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

violations=0
while IFS= read -r file; do
  [ -n "$file" ] || continue
  rel="${file#"$REPO_ROOT/"}"
  hits="$(grep_matches "$PATTERNS" "$file")"
  [ -n "$hits" ] || continue
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    lineno="${hit%%:*}"
    text="${hit#*:}"
    if is_allowed "$rel" "$text"; then
      continue
    fi
    fail "no swallowed error at $rel:$lineno" \
      "found: $(printf '%s\n' "$text" | sed 's/^[[:space:]]*//')" \
      "reproduce: grep -nE '$PATTERNS' $rel"
    violations=$((violations + 1))
  done <<< "$hits"
done <<< "$targets"

if [ "$violations" -eq 0 ]; then
  ok "no construct hides a failure in the workflows, the Dockerfile or scripts/"
fi

# A stale allowlist entry is the same class of silent rot as a stale pin.
i=0
stale=0
while [ "$i" -lt "${#allow_paths[@]}" ]; do
  if [ "${allow_used[$i]}" -eq 0 ]; then
    fail "allowlist entry is still needed" \
      "unused: ${allow_paths[$i]} | ${allow_needles[$i]}" \
      "the construct is gone, so remove the exception" \
      "reproduce: remove the line from tests/policy/swallowed-errors.allow"
    stale=1
  fi
  i=$((i + 1))
done
if [ "$stale" -eq 0 ]; then
  ok "no dead allowlist entry (${#allow_paths[@]} entries)"
fi

summary
