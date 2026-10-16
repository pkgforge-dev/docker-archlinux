#!/usr/bin/env bash
#
# scripts/build-port makes the builder of a build leg and runs its two
# builds. When a pull fails on a used-up pull limit, the mode runs once more
# with the same digest from the next registry.
#
#   1. push: the build args, the push by digest, the outputs; the second try
#      on a pull limit, and no second try for any other failure.
#   2. snapshot: the export of the target dbsnapshot, with the same build
#      args, and the same second try.
#   3. builder: the pull of the buildkit image, and the builder that runs
#      it.
#
# A stand-in docker (tests/fixtures/36-build-port/fake-docker) records each
# call. scripts/pick-base-image reads the registry answers from a fixture
# that the test makes. No registry and no container runtime is called.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

BP="$REPO_ROOT/scripts/build-port"
FX="$(fixture_dir)"

for f in "$BP" "$REPO_ROOT/scripts/pick-base-image" "$FX/fake-docker"; do
  if [ ! -x "$f" ]; then
    fail "${f#"$REPO_ROOT/"} is executable" "reproduce: ls -l ${f#"$REPO_ROOT/"}"
    summary
    exit 1
  fi
done
if ! need_tool jq timeout; then
  summary
  exit 0
fi

work="$(work_dir)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/fx"
cp "$FX/fake-docker" "$work/bin/docker"
chmod +x "$work/bin/docker"
repro="bash tests/static/36-build-port.sh; the stand-in docker is tests/fixtures/36-build-port/fake-docker"

# The BASE_IMAGE pin of the Dockerfile, and the same digest on each registry.
pin="$(awk '/^[[:space:]]*ARG[[:space:]]+BASE_IMAGE=/ { sub(/^[^=]*=/, ""); print }' "$REPO_ROOT/Dockerfile")"
d="${pin##*@}"
repo="${pin#docker.io/}"
repo="${repo%%@*}"
repo="${repo%:*}"
hub="$pin"
gcr="mirror.gcr.io/$repo@$d"
ecr="public.ecr.aws/docker/$repo@$d"

# A buildkit pin that is not a Docker official image, so ECR Public is not
# asked. LONE is served by docker.io only.
BK_D="sha256:$(printf '%064d' 7)"
BK="docker.io/example/buildkit:stable@$BK_D"
BK_GCR="mirror.gcr.io/example/buildkit@$BK_D"
LONE_D="sha256:$(printf '%064d' 8)"
LONE="docker.io/example/lone:stable@$LONE_D"

{
  printf 'docker.io\t%s\t%s\t200\t%s\n' "$repo" "$d" "$d"
  printf 'mirror.gcr.io\t%s\t%s\t200\t%s\n' "$repo" "$d" "$d"
  printf 'public.ecr.aws\tdocker/%s\t%s\t200\t%s\n' "$repo" "$d" "$d"
  printf 'docker.io\texample/buildkit\t%s\t200\t%s\n' "$BK_D" "$BK_D"
  printf 'mirror.gcr.io\texample/buildkit\t%s\t200\t%s\n' "$BK_D" "$BK_D"
  printf 'docker.io\texample/lone\t%s\t200\t%s\n' "$LONE_D" "$LONE_D"
} > "$work/fx/heads.tsv"

P1="$("$REPO_ROOT/scripts/ports" list | awk 'NR == 1')"
PLAT="$("$REPO_ROOT/scripts/ports" get "$P1" platform)"
TARGET="ghcr.io/example/archlinux-ci"
DIGEST="sha256:$(printf '%064d' 5)"
SNAP="$work/dbsnapshot"

# bp NAME MODE [VAR=VALUE ...] -> the exit code. The docker calls go to
# $work/NAME.calls, the step outputs to $work/NAME.outputs.
bp() {
  local name="$1" mode="$2" rc=0
  shift 2
  : > "$work/$name.calls"
  : > "$work/$name.outputs"
  env -u GITHUB_RUN_ID -u FAKE_DOCKER_LIMITED -u FAKE_DOCKER_FAIL \
    PATH="$work/bin:$PATH" FAKE_DOCKER_LOG="$work/$name.calls" FAKE_DOCKER_DIGEST="$DIGEST" \
    GITHUB_OUTPUT="$work/$name.outputs" ARCH="$P1" PLATFORM="$PLAT" TARGET_IMAGE="$TARGET" \
    DB_SNAPSHOT="$SNAP" IMAGE_VERSION=2030.01.02 SOURCE_COMMIT="$(printf '%040d' 1)" \
    BUILD_DATE=2030-01-02T05:30:00Z TRANSPORT=worker SKIP_SERVERS= "$@" \
    "$BP" --fixtures "$work/fx" "$mode" > "$work/$name.out" 2> "$work/$name.err" || rc=$?
  printf '%s\n' "$rc"
}

