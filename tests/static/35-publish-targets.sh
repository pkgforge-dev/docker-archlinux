#!/usr/bin/env bash
#
# A dry run must not be able to reach a real repository.
#
# The publish job creates tags from a resolved target name. A dry run resolves
# that name to a scratch repository on each registry. ⛔ The failure this guards
# is one edit away: if a tag-creating step goes back to naming HUB_IMAGE
# directly instead of the resolved output, a dry run keeps its scratch name on
# GHCR and writes real tags to Docker Hub. Nothing about the run would look
# wrong, and the tags would be public.
#
# ⚠ This reads the workflow rather than running it. What it cannot check is
# whether the resolve step's branches are correct; that is checked by running
# the workflow with dry_run and dry_run_hub, recorded in
# HISTORY/tests-seen-to-fail.md.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

WF="$REPO_ROOT/.github/workflows/build-deploy.yml"

if [ ! -f "$WF" ]; then
  fail "the build workflow exists" \
    "expected: $WF" \
    "reproduce: ls .github/workflows/build-deploy.yml"
  summary
  exit 1
fi
ok "the build workflow exists"

# value NAME -> the value of a top level env entry
value() {
  awk -v k="$1" '$1 == k":" { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }' "$WF"
}

ghcr="$(value GHCR_IMAGE)"
hub="$(value HUB_IMAGE)"
scratch="$(value SCRATCH_IMAGE)"
hub_scratch="$(value HUB_SCRATCH_IMAGE)"

#---------------------------------------------------------------------------#
# 1. Four names, and each real one differs from its scratch counterpart.
#---------------------------------------------------------------------------#
for pair in "GHCR_IMAGE:$ghcr:SCRATCH_IMAGE:$scratch" "HUB_IMAGE:$hub:HUB_SCRATCH_IMAGE:$hub_scratch"; do
  IFS=: read -r rn rv sn sv <<< "$pair"
  if [ -z "$rv" ] || [ -z "$sv" ]; then
    fail "$rn and $sn are both set" \
      "$rn=${rv:-<unset>}, $sn=${sv:-<unset>}" \
      "reproduce: grep -nE '^  (GHCR|HUB|SCRATCH|HUB_SCRATCH)_IMAGE:' .github/workflows/build-deploy.yml"
  elif [ "$rv" = "$sv" ]; then
    fail "$sn names a different repository from $rn" \
      "both are $rv" \
      "a dry run would then write to the repository consumers pull" \
      "reproduce: grep -nE '^  (GHCR|HUB|SCRATCH|HUB_SCRATCH)_IMAGE:' .github/workflows/build-deploy.yml"
  else
    ok "$sn ($sv) is not $rn ($rv)"
  fi
done

