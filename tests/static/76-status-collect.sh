#!/usr/bin/env bash
#
# scripts/status-collect on a fixture world, with no network.
#
# tests/fixtures/status/make-world writes the registries, the Actions API
# answers, the build artifacts and the mirror record of 8 fixture ports from
# world.json. STATUS_FIXTURE_DIR points the collect at those files. The
# status.json it writes must be expected-status.json, after error texts are
# cut to true and the time the collect took is left out.
#
# The world holds:
#   - one port whose image GHCR does not serve: its age, size, labels,
#     packages and mirror lag are unknown
#   - one port whose last build failed
#   - a rolling tag with another digest on Docker Hub
#   - a pinned tag that Docker Hub lacks, and a platform that latest lacks
#   - each case of the evidence choice
#   - two dry runs and a run of a pull request from a fork, with artifacts
#     that must not count
# The checks below name the facts the page depends on. So a failure says
# which one moved.
#
# Then:
#   - a rolling tag whose HEAD did not read makes the parity unknown
#   - with no registry, every value is unknown, and the collect ends 0
#   - with a budget that is used up, every read is unknown, and
#     budget.exhausted is true
#   - with no image names set, they come from the env of build-deploy.yml
#   - without GITHUB_REPOSITORY, the collect stops
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

FIX="$REPO_ROOT/tests/fixtures/status"
COLLECT="$REPO_ROOT/scripts/status-collect"
work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

expect() {
  if [ "$2" = "$3" ]; then
    ok "$1"
  else
    fail "$1" "expected: $2" "got:      $3" "reproduce: $4"
  fi
}

if ! need_tool jq awk sha256sum timeout; then
  summary
  exit $?
fi

export PORTS_DIR="$FIX/ports"
NOW="$(jq -r '.now | fromdateiso8601' "$FIX/world.json")"
REPRO="bash tests/fixtures/status/make-world W && PORTS_DIR=tests/fixtures/status/ports STATUS_FIXTURE_DIR=W/fx STATUS_NOW=$NOW GITHUB_REPOSITORY=test-owner/docker-archlinux GHCR_IMAGE=ghcr.io/test-owner/archlinux HUB_IMAGE=docker.io/test/archlinux scripts/status-collect W/in"

# collect WORLD [ENV=VALUE ...]: status-collect on WORLD/fx into WORLD/in;
# sets rc
collect() {
  local w="$1"
  shift
  rc=0
  env STATUS_FIXTURE_DIR="$w/fx" STATUS_NOW="$NOW" GITHUB_REPOSITORY=test-owner/docker-archlinux \
    GHCR_IMAGE=ghcr.io/test-owner/archlinux HUB_IMAGE=docker.io/test/archlinux "$@" \
    "$COLLECT" "$w/in" > "$w/out" 2> "$w/err" || rc=$?
}

# The error texts are wording: only whether there is one counts here.
NORMAL='del(.budget.used) | walk(if type == "object" and has("error") then .error |= (. != null) else . end)'

#---------------------------------------------------------------------------#
# The fixture world
#---------------------------------------------------------------------------#
w="$work/w1"
rc=0
bash "$FIX/make-world" "$w" > "$work/make.out" 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then
  fail "make-world writes the fixture world" "$(awk 'NR <= 10' "$work/make.out")" "reproduce: bash tests/fixtures/status/make-world W"
  summary
  exit $?
fi
collect "$w"
expect "status-collect measures the fixture world and exits 0" 0 "$rc" "$REPRO; $(awk 'END { print }' "$w/err")"
s="$w/in/status.json"
if [ "$rc" -ne 0 ] || [ ! -f "$s" ]; then
  summary
  exit $?
fi
q() { jq -r "$1" "$s" | tr -d '\r'; }

jq -S "$NORMAL" "$s" > "$work/got.json"
jq -S . "$FIX/expected-status.json" > "$work/want.json"
if cmp -s "$work/want.json" "$work/got.json"; then
  ok "status.json is expected-status.json"
