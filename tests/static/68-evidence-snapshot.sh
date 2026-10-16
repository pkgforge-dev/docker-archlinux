#!/usr/bin/env bash
#
# The evidence is made from the databases that the build used.
#
# scripts/gen-evidence joins the packages in the image with the repository
# databases. A second fetch of the databases can see newer ones: a package
# that moved after the build is in the image and in no database, and the
# evidence has a hole. So the Dockerfile exports the databases of the build,
# and the build leg gives that directory to gen-evidence as DB_SNAPSHOT.
#
#   1. The Dockerfile copies the databases out before it empties the
#      directory, and its dbsnapshot stage takes them from bootstrap.
#   2. The build leg exports the dbsnapshot target to the path that the
#      evidence step reads (yq).
#   3. gen-evidence refuses a snapshot that it cannot use, with exit 3, before
#      it runs the image.
#
# ⚠ This cannot check that the export hit the build cache. gen-evidence
# names each package that it cannot find, so a miss fails the leg.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

DF="$REPO_ROOT/Dockerfile"
WF="$REPO_ROOT/.github/workflows/build-deploy.yml"
GEN="$REPO_ROOT/scripts/gen-evidence"

missing=0
for f in "$DF" "$WF" "$GEN"; do
  if [ ! -f "$f" ]; then
    fail "${f#"$REPO_ROOT/"} exists" "reproduce: ls ${f#"$REPO_ROOT/"}"
    missing=1
  fi
done
if [ "$missing" -eq 1 ]; then
  summary
  exit 1
fi

work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

#---------------------------------------------------------------------------#
# 1. The Dockerfile.
#---------------------------------------------------------------------------#
stage_line="$(awk '$1 == "FROM" && $2 == "scratch" && toupper($3) == "AS" && $4 == "dbsnapshot" { print NR; exit }' "$DF")"
if [ -n "$stage_line" ]; then
  ok "the Dockerfile has a dbsnapshot stage, at line $stage_line"
else
  fail "the Dockerfile has a dbsnapshot stage" "no 'FROM scratch AS dbsnapshot' line" \
    "without it the build has nothing to export" "reproduce: grep -n dbsnapshot Dockerfile"
fi

copy_from="$(awk '$1 == "COPY" && $2 == "--from=bootstrap" && $3 == "/dbsnapshot" { print NR; exit }' "$DF")"
if [ -n "$copy_from" ]; then
  ok "the dbsnapshot stage takes its files from the bootstrap stage, at line $copy_from"
else
  fail "the dbsnapshot stage takes its files from the bootstrap stage" "no 'COPY --from=bootstrap /dbsnapshot' line" \
    "files from another stage are not the databases of this build" "reproduce: grep -n 'from=bootstrap' Dockerfile"
fi

export_line="$(awk 'index($0, "/dbsnapshot/") && index($0, "pacman/sync") { print NR; exit }' "$DF")"
delete_line="$(awk 'index($0, "pacman/sync") && index($0, "-delete") { print NR; exit }' "$DF")"
if [ -z "$export_line" ] || [ -z "$delete_line" ]; then
  fail "the bootstrap stage copies the sync databases to /dbsnapshot, then empties the sync directory" \
    "copy at line ${export_line:-none}, delete at line ${delete_line:-none}" \
    "reproduce: grep -n 'pacman/sync' Dockerfile"
elif [ "$export_line" -lt "$delete_line" ]; then
  ok "the databases are copied out (line $export_line) before the directory is emptied (line $delete_line)"
else
  fail "the databases are copied out before the directory is emptied" \
    "copy at line $export_line, delete at line $delete_line" \
    "in this order the export is empty" "reproduce: grep -n 'pacman/sync' Dockerfile"
fi

