#!/usr/bin/env bash
#
# The shape of .github/workflows/status.yml, read as data with yq.
#
#   - name Status; an hourly cron and workflow_dispatch; no permission at the
#     top; one concurrency group that never cancels a run
#   - jobs build, check, deploy and keep, each on ubuntu-24.04 with a timeout
#   - build: contents write, runs scripts/status-collect and
#     scripts/status-render, pushes the branch status and uploads the Pages
#     artifact only on the default branch, uploads no status-history
#   - deploy: pages and id-token write, environment github-pages, group
#     pages, and the Pages artifact name of this run attempt
#   - keep: contents read, after a build that passed, keeps status-history
#     90 days; no other job needs it
#   - check: issues write, runs whatever build did, and calls
#     scripts/check-status-record
#   - no workflow sets a test seam of the status scripts
#
# Then the step that reads the branch status runs, with stand-ins for git,
# gh and unzip. With no branch status, it must take the status-history
# artifact of a run of this repository on the default branch. The artifact
# of a run of a pull request from a fork must not count.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

WF="$REPO_ROOT/.github/workflows/status.yml"
work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

expect() {
  if [ "$2" = "$3" ]; then
    ok "$1"
  else
    fail "$1" "expected: $2" "got:      $3" "reproduce: $4"
  fi
}

if ! need_tool yq jq python3 timeout base64; then
  summary
  exit $?
fi

# A YAML 1.1 reader reads the key on as true, so .on is read as (.on // .true) below.

rc=0
yaml_json "$WF" > "$work/wf.json" 2> "$work/yq.err" || rc=$?
if [ "$rc" -ne 0 ]; then
  fail "status.yml reads as YAML" "$(awk 'NR <= 5' "$work/yq.err")" "reproduce: yq . .github/workflows/status.yml"
  summary
  exit $?
fi
q() { jq -r "$1" "$work/wf.json" | tr -d '\r'; }
R="yq . .github/workflows/status.yml"
ON='(.on // .["true"])'
PUBLISH_IF="github.event_name == 'schedule' || github.ref == format('refs/heads/{0}', github.event.repository.default_branch)"

expect "the workflow is named Status" Status "$(q .name)" "$R | jq .name"
expect "an hourly cron at minute 23, and workflow_dispatch" "23 * * * * true" \
  "$(q "$ON | \"\\(.schedule[0].cron) \\(has(\"workflow_dispatch\"))\"")" "$R | jq .on"
expect "no permission at the top" "{}" "$(q '.permissions | tojson')" "$R | jq .permissions"
expect "one concurrency group, and a run is never cancelled" "status false" \
  "$(q '"\(.concurrency.group) \(.concurrency["cancel-in-progress"])"')" "$R | jq .concurrency"
expect "the jobs are build, check, deploy and keep" "build check deploy keep" "$(q '.jobs | keys | join(" ")')" "$R | jq '.jobs | keys'"
expect "every job runs on ubuntu-24.04 with a timeout" "" \
  "$(q '[.jobs | to_entries[] | select(.value["runs-on"] != "ubuntu-24.04" or (.value["timeout-minutes"] | type) != "number") | .key] | join(" ")')" \
  "$R | jq '.jobs[] | {\"runs-on\", \"timeout-minutes\"}'"

# build
expect "build: actions read and contents write, nothing more" '{"actions":"read","contents":"write"}' \
  "$(q '.jobs.build.permissions | tojson')" "$R | jq .jobs.build.permissions"
# shellcheck disable=SC2016 # a jq variable, not a shell one
expect "build: runs scripts/status-collect, then scripts/status-render" "true true" \
  "$(q '[.jobs.build.steps[].run // ""] | join("\n") as $r
        | "\($r | test("scripts/status-collect ")) \($r | test("python3 -I scripts/status-render "))"')" "$R | jq '.jobs.build.steps[].run'"
