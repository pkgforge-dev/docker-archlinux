#!/usr/bin/env bash
#
# Check that each workflow builds and tests the commit that started it.
#
#   - no run: block runs git clone; a clone gets the default branch, not the
#     commit of the run
#   - a checkout with a fixed ref (a branch name or a hash) also has a path,
#     so it is a second tree of data, not the code under test
#   - each job that runs a file of scripts/ or tests/ checks the tree out
#     before that step
#   - each image build reads the checked-out tree: build-push-action has no
#     context, ".", or ${{ github.workspace }}; a docker build command ends
#     in "." or "$GITHUB_WORKSPACE"
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

cd "$REPO_ROOT"
work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

if ! need_tool yq jq; then
  rc=0
  summary || rc=$?
  exit "$rc"
fi

mapfile -t wfs < <(find .github/workflows -type f \( -name '*.yml' -o -name '*.yaml' \) | LC_ALL=C sort)
if [ "${#wfs[@]}" -eq 0 ]; then
  fail "there are workflows" "no .github/workflows/*.yml" "reproduce: ls .github/workflows"
  summary
  exit 1
fi

# The rules, in one jq program. Each fault line is "<rule><TAB><text>".
# shellcheck disable=SC2016 # a jq program, not shell
program='
  def steps_of: .value.steps // [] | to_entries;
  def is_checkout: (.uses // "") | startswith("actions/checkout@");
  (.jobs | to_entries[] | .key as $j | steps_of[] | .value
    | select((.run // "") | tostring | test("(^|[^A-Za-z0-9_-])git[[:space:]]+clone([[:space:]]|$)"))
    | "clone\t\($j): \(.name // .id // "a step")"),
  (.jobs | to_entries[] | .key as $j | steps_of[] | .value | select(is_checkout)
    | select(((.with // {}).ref // null) as $r | $r != null and ($r | tostring | test("\\$\\{\\{") | not))
    | select(((.with // {}).path // "") == "")
    | "ref\t\($j): ref \(.with.ref) with no path"),
  (.jobs | to_entries[] | .key as $j
    | ([steps_of[] | select(.value | is_checkout) | .key] | min // 1e9) as $co
    | steps_of[] | select(.key < $co)
    | select((.value.run // "") | tostring | test("(^|[[:space:];|&(=\"])(\\./)?(scripts|tests)/[A-Za-z0-9_.-]+"))
    | "checkout\t\($j): \(.value.name // .value.id // "step \(.key)") runs a file of the tree before any checkout"),
  (.jobs | to_entries[] | .key as $j | steps_of[] | .value
    | select((.uses // "") | startswith("docker/build-push-action@"))
    | select(((.with // {}).context // ".") as $c | ($c != "." and ($c | test("^\\$\\{\\{[[:space:]]*github\\.workspace[[:space:]]*\\}\\}$") | not)))
    | "context\t\($j): context \(.with.context)"),
  (.jobs | to_entries[] | .key as $j | steps_of[] | .value | select(.run != null)
    | .run | tostring | gsub("\\\\\n"; " ") | split("\n")[]
    | select(test("(^|[[:space:]])docker([[:space:]]+buildx)?[[:space:]]+build[[:space:]]"))
    | select(test("[[:space:]](\\.|\"?\\$\\{?GITHUB_WORKSPACE\\}?\"?)[[:space:]]*$") | not)
    | "context\t\($j): \(.)")
'

declare -A hits=([clone]="" [ref]="" [checkout]="" [context]="")
for wf in "${wfs[@]}"; do
  rc=0
  out="$(yaml_json "$wf" | jq -r "$program" 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "$wf: reads as a workflow" "$out" "reproduce: yq -o=json . $wf"
    continue
  fi
  while IFS=$'\t' read -r rule text; do
    [ -n "$rule" ] || continue
    hits[$rule]="${hits[$rule]}$wf: $text; "
  done <<< "$out"
done

check_eq "no run: block runs git clone" "" "${hits[clone]}" \
  "grep -n 'git clone' .github/workflows/*.yml; use actions/checkout"
check_eq "a checkout with a fixed ref also has a path" "" "${hits[ref]}" \
  "yq '.jobs[].steps[] | select(.uses == \"actions/checkout*\") | .with' .github/workflows/*.yml"
check_eq "each job checks the tree out before it runs a file of scripts/ or tests/" "" "${hits[checkout]}" \
  "yq '.jobs[].steps[] | [.uses, .run]' .github/workflows/*.yml"
check_eq "each image build reads the checked-out tree" "" "${hits[context]}" \
  "grep -nE 'context:|docker (buildx )?build' .github/workflows/*.yml"

summary
