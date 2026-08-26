#!/usr/bin/env bash
#
# The workflow must build the ref that triggered it.
#
# A hand-clone of the default branch builds main whatever ref was dispatched,
# so a branch cannot be tested and a green run proves nothing about the branch.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

WF="$REPO_ROOT/.github/workflows/build-deploy.yml"

if [ ! -f "$WF" ]; then
  fail "workflow exists" "expected: $WF"
  summary
  exit 1
fi

# 1. the repository arrives through actions/checkout, pinned by commit hash
checkout="$(grep_matches 'uses:[[:space:]]*actions/checkout@' "$WF")"
if [ -z "$checkout" ]; then
  fail "actions/checkout is used" \
    "no 'uses: actions/checkout@' in $WF" \
    "reproduce: grep -nE 'uses:[[:space:]]*actions/checkout@' .github/workflows/build-deploy.yml"
elif ! printf '%s\n' "$checkout" | grep -qE 'actions/checkout@[0-9a-f]{40}'; then
  fail "actions/checkout is pinned to a commit hash" \
    "found: $checkout" \
    "a tag is not a pin, see standing policy 10"
else
  ok "actions/checkout is used and pinned to a commit hash"
fi

# 2. nothing hand-clones this repository
clones="$(grep_matches 'git[[:space:]]+clone' "$WF")"
if [ -n "$clones" ]; then
  fail "the workflow does not hand-clone the repository" \
    "found: $clones" \
    "a hand-clone without --branch builds the default branch, not the triggering ref"
else
  ok "the workflow does not hand-clone the repository"
fi

# 3. every build context is the checked-out workspace
contexts="$(grep_matches '^[[:space:]]*context:' "$WF")"
if [ -z "$contexts" ]; then
  ok "no explicit build context, so the action default of the workspace applies"
else
  bad=0
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    if ! printf '%s\n' "$c" | grep -qE 'context:[[:space:]]*"?(\.|\$\{\{[[:space:]]*github\.workspace)'; then
      fail "build context is the workspace" \
        "found: $c" \
        "expected . or \${{ github.workspace }}"
      bad=1
    fi
  done <<< "$contexts"
  if [ "$bad" -eq 0 ]; then
    ok "every build context is the checked-out workspace"
  fi
fi

summary