#---------------------------------------------------------------------------#
# 2. No step that creates a tag names a real repository directly.
#
# The tag steps must build their image list from the resolved outputs. A
# reference to HUB_IMAGE or GHCR_IMAGE inside one of them bypasses the dry run.
#---------------------------------------------------------------------------#
direct="$(awk '
  /^      - name: Create the (per architecture|index) tags$/ { instep = 1; next }
  /^      - name: / { instep = 0 }
  instep && /\$(\{)?(HUB_IMAGE|GHCR_IMAGE)/ { printf "%d: %s\n", NR, $0 }
' "$WF")"

if [ -z "$direct" ]; then
  ok "no tag-creating step names GHCR_IMAGE or HUB_IMAGE directly"
else
  fail "no tag-creating step names GHCR_IMAGE or HUB_IMAGE directly" \
    "found: $(printf '%s' "$direct" | tr '\n' ' ')" \
    "these steps must use the resolved target_image and hub_image outputs" \
    "naming the real repository here makes a dry run publish real tags" \
    "reproduce: grep -n 'HUB_IMAGE\|GHCR_IMAGE' .github/workflows/build-deploy.yml"
fi

#---------------------------------------------------------------------------#
# 3. dry_run_hub cannot be used on its own.
#---------------------------------------------------------------------------#
if grep -q 'dry_run_hub needs dry_run' "$WF"; then
  ok "the resolve step refuses dry_run_hub without dry_run"
else
  fail "the resolve step refuses dry_run_hub without dry_run" \
    "the guard is not present" \
    "without it, dry_run_hub alone takes the real branch and looks like a test" \
    "reproduce: grep -n 'dry_run_hub' .github/workflows/build-deploy.yml"
fi

#---------------------------------------------------------------------------#
# 4. Both registries are verified after publishing.
#
# Copying across registries is its own operation and can fail on its own. A
# verification that only inspects the staging registry passes while the other
# one carries nothing.
#---------------------------------------------------------------------------#
verify_block="$(awk '
  /^      - name: Verify what was published$/ { instep = 1 }
  instep && /^      - name: / && !/Verify what was published/ { instep = 0 }
  instep { print }
' "$WF")"

if [ -z "$verify_block" ]; then
  fail "the publish job verifies what it published" \
    "no 'Verify what was published' step found" \
    "reproduce: grep -n 'Verify what was published' .github/workflows/build-deploy.yml"
else
  hits=0
  # shellcheck disable=SC2016
  # The dollar signs are literal. These match the text of the workflow, where
  # $TARGET_IMAGE and $HUB_TARGET are shell variables in the step's own script.
  {
    printf '%s\n' "$verify_block" | grep -qF 'verify_index "$TARGET_IMAGE"' && hits=$((hits + 1))
    printf '%s\n' "$verify_block" | grep -qF 'verify_index "$HUB_TARGET"' && hits=$((hits + 1))
  }
  if [ "$hits" -eq 2 ]; then
    ok "the publish job verifies the index on both registries"
  else
    fail "the publish job verifies the index on both registries" \
      "matched $hits of the 2 expected verify_index calls" \
      "a run that copied nothing to the second registry would still be green" \
      "reproduce: sed -n '/Verify what was published/,/^\$/p' .github/workflows/build-deploy.yml"
  fi
fi

#---------------------------------------------------------------------------#
# The rollback guard.
#
# 20 of the 46 shipped mirrors are plain http, all on the two ARM ports. An
# on-path attacker there cannot forge a package and can serve a stale but
# validly signed set, which signatures do not catch. scripts/check-anchor-floor
# refuses a build whose anchor is older than one already published.
#
# ⛔ Deleting one line from the workflow turns that off, and every run stays
# green. That is what these assert. HISTORY/arm-rollback.md.
#---------------------------------------------------------------------------#
if [ -n "$(grep_matches 'scripts/check-anchor-floor' "$WF")" ]; then
  ok "the workflow runs scripts/check-anchor-floor"
else
  fail "the workflow runs scripts/check-anchor-floor" \
    "no step calls it, so a build whose anchor went backwards publishes normally" \
    "a stale package set is validly signed, so nothing else in the run would notice" \
    "reproduce: grep -n check-anchor-floor .github/workflows/build-deploy.yml"
fi

# The override has to exist and has to be an input, so taking one is a named
# act. An env default, or a hardcoded 1, would be the same thing switched off.
if [ -n "$(grep_matches '^[[:space:]]+allow_anchor_downgrade:' "$WF")" ]; then
  ok "allow_anchor_downgrade is a workflow_dispatch input"
else
  fail "allow_anchor_downgrade is a workflow_dispatch input" \
    "not declared, so a legitimate upstream revert has no way through but editing the workflow" \
    "reproduce: grep -n allow_anchor_downgrade .github/workflows/build-deploy.yml"
fi

hardcoded="$(grep_matches '^[[:space:]]*ALLOW_ANCHOR_DOWNGRADE:[[:space:]]*.?1' "$WF")"
if [ -z "$hardcoded" ]; then
  ok "the override is not switched on in the workflow itself"
else
  fail "the override is not switched on in the workflow itself" \
    "found: $(printf '%s' "$hardcoded" | tr '\n' ' ')" \
    "a guard that always passes is the same as no guard, and reads as one that works" \
    "reproduce: grep -n ALLOW_ANCHOR_DOWNGRADE .github/workflows/build-deploy.yml"
fi

summary
