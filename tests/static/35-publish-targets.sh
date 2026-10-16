#!/usr/bin/env bash
# The ${{ }} text in single quotes is workflow text, not shell.
# shellcheck disable=SC2016
#
# The build workflow has the shape that the other files depend on, and a dry
# run cannot write to a published image.
#
#   1. .github/workflows/build-deploy.yml, read as data with yq: the job ids,
#      needs, permissions, concurrency, the leg name, and no secret in a leg.
#   2. A dry run end to end with fixtures: scripts/plan-build gives the
#      scratch targets, and scripts/publish-ghcr and scripts/sync-hub then plan
#      writes to the scratch images only.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

WF="$REPO_ROOT/.github/workflows/build-deploy.yml"
PORTS="$REPO_ROOT/scripts/ports"

if [ ! -f "$WF" ]; then
  fail "the build workflow exists" "reproduce: ls .github/workflows/build-deploy.yml"
  summary
  exit 1
fi
if ! need_tool yq jq; then
  summary
  exit 0
fi

work="$(work_dir)"
trap 'rm -rf "$work"' EXIT
reproduce="yq '.jobs' .github/workflows/build-deploy.yml"

rc=0
yaml_json "$WF" > "$work/wf.json" 2> "$work/wf.err" || rc=$?
if [ "$rc" -ne 0 ] || ! jq -e 'type == "object"' "$work/wf.json" > "$work/type" 2>&1; then
  fail "the build workflow reads as YAML" "yq exited $rc: $(tr '\n' ' ' < "$work/wf.err")" \
    "reproduce: yq . .github/workflows/build-deploy.yml"
  summary
  exit 1
fi

# q FILTER -> jq -r on the workflow, with $on bound to the triggers
q() { jq -r "(.on // .[\"true\"]) as \$on | $1" "$work/wf.json"; }

# check DESC WANT GOT
check() {
  if [ "$3" = "$2" ]; then
    ok "$1"
  else
    fail "$1" "got: $3" "want: $2" "reproduce: $reproduce"
  fi
}

#---------------------------------------------------------------------------#
# 1. The workflow.
#---------------------------------------------------------------------------#
check "the workflow name is 'Build and publish'" "Build and publish" "$(q '.name')"
check "the job ids are the eight that the other files name" \
  "build gate hub plan publish report status watch" "$(q '.jobs | keys | join(" ")')"
check "the top level grants no permission" "{}" "$(q '.permissions | tojson')"
check "the schedules are 05:30 and 17:30 UTC" "30 5 * * *|30 17 * * *" \
  "$(q '[$on.schedule[].cron] | join("|")')"
check "the dispatch inputs" "allow_anchor_downgrade arches dry_run dry_run_hub force" \
  "$(q '$on.workflow_dispatch.inputs | keys | join(" ")')"
check "allow_anchor_downgrade is a string that defaults to none" "string none" \
  "$(q '$on.workflow_dispatch.inputs.allow_anchor_downgrade | "\(.type) \(.default)"')"
check "every job runs on ubuntu-24.04 with a timeout" "" \
  "$(q '[.jobs | to_entries[] | select(.value["runs-on"] != "ubuntu-24.04" or (.value["timeout-minutes"] | type) != "number") | .key] | join(" ")')"

# needs, as a sorted word list
needs() { q ".jobs.$1.needs // [] | if type == \"string\" then [.] else . end | sort | join(\" \")"; }
check "build needs plan only, so it runs beside the gate" "plan" "$(needs build)"
check "gate needs nothing" "" "$(needs gate)"
check "publish needs plan, build and gate" "build gate plan" "$(needs publish)"
check "hub needs publish" "plan publish" "$(needs hub)"
check "report needs every job that it reports on" "build gate hub plan publish" "$(needs report)"
check "status needs report" "report" "$(needs status)"
check "watch needs nothing" "" "$(needs watch)"

check "the build leg is named Build <arch>" 'Build ${{ matrix.arch }}' "$(q '.jobs.build.name')"
check "the legs come from the plan matrix and do not stop each other" \
  'false ${{ fromJSON(needs.plan.outputs.matrix) }}' \
  "$(q '.jobs.build.strategy | "\(.["fail-fast"]) \(.matrix.include)"')"
check "a build leg can read the tree and push packages, nothing more" '{"contents":"read","packages":"write"}' \
  "$(q '.jobs.build.permissions | tojson')"
check "⛔ no secret in a build leg" "0" "$(q '[.jobs.build | .. | strings | select(test("secrets\\."))] | length')"
check "the publish runs only after a passed plan and gate" "true" \
  "$(q '.jobs.publish.if | test("needs\\.plan\\.result == .success.") and test("needs\\.gate\\.result == .success.")
    and test("!cancelled\\(\\)")')"