# bases NAME: the BASE_IMAGE build arg of each build, in order, space separated.
bases() {
  awk -F'\t' '$1 == "buildx" && $2 == "build" {
      for (i = 3; i < NF; i++) if ($i == "--build-arg" && index($(i + 1), "BASE_IMAGE=") == 1) printf "%s%s", sep, substr($(i + 1), 12)
      sep = " "
    }
    END { print "" }' "$work/$1.calls"
}

# opts NAME N OPTION: each value of OPTION in build N of NAME, space separated.
opts() {
  awk -F'\t' -v n="$2" -v o="$3" '$1 == "buildx" && $2 == "build" && ++k == n {
      for (i = 3; i < NF; i++) if ($i == o) { printf "%s%s", sep, $(i + 1); sep = " " }
    }
    END { print "" }' "$work/$1.calls"
}

# lastarg NAME N: the last argument of build N of NAME, the build context.
lastarg() {
  awk -F'\t' -v n="$2" '$1 == "buildx" && $2 == "build" && ++k == n { print $NF }' "$work/$1.calls"
}

# out NAME KEY: the value of KEY in the step outputs of NAME.
out() {
  awk -v k="$2" 'index($0, k "=") == 1 { print substr($0, length(k) + 2) }' "$work/$1.outputs"
}

# calls NAME WORD...: the number of docker calls that start with WORD...
calls() {
  local name="$1"
  shift
  awk -F'\t' -v w="$*" '{
      s = $1
      for (i = 2; i <= split(w, x, " "); i++) s = s " " $i
      if (s == w) n++
    }
    END { print n + 0 }' "$work/$name.calls"
}

#---------------------------------------------------------------------------#
# 1. push
#---------------------------------------------------------------------------#
rc="$(bp limit push BASE_IMAGE="$hub" FAKE_DOCKER_LIMITED=docker.io)"
check_eq "⭐ push: when the docker.io pull limit runs out after the pick, the build runs once more with the same digest from mirror.gcr.io" \
  "0|$hub $gcr|$gcr|$DIGEST" "$rc|$(bases limit)|$(out limit base_image)|$(out limit digest)" "$repro"

rc="$(bp plain push BASE_IMAGE="$hub")"
check_eq "push: with pulls left, one build from the value of the pick" \
  "0|$hub|$hub|$DIGEST" "$rc|$(bases plain)|$(out plain base_image)|$(out plain digest)" "$repro"

# The build args are the ARGs of the Dockerfile, without the platform ARGs
# that BuildKit sets.
want_args="$(awk '/^[[:space:]]*ARG[[:space:]]/ { sub(/=.*/, "", $2); print $2 }' "$REPO_ROOT/Dockerfile" |
  awk '$1 !~ /^(TARGET|BUILD)(PLATFORM|OS|ARCH|VARIANT)$/' | LC_ALL=C sort -u | awk '{ printf "%s%s", sep, $1; sep = " " } END { print "" }')"
got_args="$(opts plain 1 --build-arg | tr ' ' '\n' | sed 's/=.*//' | LC_ALL=C sort -u | awk '{ printf "%s%s", sep, $1; sep = " " } END { print "" }')"
check_eq "push: the build args are the ARGs of the Dockerfile" "$want_args" "$got_args" \
  "grep -n '^ARG' Dockerfile; $repro"

check_eq "push: the build pushes by digest to TARGET_IMAGE, on the builder, for the platform of the port, from the tree" \
  "type=image,name=$TARGET,push-by-digest=true,name-canonical=true,push=true|docker-archlinux|$PLAT|$REPO_ROOT" \
  "$(opts plain 1 --output)|$(opts plain 1 --builder)|$(opts plain 1 --platform)|$(lastarg plain 1)" "$repro"