#---------------------------------------------------------------------------#
# 2. The build leg (yq).
#---------------------------------------------------------------------------#
if need_tool yq jq; then
  rc=0
  yaml_json "$WF" > "$work/wf.json" 2> "$work/wf.err" || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "the build workflow reads as YAML" "yq exited $rc: $(tr '\n' ' ' < "$work/wf.err")" \
      "reproduce: yq . .github/workflows/build-deploy.yml"
  else
    dest="$(jq -r '[.jobs.build.steps[] | select(.with.target == "dbsnapshot") | .with.outputs
                   | capture("^type=local,dest=(?<d>.+)$").d] | join(" ")' "$work/wf.json")"
    snap="$(jq -r '[.jobs.build.steps[] | select((.run // "") | test("scripts/gen-evidence")) | .env.DB_SNAPSHOT // ""] | join(" ")' "$work/wf.json")"
    if [ -z "$dest" ]; then
      fail "the build leg exports the dbsnapshot target to a local directory" "no step with target dbsnapshot and type=local" \
        "reproduce: yq '.jobs.build.steps' .github/workflows/build-deploy.yml"
    elif [ -z "$snap" ]; then
      fail "the evidence step has DB_SNAPSHOT" "the step that runs scripts/gen-evidence has none" \
        "⛔ without it gen-evidence fetches the databases again" \
        "reproduce: yq '.jobs.build.steps' .github/workflows/build-deploy.yml"
    elif [ "$dest" = "$snap" ]; then
      ok "the export directory and DB_SNAPSHOT are the same path ($snap)"
    else
      fail "the export directory and DB_SNAPSHOT are the same path" "export: $dest; DB_SNAPSHOT: $snap" \
        "reproduce: yq '.jobs.build.steps' .github/workflows/build-deploy.yml"
    fi
  fi
fi

#---------------------------------------------------------------------------#
# 3. gen-evidence refuses a snapshot that it cannot use.
#
# The refusals come before the image runs, so this needs no runtime and no
# network: CONTAINER_RUNTIME names a command that does not exist.
#---------------------------------------------------------------------------#
mkdir -p "$work/repo/scripts" "$work/repo/rootfs/fake/etc/pacman.d" "$work/full" "$work/partial"
cp "$GEN" "$work/repo/scripts/gen-evidence"
printf '[options]\nArchitecture = x86_64\n\n[core]\nInclude = /etc/pacman.d/mirrorlist\n\n[extra]\nInclude = /etc/pacman.d/mirrorlist\n' \
  > "$work/repo/rootfs/fake/etc/pacman.conf"
# The host cannot be reached: nothing here may fetch.
printf 'Server = https://example.invalid/repo/os/arch\n' > "$work/repo/rootfs/fake/etc/pacman.d/mirrorlist"
: > "$work/full/core.db"
: > "$work/full/extra.db"
: > "$work/partial/core.db"

# run_gen SNAPSHOT -> the exit code; stderr in $work/err
run_gen() {
  local rc=0
  (
    cd "$work/repo" &&
      CONTAINER_RUNTIME=gen-evidence-has-no-runtime DB_SNAPSHOT="$1" \
        bash scripts/gen-evidence fake localhost/none:test linux/amd64 "$work/out.json"
  ) > "$work/out" 2> "$work/err" || rc=$?
  printf '%s\n' "$rc"
}
said() { awk -v n="$1" 'index($0, n) { found = 1 } END { exit found ? 0 : 1 }' "$work/err"; }
last_words() { tr -d '\r' < "$work/err" | awk 'NF { last = $0 } END { print last }'; }
repro="bash tests/static/68-evidence-snapshot.sh; the fixtures are made in the test"

rc="$(run_gen "$work/no-such-directory")"
if [ "$rc" -eq 3 ]; then
  ok "a DB_SNAPSHOT that is not a directory is refused with exit 3"
else
  fail "a DB_SNAPSHOT that is not a directory is refused with exit 3" "exit $rc: $(last_words)" "reproduce: $repro"
fi

rc="$(run_gen "$work/partial")"
if [ "$rc" -eq 3 ] && said "extra.db"; then
  ok "a snapshot with no database for an enabled repository is refused with exit 3, and names it"
else
  fail "a snapshot with no database for an enabled repository is refused with exit 3, and names it" \
    "exit $rc: $(last_words)" "⛔ a partial export would join against part of the set" "reproduce: $repro"
fi

# The control: a full snapshot passes these checks and goes on to the image,
# which fails here (no runtime) with another code.
rc="$(run_gen "$work/full")"
if [ "$rc" -ne 3 ] && [ "$rc" -ne 0 ]; then
  ok "a snapshot with each enabled database passes, and the run goes on to the image (exit $rc)"
else
  fail "a snapshot with each enabled database passes, and the run goes on to the image" \
    "exit $rc: $(last_words)" "a check that refuses each snapshot passes the two tests above" "reproduce: $repro"
fi

summary
