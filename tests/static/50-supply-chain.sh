#!/usr/bin/env bash
#
# Build-time supply chain surface.
#
# Every fetch at build time, every action and every credential is surface.
# What remains must be pinned to content, readable, and currently supported.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

workflows="$(find "$REPO_ROOT/.github/workflows" -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)"
if [ -z "$workflows" ]; then
  fail "at least one workflow exists" "searched: $REPO_ROOT/.github/workflows" \
    "reproduce: ls .github/workflows"
  summary
  exit 1
fi

#---------------------------------------------------------------------------#
# 1. every action is pinned to a commit hash, and says which version that is
#---------------------------------------------------------------------------#
unpinned=0
uncommented=0
while IFS= read -r wf; do
  [ -n "$wf" ] || continue
  rel="${wf#"$REPO_ROOT/"}"
  uses="$(grep_matches '^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*[^ ]+' "$wf")"
  [ -n "$uses" ] || continue
  while IFS= read -r u; do
    [ -n "$u" ] || continue
    lineno="${u%%:*}"
    text="${u#*:}"
    ref="$(printf '%s\n' "$text" | sed -e 's/.*uses:[[:space:]]*//' -e 's/[[:space:]]*#.*//' -e 's/^"//' -e 's/"$//')"
    # a local action or a reusable workflow in this repository is not a pin target
    case "$ref" in ./* | .) continue ;; esac
    if ! printf '%s\n' "$ref" | grep -qE '@[0-9a-f]{40}$'; then
      fail "action is pinned to a commit hash at $rel:$lineno" \
        "found: $ref" \
        "a tag moves, gets deleted and gets re-cut, see standing policy 10" \
        "resolve with: gh api repos/OWNER/REPO/git/ref/tags/TAG --jq .object.sha" \
        "reproduce: grep -n 'uses:' $rel"
      unpinned=$((unpinned + 1))
    elif ! printf '%s\n' "$text" | grep -qE '#[[:space:]]*v?[0-9]'; then
      fail "pinned action names its version in a comment at $rel:$lineno" \
        "found: $text" \
        "a bare hash is unreadable, so record the version it corresponds to" \
        "reproduce: add a trailing comment naming the version, shaped: uses: owner/repo@<sha> # v1.2.3"
      uncommented=$((uncommented + 1))
    fi
  done <<< "$uses"
done <<< "$workflows"
if [ "$unpinned" -eq 0 ]; then
  ok "every action is pinned to a commit hash"
fi
if [ "$uncommented" -eq 0 ]; then
  ok "every pinned action names its version in a comment"
fi

#---------------------------------------------------------------------------#
# 2. nothing pipes a remote script into a shell, and nothing fetches a binary
#---------------------------------------------------------------------------#
targets="$workflows"
if [ -f "$REPO_ROOT/Dockerfile" ]; then
  targets="$targets
$REPO_ROOT/Dockerfile"
fi
if [ -d "$REPO_ROOT/scripts" ]; then
  targets="$targets
$(find "$REPO_ROOT/scripts" -type f -name '*.sh' | sort)"
fi

PIPE_TO_SHELL='(curl|wget)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba)?sh|(ba)?sh[[:space:]]+<\((curl|wget)'
FETCH_BINARY='(curl|wget)[^;&]*(-O|--output|-o)[^;&]*[;&]*[[:space:]]*(&&)?[[:space:]]*chmod[[:space:]]+\+x'

piped=0
fetched=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  rel="${f#"$REPO_ROOT/"}"

  hits="$(grep_matches "$PIPE_TO_SHELL" "$f")"
  if [ -n "$hits" ]; then
    while IFS= read -r h; do
      [ -n "$h" ] || continue
      fail "no remote script is piped into a shell at $rel:${h%%:*}" \
        "found: $(printf '%s\n' "${h#*:}" | sed 's/^[[:space:]]*//')" \
        "the fetched content is unpinned and unreviewed at the moment it runs" \
        "vendor it into this repository instead, see standing policy 1" \
        "reproduce: grep -nE 'curl|wget' $rel"
      piped=$((piped + 1))
    done <<< "$hits"
  fi

  hits="$(grep_matches "$FETCH_BINARY" "$f")"
  if [ -n "$hits" ]; then
    while IFS= read -r h; do
      [ -n "$h" ] || continue
      fail "no opaque binary is fetched and made executable at $rel:${h%%:*}" \
        "found: $(printf '%s\n' "${h#*:}" | sed 's/^[[:space:]]*//')" \
        "build it from a pinned source, or pin the artefact by sha256" \
        "reproduce: grep -n chmod $rel"
      fetched=$((fetched + 1))
    done <<< "$hits"
  fi
done <<< "$targets"
if [ "$piped" -eq 0 ]; then
  ok "no remote script is piped into a shell"
fi
if [ "$fetched" -eq 0 ]; then
  ok "no opaque binary is fetched and made executable"
fi

#---------------------------------------------------------------------------#
# 3. deprecated workflow commands
#---------------------------------------------------------------------------#
deprecated=0
while IFS= read -r wf; do
  [ -n "$wf" ] || continue
  rel="${wf#"$REPO_ROOT/"}"
  hits="$(grep_matches '::(set-output|save-state|set-env|add-path)' "$wf")"
  if [ -n "$hits" ]; then
    while IFS= read -r h; do
      [ -n "$h" ] || continue
      fail "no deprecated workflow command at $rel:${h%%:*}" \
        "found: $(printf '%s\n' "${h#*:}" | sed 's/^[[:space:]]*//')" \
        "write to the GITHUB_OUTPUT, GITHUB_STATE, GITHUB_ENV or GITHUB_PATH file instead" \
        "reproduce: grep -n '::set-' $rel"
      deprecated=$((deprecated + 1))
    done <<< "$hits"
  fi
done <<< "$workflows"
if [ "$deprecated" -eq 0 ]; then
  ok "no deprecated workflow command is used"
fi

#---------------------------------------------------------------------------#
# 4. least privilege on the token
#---------------------------------------------------------------------------#
perms=0
while IFS= read -r wf; do
  [ -n "$wf" ] || continue
  rel="${wf#"$REPO_ROOT/"}"
  block="$(grep_matches '^[[:space:]]*permissions:' "$wf")"
  if [ -z "$block" ]; then
    fail "$rel declares a permissions block" \
      "no permissions: key, so the token keeps the repository default" \
      "reproduce: grep -n 'permissions:' $rel"
    perms=$((perms + 1))
    continue
  fi
  wide="$(grep_matches '^[[:space:]]*permissions:[[:space:]]*write-all' "$wf")"
  if [ -n "$wide" ]; then
    fail "$rel does not grant write-all" "found: $wide" \
      "reproduce: grep -n -A3 'permissions:' $rel"
    perms=$((perms + 1))
  fi
done <<< "$workflows"
if [ "$perms" -eq 0 ]; then
  ok "every workflow declares a permissions block and none grants write-all"
fi

summary