check_eq "push: the image has a provenance attestation (mode=max) and an SBOM" \
  "type=provenance,mode=max type=sbom,disabled=false" "$(opts plain 1 --attest)" "$repro"
check_eq "push: the gha cache of the port is read and written, and a cache service error does not stop the build" \
  "type=gha,scope=$P1|type=gha,mode=max,scope=$P1,ignore-error=true" \
  "$(opts plain 1 --cache-from)|$(opts plain 1 --cache-to)" "$repro"

rc="$(bp other push BASE_IMAGE="$hub" FAKE_DOCKER_FAIL='ERROR: failed to solve: process "/bin/sh -c pacstrap" did not complete successfully: exit code: 1')"
check_eq "push: a build that fails for another reason runs once, and the step fails with no digest" \
  "1|$hub|" "$rc|$(bases other)|$(out other digest)" "$repro"

rc="$(bp mirror push BASE_IMAGE="$hub" FAKE_DOCKER_FAIL='pacman-oci: ghcr.io/example/mirror: 429 Too Many Requests: toomanyrequests')"
check_eq "push: a 429 line that does not name the base image is not its pull limit, so the build runs once" \
  "1|$hub" "$rc|$(bases mirror)" "$repro"

rc="$(bp twice push BASE_IMAGE="$hub" FAKE_DOCKER_LIMITED="docker.io mirror.gcr.io")"
check_eq "push: a second used-up pull limit stops the step: one more build, not two" \
  "1|$hub $gcr" "$rc|$(bases twice)" "$repro"

rc="$(bp last push BASE_IMAGE="$ecr" FAKE_DOCKER_LIMITED=public.ecr.aws)"
check_eq "push: with no registry after the one that met the pull limit, the step stops after one build" \
  "1|$ecr" "$rc|$(bases last)" "$repro"

rc="$(bp unset push BASE_IMAGE="$hub" TRANSPORT=)"
check_eq "push: a missing build variable stops the step before any docker call" \
  "1|0" "$rc|$(awk 'END { print NR }' "$work/unset.calls")" "$repro"

#---------------------------------------------------------------------------#
# 2. snapshot
#---------------------------------------------------------------------------#
rc="$(bp snap snapshot BASE_IMAGE="$hub" FAKE_DOCKER_LIMITED=docker.io)"
check_eq "⭐ snapshot: when the docker.io pull limit runs out, the export runs once more with the same digest from mirror.gcr.io" \
  "0|$hub $gcr|$gcr" "$rc|$(bases snap)|$(out snap base_image)" "$repro"
check_eq "snapshot: the build exports the target dbsnapshot to DB_SNAPSHOT, on the builder, from the tree" \
  "dbsnapshot|type=local,dest=$SNAP|docker-archlinux|$PLAT|$REPO_ROOT" \
  "$(opts snap 2 --target)|$(opts snap 2 --output)|$(opts snap 2 --builder)|$(opts snap 2 --platform)|$(lastarg snap 2)" "$repro"

rc="$(bp snap-plain snapshot BASE_IMAGE="$hub")"
check_eq "snapshot: the export has the build args and the cache of the push, so the bootstrap stage is the same one" \
  "0|$(opts plain 1 --build-arg)|$(opts plain 1 --cache-from)" \
  "$rc|$(opts snap-plain 1 --build-arg)|$(opts snap-plain 1 --cache-from)" "$repro"

#---------------------------------------------------------------------------#
# 3. builder
#---------------------------------------------------------------------------#
# pulls NAME: the image of each pull, in order, space separated.
pulls() {
  awk -F'\t' '$1 == "pull" { printf "%s%s", sep, $2; sep = " " } END { print "" }' "$work/$1.calls"
}

rc="$(bp bk builder BUILDKIT_IMAGE="$BK" FAKE_DOCKER_LIMITED=docker.io)"
check_eq "⭐ builder: when the docker.io pull limit runs out after the pick, the builder runs the same digest from mirror.gcr.io" \
  "0|$BK $BK_GCR|image=$BK_GCR|$BK_GCR|1" \
  "$rc|$(pulls bk)|$(awk -F'\t' '$1 == "buildx" && $2 == "create" { for (i = 3; i < NF; i++) if ($i == "--driver-opt") print $(i + 1) }' "$work/bk.calls")|$(out bk ref)|$(calls bk buildx inspect)" \
  "$repro"