else
  rc=0
  diff "$work/want.json" "$work/got.json" > "$work/diff.txt" || rc=$?
  fail "status.json is expected-status.json" "$(awk 'NR <= 40' "$work/diff.txt")" \
    "reproduce: $REPRO && jq -S '$NORMAL' W/in/status.json | diff tests/fixtures/status/expected-status.json -"
fi

expect "every fixture port, in the order of scripts/ports" "$("$REPO_ROOT/scripts/ports" list | tr -d '\r' | tr '\n' ' ')" \
  "$(q '.ports[].arch' | tr '\n' ' ')" "$REPRO"

# The port GHCR does not serve: unknown is null, never 0
expect "ppc64: the image did not read, so its state is error" error "$(q '.ports[] | select(.arch == "ppc64") | .ghcr.state')" "$REPRO"
expect "ppc64: age, size, created, packages and mirror lag are null, not 0" "null null null null null" \
  "$(q '.ports[] | select(.arch == "ppc64") | [.age_seconds, .ghcr.size, .ghcr.created, .evidence.packages, .mirror.lag_seconds] | map(tostring) | join(" ")')" "$REPRO"
expect "ppc64: Docker Hub match is unknown while the GHCR image is unknown" null \
  "$(q '.ports[] | select(.arch == "ppc64") | .hub.match')" "$REPRO"

# The port whose last build failed
expect "ppc: the newest Build job failed, in run 1002" "failure 1002 120" \
  "$(q '.ports[] | select(.arch == "ppc") | "\(.build.result) \(.build.run_id) \(.build.duration_seconds)"')" "$REPRO"

# The runs that count
expect "builds: only runs 1002 and 1001 count; dry runs 1003 and 1005 and fork run 1004 are left out" "1001 1002 2 1002" \
  "$(q '"\([.ports[].builds[].run_id] | unique | map(tostring) | join(" ")) \(.builds.runs) \(.builds.newest_run.id)"')" \
  "$REPRO; jq '[.ports[].builds[].run_id], .builds' W/in/status.json"
