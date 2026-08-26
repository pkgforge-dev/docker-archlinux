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
  printf '%s\n' "$verify_block" | grep -q 'verify_index "\$TARGET_IMAGE"' && hits=$((hits + 1))
  printf '%s\n' "$verify_block" | grep -q 'verify_index "\$HUB_TARGET"' && hits=$((hits + 1))
  if [ "$hits" -eq 2 ]; then
    ok "the publish job verifies the index on both registries"
  else
    fail "the publish job verifies the index on both registries" \
      "matched $hits of the 2 expected verify_index calls" \
      "a run that copied nothing to the second registry would still be green" \
      "reproduce: sed -n '/Verify what was published/,/^\$/p' .github/workflows/build-deploy.yml"
  fi
fi

summary