rc="$(bp bk-plain builder BUILDKIT_IMAGE="$BK")"
check_eq "builder: with pulls left, the builder runs the value of the pick, and is the current builder" \
  "0|$BK|1|$BK" \
  "$rc|$(pulls bk-plain)|$(awk -F'\t' '$1 == "buildx" && $2 == "create" { for (i = 3; i <= NF; i++) if ($i == "--use") n++ } END { print n + 0 }' "$work/bk-plain.calls")|$(out bk-plain ref)" \
  "$repro"

rc="$(bp lone builder BUILDKIT_IMAGE="$LONE" FAKE_DOCKER_LIMITED=docker.io)"
check_eq "builder: with no other registry that serves the digest, the step stops after one pull and makes no builder" \
  "1|$LONE|0" "$rc|$(pulls lone)|$(calls lone buildx create)" "$repro"

#---------------------------------------------------------------------------#
# 4. The steps of build-deploy.yml that run scripts/build-port
#---------------------------------------------------------------------------#
# Each step runs the script with the variables of the job and of the step,
# and no others. A variable that the mode needs and does not get stops the
# script before any docker call. A value with ${{ }} is "x" here.
WF="$REPO_ROOT/.github/workflows/build-deploy.yml"
if need_tool yq; then
  rc=0
  yaml_json "$WF" > "$work/wf.json" 2> "$work/wf.err" || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "the build workflow reads as YAML" "yq exited $rc: $(tr '\n' ' ' < "$work/wf.err")" \
      "reproduce: yq . .github/workflows/build-deploy.yml"
  else
    # One line for each step: id, mode, then NAME=VALUE for each variable.
    jq -r '.jobs.build as $b | $b.steps[]
      | select((.run // .with.script // "") | tostring | test("scripts/build-port"))
      | [.id, ((.run // .with.script) | capture("scripts/build-port[^a-z]*(?<m>[a-z]+)").m)]
        + [(($b.env // {}) + (.env // {})) | to_entries[]
            | "\(.key)=\(.value | tostring | if test("\\$\\{\\{") then "x" else . end)"]
      | join("\t")' "$work/wf.json" > "$work/wire.tsv"
    # The buildkit pin of the workflow, served by docker.io.
    wf_bk="$(awk -F'\t' '{ for (i = 3; i <= NF; i++) if (index($i, "BUILDKIT_IMAGE=") == 1) print substr($i, 16) }' "$work/wire.tsv")"
    if [[ "$wf_bk" =~ ^docker\.io/([a-z0-9._/-]+):[A-Za-z0-9._-]+@(sha256:[0-9a-f]{64})$ ]]; then
      printf 'docker.io\t%s\t%s\t200\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[2]}" >> "$work/fx/heads.tsv"
    fi
    got=""
    while IFS=$'\t' read -r -a f; do
      [ "${#f[@]}" -ge 2 ] || continue
      : > "$work/wire.calls"
      rc=0
      env -i PATH="$work/bin:$PATH" FAKE_DOCKER_LOG="$work/wire.calls" FAKE_DOCKER_DIGEST="$DIGEST" \
        GITHUB_OUTPUT="$work/wire.outputs" "${f[@]:2}" \
        "$BP" --fixtures "$work/fx" "${f[1]}" > "$work/wire.out" 2> "$work/wire.err" || rc=$?
      got="$got ${f[0]}:${f[1]}:$rc"
      [ "$rc" -eq 0 ] || diag "${f[0]}: $(tr '\n' '|' < "$work/wire.err")"
    done < "$work/wire.tsv"
    check_eq "each step that runs scripts/build-port gives it every variable of its mode" \
      " buildkit:builder:0 push:push:0 snapshot:snapshot:0" "$got" \
      "yq '.jobs.build.env, (.jobs.build.steps[] | select(.id == \"buildkit\" or .id == \"push\" or .id == \"snapshot\") | .env)' .github/workflows/build-deploy.yml"
  fi
fi

summary