expect "build: the push to the branch status and the Pages artifact run on the default branch only" "2" \
  "$(jq -r --arg c "$PUBLISH_IF" '[.jobs.build.steps[]
        | select((.run // "" | test("refs/heads/status")) or ((.uses // "") | startswith("actions/upload-pages-artifact@")))
        | select((.if // "") | contains($c))] | length' "$work/wf.json")" "$R | jq '.jobs.build.steps[] | {if, uses}'"
expect "build: the Pages artifact is named for this run attempt, and deploy takes that name" "true true" \
  "$(q '"\(.jobs.build.outputs.pages_artifact | test("run_attempt")) \([.jobs.deploy.steps[] | select((.uses // "") | startswith("actions/deploy-pages@")) | .with.artifact_name] | .[0] | test("needs.build.outputs.pages_artifact"))"')" \
  "$R | jq '.jobs.build.outputs, .jobs.deploy.steps'"
expect "build: no step uploads status-history, so a fault of the artifact store cannot stop the record" "" \
  "$(q '[.jobs.build.steps[] | select(.with.name == "status-history") | .name] | join(", ")')" \
  "$R | jq '.jobs.build.steps[] | select(.with.name == \"status-history\")'"

# keep
expect "keep: contents read, nothing more" '{"contents":"read"}' "$(q '.jobs.keep.permissions | tojson')" "$R | jq .jobs.keep.permissions"
expect "keep: needs build, runs only after a build that passed, on the default branch" "build true true" \
  "$(q '.jobs.keep | "\(.needs) \(.if | test("needs[.]build[.]result *== *.success.")) \(.if | contains("default_branch"))"')" \
  "$R | jq .jobs.keep"
expect "keep: status-history is kept 90 days, a re-run overwrites it, and no file is an error" "90 true error" \
  "$(q '[.jobs.keep.steps[] | select(.with.name == "status-history") | "\(.with["retention-days"]) \(.with.overwrite) \(.with["if-no-files-found"])"] | .[0]')" \
  "$R | jq '.jobs.keep.steps'"
expect "no job needs keep" "" \
  "$(q '[.jobs | to_entries[] | select([.value.needs // [] | if type == "array" then .[] else . end] | index("keep")) | .key] | join(" ")')" \
  "$R | jq '.jobs[] | .needs'"

# deploy
expect "deploy: pages and id-token write, nothing more" '{"id-token":"write","pages":"write"}' \
  "$(q '.jobs.deploy.permissions | to_entries | sort_by(.key) | from_entries | tojson')" "$R | jq .jobs.deploy.permissions"
expect "deploy: environment github-pages, group pages, never cancelled, needs build" "github-pages pages false build" \
  "$(q '.jobs.deploy | "\(.environment.name) \(.concurrency.group) \(.concurrency["cancel-in-progress"]) \(.needs)"')" "$R | jq .jobs.deploy"
expect "deploy: the build type of Pages is read before the deploy" "true" \
  "$(q '[.jobs.deploy.steps[].run // ""] | join("\n") | test("build_type")')" "$R | jq '.jobs.deploy.steps[].run'"

# check
expect "check: contents read and issues write" '{"contents":"read","issues":"write"}' \
  "$(q '.jobs.check.permissions | tojson')" "$R | jq .jobs.check.permissions"
expect "check: runs whatever build did, on the default branch, after build" "true true build" \
  "$(q '.jobs.check | "\(.if | test("always\\(\\)")) \(.if | test("default_branch")) \(.needs)"')" "$R | jq .jobs.check"
expect "check: calls scripts/check-status-record with the result of build" "true true" \
  "$(q '.jobs.check.steps[] | select(.run != null) | "\(.run | test("scripts/check-status-record ")) \(.env.BUILD_RESULT | test("needs.build.result"))"')" \
  "$R | jq '.jobs.check.steps'"

# Test seams stay out of the workflows
seams=""
for f in "$REPO_ROOT"/.github/workflows/*.yml; do
  hit="$(grep_matches 'STATUS_FIXTURE_DIR|STATUS_NOW' "$f")"
  [ -z "$hit" ] || seams="$seams $(basename "$f")"
done
expect "no workflow sets STATUS_FIXTURE_DIR or STATUS_NOW" "" "$seams" "grep -nE 'STATUS_FIXTURE_DIR|STATUS_NOW' .github/workflows/*.yml"

#---------------------------------------------------------------------------#
# The step build.read with no branch status, against stand-ins
#---------------------------------------------------------------------------#
stub="$work/stub"
fake="$work/fake"
mkdir -p "$stub" "$fake"
q '.jobs.build.steps[] | select(.id == "read") | .run' > "$work/read.sh"
REPO=test-owner/docker-archlinux

# git: ls-remote ends FAKE_LS_REMOTE (2: no such branch). Nothing else runs.
cat > "$stub/git" << 'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  if [ "$a" = ls-remote ]; then
    exit "${FAKE_LS_REMOTE:-2}"
  fi
done
echo "stand-in git: no answer for: git $*" >&2
exit 1
EOF
# gh api PATH [--jq EXPR]: the answer from FAKE_DIR, by the path without
# its query; each path goes to FAKE_DIR/calls.log.
cat > "$stub/gh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ "${1:-}" = api ] || { echo "stand-in gh: only gh api, not: gh $*" >&2; exit 1; }
shift
path="" expr=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --jq | -q) expr="$2"; shift 2 ;;
    -*) echo "stand-in gh: no flag $1" >&2; exit 1 ;;
    *) path="$1"; shift ;;
  esac
done
printf '%s\n' "$path" >> "$FAKE_DIR/calls.log"
route="${path%%\?*}"
case "$route" in
  repos/*/actions/workflows/status.yml/runs) f="$FAKE_DIR/runs.json" ;;
  repos/*/actions/runs/*/artifacts) r="${route%/artifacts}"; f="$FAKE_DIR/artifacts-${r##*/}.json" ;;
  repos/*/actions/artifacts/*/zip) r="${route%/zip}"; f="$FAKE_DIR/zip-${r##*/}.zip" ;;
  repos/*/actions/artifacts) f="$FAKE_DIR/artifacts.json" ;;
  *) echo "stand-in gh: no answer for: gh api $path" >&2; exit 1 ;;
esac
[ -f "$f" ] || { echo "stand-in gh: HTTP 404 for $path" >&2; exit 1; }
if [ -n "$expr" ]; then jq -r "$expr" "$f"; else cat "$f"; fi
EOF
# unzip -q -o ZIP -d DIR
cat > "$stub/unzip" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
zip="" dir=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -q | -o) shift ;;
    -d) dir="$2"; shift 2 ;;
    *) zip="$1"; shift ;;
  esac
done
python3 -I -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$zip" "$dir"
EOF
chmod +x "$stub/git" "$stub/gh" "$stub/unzip"

# zip_of ID WORD: an artifact zip whose history.jsonl and evidence name WORD
zip_of() {
  python3 -I -c '
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    z.writestr("history.jsonl", "{\"t\":\"2026-10-16T10:23:00Z\",\"from\":\"%s\"}\n" % sys.argv[2])
    z.writestr("evidence/amd64.json", "{\"from\":\"%s\"}\n" % sys.argv[2])
' "$fake/zip-$1.zip" "$2"
}
# run_of ID EVENT REPO: one run of status.yml on main
run_of() {
  jq -nc --argjson id "$1" --arg e "$2" --arg r "$3" \
    '{id: $id, event: $e, status: "completed", head_branch: "main", head_repository: {full_name: $r}}'
}
# artifacts_of ID...: a list of status-history artifacts, of one run or of
# the repository
artifacts_of() {
  jq -nc '{total_count: ($ARGS.positional | length),
           artifacts: [$ARGS.positional[] | {id: tonumber, name: "status-history", expired: false}]}' --args "$@"
}
# Run 9003 is a pull request from a fork, the newest, with a forged artifact.
# Run 9002 kept no artifact. Run 9001 has the artifact to take.
{
  printf '{"total_count": 4, "workflow_runs": [\n'
  run_of 9003 pull_request outsider/docker-archlinux
  printf ',\n'
  run_of 9002 schedule "$REPO"
  printf ',\n'
  run_of 9001 workflow_dispatch "$REPO"
  printf ',\n'
  run_of 9000 schedule "$REPO"
  printf ']}\n'
} > "$fake/runs.json"
artifacts_of 7003 > "$fake/artifacts-9003.json"
artifacts_of > "$fake/artifacts-9002.json"
artifacts_of 7001 > "$fake/artifacts-9001.json"
artifacts_of 7000 > "$fake/artifacts-9000.json"
artifacts_of 7003 7001 7000 > "$fake/artifacts.json"
zip_of 7003 fork
zip_of 7001 own
zip_of 7000 older

# read_step NAME: the step, in RUNNER_TEMP=$work/rt-NAME; sets rc
read_step() {
  local rt="$work/rt-$1"
  mkdir -p "$rt"
  : > "$fake/calls.log"
  rc=0
  env PATH="$stub:$PATH" FAKE_DIR="$fake" RUNNER_TEMP="$rt" GH_TOKEN=stub GITHUB_REPOSITORY="$REPO" \
    GITHUB_SERVER_URL=https://github.invalid DEFAULT_BRANCH=main \
    bash --noprofile --norc -eo pipefail "$work/read.sh" > "$rt.out" 2>&1 || rc=$?
}
RS="yq '.jobs.build.steps[] | select(.id == \"read\") | .run' .github/workflows/status.yml > read.sh; PATH=STUBS:\$PATH bash -eo pipefail read.sh"
# from_of FILE: the field from of FILE, or none when FILE is absent
from_of() {
  if [ -f "$1" ]; then
    jq -r .from "$1" | tr -d '\r'
  else
    echo none
  fi
}

read_step fork-newest
expect "read, no branch status: the step ends 0 and takes the artifact of run 9001, not the forged one of fork run 9003" "0 own own" \
  "$rc $(from_of "$work/rt-fork-newest/status/history.jsonl") $(from_of "$work/rt-fork-newest/status/evidence/amd64.json")" \
  "$RS; $(awk 'END { print }' "$work/rt-fork-newest.out")"

artifacts_of > "$fake/artifacts-9001.json"
artifacts_of > "$fake/artifacts-9000.json"
artifacts_of 7003 > "$fake/artifacts.json"
read_step fork-only
expect "read, no branch status, only the fork run has an artifact: the step ends 0 and the history starts empty" "0 absent" \
  "$rc $([ -e "$work/rt-fork-only/status/history.jsonl" ] && echo present || echo absent)" \
  "$RS; $(awk 'END { print }' "$work/rt-fork-only.out")"

summary