# ⭐ On a stand-down the publish makes latest again when an earlier index
# write failed, so the matrix does not gate it.
check "the publish runs on a stand-down too" "false" "$(q '.jobs.publish.if | test("matrix")')"
check "⛔ a publish never cancels another" "false true" \
  "$(q '"\(.jobs.publish.concurrency["cancel-in-progress"]) \(.jobs.publish.concurrency.group | startswith("publish-"))"')"
check "⛔ a run never cancels another" "false" "$(q '.concurrency["cancel-in-progress"]')"
check "a dry run has its own run group, so it never takes the place of a pending real run" "true" \
  "$(q '.concurrency.group | test("inputs\\.dry_run")')"
check "the Docker Hub copy runs only when the plan says publish_hub, after a passed publish" "true" \
  "$(q '.jobs.hub.if | test("needs\\.plan\\.outputs\\.publish_hub == .true.") and test("needs\\.publish\\.result == .success.")
    and (test("skipped") | not)')"
check "⛔ the report clears build-<arch> from the publish output written after the read back" \
  '${{ steps.publish.outputs.published }} ${{ needs.publish.outputs.published }}' \
  "$(q '"\(.jobs.publish.outputs.published) \([.jobs.report.steps[] | select((.run // "") | test("scripts/report-build")) | .env.PUBLISHED] | first)"')"
check "no Docker Hub secret outside the hub job" "hub" \
  "$(q '[.jobs | to_entries[] | select([.value | .. | strings | select(test("secrets\\.DOCKERHUB"))] | length > 0) | .key] | join(" ")')"
check "the report and watch jobs do not run in a dry run" "true true" \
  "$(q '"\(.jobs.report.if | test("inputs\\.dry_run != true")) \(.jobs.watch.if | test("inputs\\.dry_run != true"))"')"
check "the report job runs after a failure too" "true" "$(q '.jobs.report.if | test("always\\(\\)")')"

# The published image names are set once, in the top level env. scripts/
# plan-build reads them, and every job takes its targets from the plan
# outputs, so a dry run reaches no published image.
check "the top level env sets the two published image names, and nothing else" "GHCR_IMAGE HUB_IMAGE" \
  "$(q '.env | keys | join(" ")')"
check "no job reads GHCR_IMAGE or HUB_IMAGE itself" "" \
  "$(q '[.jobs | to_entries[] | select([.value | .. | strings | select(test("env\\.(GHCR|HUB)_IMAGE|\\$\\{?(GHCR|HUB)_IMAGE"))] | length > 0) | .key] | join(" ")')"

# A step of the build leg, by the script it runs.
# The script name must end there: scripts/gen-evidence-x is another script.
step_with() { q "[.jobs.build.steps[] | select((.run // \"\") | test(\"$1([^-A-Za-z0-9_]|\$)\"))] | length > 0"; }
for s in scripts/binfmt-register scripts/pick-base-image scripts/gen-mirrorlist scripts/pick-transport \
  scripts/check-mirror-lag scripts/resolve-anchor scripts/check-anchor-floor scripts/gen-evidence; do
  check "a build leg runs $s" "true" "$(step_with "$s")"
done
check "the anchor floor takes its allow list from the dispatch input" "true" \
  "$(q '[.jobs.build.steps[] | select((.run // "") | test("check-anchor-floor")) | .env.ALLOW_ANCHOR_DOWNGRADE | test("inputs\\.allow_anchor_downgrade")] | all')"
check "⛔ the evidence must have the resolved anchor" "true" \
  "$(q '[.jobs.build.steps[] | select((.run // "") | test("gen-evidence")) | .env.EXPECT_ANCHOR == "${{ steps.anchor.outputs.anchor }}"] | all')"
check "both builds get the same build args" "1" \
  "$(q '[.jobs.build.steps[] | select((.uses // "") | startswith("docker/build-push-action@")) | .with["build-args"]] | unique | length')"
check "the build args are those of the Dockerfile contract" "BASE_IMAGE BUILD_DATE IMAGE_VERSION SKIP_SERVERS SOURCE_COMMIT TRANSPORT" \
  "$(q '[.jobs.build.steps[] | select((.uses // "") | startswith("docker/build-push-action@")) | .with["build-args"] | split("\n")[] | select(length > 0) | split("=")[0]] | unique | join(" ")')"
check "the build cache ignores a cache service error" "true" \
  "$(q '[.jobs.build.steps[] | select(.with["cache-to"] != null) | .with["cache-to"] | test("type=gha") and test("ignore-error=true")] | all')"
# The buildkit image: pinned in the step buildkit, picked there from the
# registries that serve the digest, and given to Buildx from that step.
bk_pin="$(q '[.jobs.build.steps[] | select(.id == "buildkit") | .env.BUILDKIT_IMAGE // ""] | first // ""')"
if [[ "$bk_pin" =~ ^docker\.io/([a-z0-9._/-]+):[A-Za-z0-9._-]+@(sha256:[0-9a-f]{64})$ ]]; then
  ok "the buildkit image is pinned by digest"
  bk_repo="${BASH_REMATCH[1]}"
  bk_digest="${BASH_REMATCH[2]}"
else
  fail "the buildkit image is pinned by digest" "BUILDKIT_IMAGE of the step buildkit: '${bk_pin:-none}'" \
    "reproduce: yq '.jobs.build.steps[] | select(.id == \"buildkit\")' .github/workflows/build-deploy.yml"
  bk_repo=""
  bk_digest=""
fi
check "Buildx runs the buildkit image that the step buildkit picked, after that step" \
  'true image=${{ steps.buildkit.outputs.ref }}' \
  "$(q '.jobs.build.steps as $s
    | ([range(0; $s | length) | select($s[.].id == "buildkit")] | first) as $i
    | ([range(0; $s | length) | select(($s[.].uses // "") | startswith("docker/setup-buildx-action@"))] | first) as $j
    | "\($i != null and $j != null and $i < $j and ($s[$i].run | test("scripts/pick-base-image --image"))) \($s[$j].with["driver-opts"])"')"
if [ -n "$bk_repo" ]; then
  mkdir -p "$work/bk"
  printf 'docker.io\t%s\t%s\t503\t\nmirror.gcr.io\t%s\t%s\t200\t%s\n' \
    "$bk_repo" "$bk_digest" "$bk_repo" "$bk_digest" "$bk_digest" > "$work/bk/heads.tsv"
  rc=0
  "$REPO_ROOT/scripts/pick-base-image" --fixtures "$work/bk" --image "$bk_pin" > "$work/bk/out" 2> "$work/bk/err" || rc=$?
  check "⭐ a Docker Hub fault takes the buildkit image from mirror.gcr.io at the same digest" \
    "0 mirror.gcr.io/$bk_repo@$bk_digest" "$rc $(cat "$work/bk/out")"
fi
check "the digest record is uploaded last" "digest-\${{ matrix.arch }}" \
  "$(q '.jobs.build.steps | last | .with.name')"
check "the publish job runs scripts/publish-ghcr and no docker command" "1 0" \
  "$(q '"\([.jobs.publish.steps[] | select((.run // "") | test("scripts/publish-ghcr([^-A-Za-z0-9_]|$)"))] | length) \([.jobs.publish.steps[] | select((.run // "") | test("docker "))] | length)"')"
check "the hub job runs scripts/sync-hub" "1" \
  "$(q '[.jobs.hub.steps[] | select((.run // "") | test("scripts/sync-hub([^-A-Za-z0-9_]|$)"))] | length')"

# The step of the job watch, run with a stand-in scripts/watch-schedules.
# Exit 3 is a stopped schedule: watch-schedules raised schedules-stopped, so
# the step stays green. A red step would turn this workflow red, and the
# watchers would then raise failing-build-deploy too.
q '[.jobs.watch.steps[] | select((.run // "") | test("scripts/watch-schedules"))] | first | .run // ""' > "$work/watch-step.sh"
mkdir -p "$work/watch/scripts"
printf '#!/usr/bin/env bash\nexit "$WATCH_RC"\n' > "$work/watch/scripts/watch-schedules"
chmod +x "$work/watch/scripts/watch-schedules"
got=""
for want_rc in 0 3 1; do
  rc=0
  (cd "$work/watch" && WATCH_RC="$want_rc" bash --noprofile --norc -eo pipefail "$work/watch-step.sh") > "$work/watch/out-$want_rc" 2>&1 || rc=$?
  got="$got $want_rc:$rc"
done
check "the watch step passes when watch-schedules exits 0 or 3, and fails when it exits 1" " 0:0 3:0 1:1" "$got"

#---------------------------------------------------------------------------#
# 2. A dry run, end to end, with fixtures.
#---------------------------------------------------------------------------#
GHCR="ghcr.io/example/archlinux"
HUB="docker.io/example/archlinux"
P1="$("$PORTS" list | awk 'NR == 1')"
mkdir -p "$work/fx" "$work/digests"
{
  printf 'ghcr.io\texample/archlinux\t%s\n' latest v2030.01.01
  printf 'ghcr.io\texample/archlinux-ci\t%s\n' latest
  printf 'docker.io\texample/archlinux\t%s\n' latest
  printf 'docker.io\texample/archlinux-ci\t%s\n' latest
} > "$work/fx/tags.tsv"
{
  printf 'ghcr.io\texample/archlinux-ci\tlatest\t200\tsha256:%064d\n' 5
  printf 'docker.io\texample/archlinux-ci\tlatest\t200\tsha256:%064d\n' 6
} > "$work/fx/heads.tsv"

rc=0
env -u GITHUB_OUTPUT GHCR_IMAGE="$GHCR" HUB_IMAGE="$HUB" DRY_RUN=true DRY_RUN_HUB=true \
  PLAN_NOW=2030-01-02T05:30:00Z "$REPO_ROOT/scripts/plan-build" --fixtures "$work/fx" > "$work/plan" 2> "$work/plan.err" || rc=$?
target="$(awk -F= '$1 == "target_image" { print $2 }' "$work/plan")"
hub_target="$(awk -F= '$1 == "hub_target" { print $2 }' "$work/plan")"
carry="$(awk -F= '$1 == "carry_image" { print $2 }' "$work/plan")"
if [ "$rc" -eq 0 ] && [ "$target" = "$GHCR-ci" ] && [ "$hub_target" = "$HUB-ci" ] && [ "$carry" = "$GHCR" ]; then
  ok "a dry run plans the scratch images, and reads the published one only to carry"
else
  fail "a dry run plans the scratch images, and reads the published one only to carry" \
    "exit $rc; target '$target', hub '$hub_target', carry '$carry'" \
    "reproduce: DRY_RUN=true GHCR_IMAGE=$GHCR HUB_IMAGE=$HUB scripts/plan-build --dry-plan"
fi

jq -n --arg a "$P1" --arg p "$("$PORTS" get "$P1" platform)" --arg d "sha256:$(printf '%064d' 1)" \
  '{arch: $a, platform: $p, digest: $d, anchor: "7.1.0-1"}' > "$work/digests/digest-$P1.json"
rc=0
env -u GITHUB_OUTPUT TARGET_IMAGE="$target" CARRY_IMAGE="$carry" HUB_IMAGE="$HUB" VERSION=2030.01.02 RETRY_PAUSE=0 \
  "$REPO_ROOT/scripts/publish-ghcr" --fixtures "$work/fx" "$work/digests" > "$work/pub" 2> "$work/pub.err" || rc=$?
# Every tag that a "tag" or "index" line names must be on the scratch image.
real="$(awk '$1 == "tag" || $1 == "index" { for (i = 2; i <= NF; i++) if ($i == "from") break; else if ($i ~ /:/ && $i !~ /@/) print $i }' "$work/pub" |
  awk -v t="$target:" 'index($0, t) != 1')"
n_written="$(awk '$1 == "tag" || $1 == "index"' "$work/pub" | awk 'END { print NR + 0 }')"
if [ "$rc" -eq 0 ] && [ "$n_written" -ge 2 ] && [ -z "$real" ]; then
  ok "⛔ a dry run tags the scratch GHCR image only"
else
  fail "⛔ a dry run tags the scratch GHCR image only" \
    "exit $rc; writes planned: $n_written; tags off the scratch image: ${real:-none}" \
    "stderr: $(tr '\n' '|' < "$work/pub.err")" \
    "reproduce: TARGET_IMAGE=$target scripts/publish-ghcr --dry-plan <digests>"
fi

# The build legs push to the scratch image, so a fresh source is there.
fresh_src="$(awk '$1 == "source" && $3 == "fresh" { print $4 }' "$work/pub")"
if [ -n "$fresh_src" ] && [ -z "$(awk -v t="$target@" 'index($0, t) != 1' <<< "$fresh_src")" ]; then
  ok "a dry run takes each fresh digest from the scratch image"
else
  fail "a dry run takes each fresh digest from the scratch image" "fresh sources: ${fresh_src:-none}" \
    "the legs pushed to $target, so a source elsewhere is not the image that was built" \
    "reproduce: TARGET_IMAGE=$target CARRY_IMAGE=$carry scripts/publish-ghcr --dry-plan <digests>"
fi

rc=0
env SOURCE_IMAGE="$target" HUB_TARGET="$hub_target" RETRY_PAUSE=0 \
  "$REPO_ROOT/scripts/sync-hub" --fixtures "$work/fx" > "$work/sync" 2> "$work/sync.err" || rc=$?
moves="$(awk '$1 == "copy" || $1 == "move"' "$work/sync" | awk 'END { print NR + 0 }')"
if [ "$rc" -eq 0 ] && [ "$moves" -eq 1 ] && [ "$(awk '$1 == "move" { print $2 }' "$work/sync")" = latest ]; then
  ok "⛔ a dry run with dry_run_hub copies between the scratch images only"
else
  fail "⛔ a dry run with dry_run_hub copies between the scratch images only" \
    "exit $rc; stdout: $(tr '\n' '|' < "$work/sync")" \
    "the published Docker Hub image has latest and is not read or written" \
    "reproduce: SOURCE_IMAGE=$target HUB_TARGET=$hub_target scripts/sync-hub --dry-plan"
fi

summary