if need_tool yq; then
  # status-collect reads a skipped job as the mark of a dry run. The fixture
  # dry run 1003 skips that job, and build-deploy.yml must skip it too.
  dry_job="$(jq -r '.jobs[] | select(.conclusion == "skipped" and (.name | startswith("Build ") | not)) | .name' \
    "$FIX/gh/actions_runs_1003_jobs.json" | tr -d '\r')"
  # shellcheck disable=SC2016 # a jq variable, not a shell one
  expect "build-deploy.yml has one job '$dry_job' that needs nothing and runs when dry_run is not true, as fixture run 1003 has it" 1 \
    "$(yaml_json "$REPO_ROOT/.github/workflows/build-deploy.yml" | jq -r --arg n "$dry_job" '
        [.jobs[] | select(.name == $n and .needs == null
                          and ((.if // "") | test("^(\\$\\{\\{)? *inputs[.]dry_run *!= *true *(\\}\\})?$")))] | length' | tr -d '\r')" \
    "yq '.jobs[] | select(.name == \"$dry_job\") | {needs, if}' .github/workflows/build-deploy.yml"
  # status-collect also reads a run name that ends in "(dry run)" as a dry
  # run. For a dry run, the run-name of build-deploy.yml must give the name
  # of fixture dry run 1005. For a real run, it must give the name of 1002.
  titles="$(jq -r '[.workflow_runs[] | select(.id == 1005 or .id == 1002) | .display_title] | join("|")' \
    "$FIX/gh/actions_workflows_build-deploy.yml_runs.json" | tr -d '\r')"
  # shellcheck disable=SC2016 # a jq variable, not a shell one
  expect "the run-name of build-deploy.yml gives the names of fixture dry run 1005 and real run 1002" "$titles" \
    "$(yaml_json "$REPO_ROOT/.github/workflows/build-deploy.yml" | jq -r '
        (.["run-name"] // "") as $r
        | ($r | capture("^\\$\\{\\{ *inputs[.]dry_run *&& *'"'"'(?<dry>[^'"'"']*)'"'"' *[|][|] *'"'"'(?<real>[^'"'"']*)'"'"' *\\}\\}$")
          // {dry: "", real: ""})
        | "\(.dry)|\(.real)"' | tr -d '\r')" \
    "yq '.\"run-name\"' .github/workflows/build-deploy.yml; jq '.workflow_runs[] | {id, display_title}' $FIX/gh/actions_workflows_build-deploy.yml_runs.json"
fi
expect "ppc: the age counts from the created label: 41.1 days" 3552300 \
  "$(q '.ports[] | select(.arch == "ppc") | .age_seconds')" "$REPRO"

# Registries
expect "parity: 16 of 17 rolling tags with the same digest, 42 of 43 pinned tags present, of 60 GHCR tags" "16 17 42 43 60" \
  "$(q '.registries | "\(.rolling.same) \(.rolling.total) \(.pinned.present) \(.pinned.total) \(.ghcr.tags)"')" "$REPRO"
expect "parity is (16 + 42) / 60, and the per port sums agree" "true true" \
  "$(q '[(.registries.parity * 60 | round) == 58, ([.ports[].parity.same] | add) + .registries.index.same == 58] | map(tostring) | join(" ")')" "$REPRO"
expect "the rolling tag that differs and the pinned tag that is missing are named" "arm64 armv7h-v2026.10.15" \
  "$(q '"\(.registries.rolling.differs | join(",")) \(.registries.pinned.missing_names | join(","))"')" "$REPRO"
expect "drift_runs: the previous line has 1, parity is below 1, so 2" 2 "$(q '.registries.drift_runs')" "$REPRO"
expect "latest lacks the platform of ppc64le, and ppc64le is not in latest" "linux/ppc64le false" \
  "$(q '"\(.latest.missing | join(",")) \(.ports[] | select(.arch == "ppc64le") | .in_latest)"')" "$REPRO"
expect "tag families of armv7: 3 rolling, 6 dated, 3 anchor on GHCR; 5 dated on Docker Hub" "3 6 3 5" \
  "$(q '.ports[] | select(.arch == "armv7") | "\(.ghcr.tags.rolling) \(.ghcr.tags.dated) \(.ghcr.tags.anchor) \(.hub.tags.dated)"')" "$REPRO"

# Evidence: the stored file, or the newest artifact that describes the published image
# ev ARCH -> "SOURCE RUN MATCHES" of the evidence of one port
ev() {
  q ".ports[] | select(.arch == \"$1\") | \"\\(.evidence.source) \\(.evidence.run_id) \\(.evidence.matches)\""
}
expect "evidence: amd64 takes the artifact of run 1002, which describes the published image" \
  "artifact 1002 true" "$(ev amd64)" "$REPRO"
expect "evidence: armv7 takes the artifact of run 1001, because run 1002 describes another image" \
  "artifact 1001 true" "$(ev armv7)" "$REPRO"
expect "evidence: arm64 keeps its stored file, which describes the published image" \
  "stored null true" "$(ev arm64)" "$REPRO"
expect "evidence: ppc64le keeps its stored file, which names an older image" "stored false" \
  "$(q '.ports[] | select(.arch == "ppc64le") | "\(.evidence.source) \(.evidence.matches)"')" "$REPRO"
expect "evidence: loong64 has only an expired artifact, so no evidence" "null null" \
  "$(q '.ports[] | select(.arch == "loong64") | "\(.evidence.source) \(.evidence.packages)"')" "$REPRO"
digests_ok=1
for f in "$w/in/evidence"/*.json; do
  a="$(basename "$f" .json)"
  if [ "$(jq -r .digest "$f" | tr -d '\r')" != "$(tr -d '\r\n' < "$w/in/evidence/$a.digest")" ]; then
    digests_ok=0
  fi
done
expect "each evidence/<arch>.digest names the digest inside its evidence file" 1 "$digests_ok" "$REPRO; ls W/in/evidence"

# History
expect "history.jsonl: the previous line and this run's line" 2 "$(awk 'END { print NR }' "$w/in/history.jsonl")" "$REPRO"
expect "history: ppc64 keeps its last size, marked carried; its age is unknown" "75497472 1 null" \
  "$(awk 'END { print }' "$w/in/history.jsonl" | jq -r '.x.ppc64 | "\(.s) \(.k) \(.a)"' | tr -d '\r')" "$REPRO"
expect "history: a measured port is not marked carried" "105906176 null" \
  "$(awk 'END { print }' "$w/in/history.jsonl" | jq -r '.x.amd64 | "\(.s) \(.k)"' | tr -d '\r')" "$REPRO"

# A second run on the same input: the drift count goes on
cp "$s" "$work/first.json"
collect "$w"
expect "a second run counts 3 runs in a row below parity 1" "0 3" "$rc $(q '.registries.drift_runs')" "$REPRO (twice)"
expect "the history keeps the last STATUS_HISTORY_LINES lines" "0 2" \
  "$(collect "$w" STATUS_HISTORY_LINES=2; printf '%s %s' "$rc" "$(awk 'END { print NR }' "$w/in/history.jsonl")")" \
  "$REPRO with STATUS_HISTORY_LINES=2"

#---------------------------------------------------------------------------#
# STATUS_ARTIFACTS=0: no artifact is read, the stored evidence still counts
#---------------------------------------------------------------------------#
w="$work/w5"
bash "$FIX/make-world" "$w" > /dev/null
collect "$w" STATUS_ARTIFACTS=0
s="$w/in/status.json"
expect "STATUS_ARTIFACTS=0: amd64 has no evidence, arm64 keeps its stored evidence" "0 null stored" \
  "$rc $(q '[.ports[] | select(.arch == "amd64" or .arch == "arm64") | .evidence.source] | map(tostring) | join(" ")')" \
  "$REPRO with STATUS_ARTIFACTS=0"

#---------------------------------------------------------------------------#
# A rolling tag whose HEAD on Docker Hub did not read
#---------------------------------------------------------------------------#
w="$work/w6"
bash "$FIX/make-world" "$w" > /dev/null
hubm="$w/fx/registry/docker.io/test/archlinux/manifests"
first="$("$REPO_ROOT/scripts/ports" aliases amd64 | tr -d '\r' | awk 'NR == 1')"
printf '500\n' > "$hubm/$first.code"
printf '500\n' > "$hubm/latest.code"
collect "$w"
s="$w/in/status.json"
expect "a Docker Hub HEAD of $first and of latest that did not read: the parity is unknown" "0 null 2" \
  "$rc $(q '"\(.registries.parity) \(.registries.rolling.unknown)"')" "$REPRO, with W/fx/registry/docker.io/test/archlinux/manifests/{$first,latest}.code = 500"
expect "amd64 and the index: same and ratio are unknown, not a tag that Docker Hub lacks" "null null 1 null null 1" \
  "$(q '[(.ports[] | select(.arch == "amd64") | .parity), .registries.index | .same, .ratio, .unknown] | map(tostring) | join(" ")')" \
  "$REPRO, with W/fx/registry/docker.io/test/archlinux/manifests/{$first,latest}.code = 500; jq '.ports[0].parity, .registries.index' W/in/status.json"
expect "riscv64, whose tags all read: its parity is still measured" "1 0" \
  "$(q '.ports[] | select(.arch == "riscv64") | "\(.parity.ratio) \(.parity.unknown)"')" "$REPRO, with one HEAD of Docker Hub at 500"

#---------------------------------------------------------------------------#
# No registry answers
#---------------------------------------------------------------------------#
w="$work/w2"
bash "$FIX/make-world" "$w" > /dev/null
rm -rf "$w/fx/registry"
collect "$w"
s="$w/in/status.json"
expect "no registry: the collect measures and exits 0" 0 "$rc" "$REPRO, with no W/fx/registry; $(awk 'END { print }' "$w/err")"
expect "no registry: every image is unread, parity is unknown, the drift count stays" "8 0 null 1" \
  "$(q '"\(.summary.unread) \(.summary.published) \(.registries.parity) \(.registries.drift_runs)"')" "$REPRO, with no W/fx/registry"
expect "no registry: no age and no size reads as 0" "0" \
  "$(q '[.ports[] | .age_seconds, .ghcr.size | select(. == 0)] | length')" "$REPRO, with no W/fx/registry"
expect "no registry: the builds still read" 8 "$(q '[.ports[] | select(.build != null)] | length')" "$REPRO, with no W/fx/registry"

#---------------------------------------------------------------------------#
# The budget is used up
#---------------------------------------------------------------------------#
w="$work/w3"
bash "$FIX/make-world" "$w" > /dev/null
start=$SECONDS
collect "$w" STATUS_BUDGET=4
took=$((SECONDS - start))
s="$w/in/status.json"
expect "STATUS_BUDGET=4: the collect exits 0" 0 "$rc" "$REPRO with STATUS_BUDGET=4; $(awk 'END { print }' "$w/err")"
expect "STATUS_BUDGET=4: budget.exhausted, no image read, no build read" "true 8 false null" \
  "$(q '"\(.budget.exhausted) \(.summary.unread) \(.builds.read) \(.registries.parity)"')" "$REPRO with STATUS_BUDGET=4"
if [ "$took" -le 60 ]; then
  ok "STATUS_BUDGET=4: the collect ends in ${took} s"
else
  fail "STATUS_BUDGET=4: the collect ends within a minute" "it took ${took} s" "reproduce: $REPRO with STATUS_BUDGET=4"
fi

#---------------------------------------------------------------------------#
# Names and refusals
#---------------------------------------------------------------------------#
w="$work/w4"
bash "$FIX/make-world" "$w" > /dev/null
rc=0
env -u GHCR_IMAGE -u HUB_IMAGE STATUS_FIXTURE_DIR="$w/fx" STATUS_NOW="$NOW" STATUS_BUDGET=4 \
  GITHUB_REPOSITORY=test-owner/docker-archlinux "$COLLECT" "$w/in" > "$w/out" 2> "$w/err" || rc=$?
s="$w/in/status.json"
expect "no GHCR_IMAGE: the GHCR image is the one build-deploy.yml names, for the owner of GITHUB_REPOSITORY" \
  "0 ghcr.io/test-owner/" "$rc $(q '.images.ghcr' | sed 's|[^/]*$||')" \
  "STATUS_FIXTURE_DIR=W/fx GITHUB_REPOSITORY=test-owner/docker-archlinux scripts/status-collect W/in; jq .images W/in/status.json"
if need_tool yq; then
  want_hub="$(yaml_json "$REPO_ROOT/.github/workflows/build-deploy.yml" | jq -r '.env.HUB_IMAGE // empty' | tr -d '\r')"
  case "$want_hub" in
    */*/*) ;;
    ?*) want_hub="docker.io/$want_hub" ;;
  esac
  expect "no HUB_IMAGE: the Docker Hub image is the env HUB_IMAGE of build-deploy.yml" "${want_hub:-<none>}" "$(q '.images.hub')" \
    "yq .env.HUB_IMAGE .github/workflows/build-deploy.yml; jq .images W/in/status.json"
fi

rc=0
env -u GITHUB_REPOSITORY STATUS_FIXTURE_DIR="$w/fx" STATUS_NOW="$NOW" "$COLLECT" "$work/nothing" > /dev/null 2> "$work/norepo.err" || rc=$?
expect "no GITHUB_REPOSITORY: the collect stops with exit 1 and writes nothing" "1 absent" \
  "$rc $([ -e "$work/nothing/status.json" ] && echo present || echo absent)" \
  "env -u GITHUB_REPOSITORY scripts/status-collect OUT"

summary
