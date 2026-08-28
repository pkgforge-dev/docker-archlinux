#!/usr/bin/env bash
#
# The evidence must be resolved against the databases the build used.
#
# scripts/gen-evidence joins the image's installed set against the repository
# databases. Fetching those databases again races upstream: a package superseded
# between the build and the evidence run is installed in the image and absent
# from every current database, the join has a hole, and the run fails. Scheduled
# run 33094128354 lost amd64 to exactly that on 2026-08-27, over a window of 63
# seconds, and the merge job then refused to tag a partial release.
#
# The Dockerfile exports the databases pacstrap resolved against, and the build
# job hands that directory to gen-evidence as DB_SNAPSHOT.
#
# ⛔ Four edits put the race back and every other check stays green: moving the
# export after the delete, dropping the export stage, dropping the export step,
# and dropping DB_SNAPSHOT. Those are the first six assertions here.
# HISTORY/evidence-race.md.
#
# ⚠ What this cannot check is whether the export hit the layer cache, so whether
# the exported databases are the ones the image was installed from. Nothing in
# the tree can. gen-evidence still names any package it cannot account for, so
# a miss that mattered fails the run rather than passing quietly.
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
    fail "${f#"$REPO_ROOT/"} exists" "expected: $f" \
      "reproduce: ls ${f#"$REPO_ROOT/"}"
    missing=1
  fi
done
if [ "$missing" -eq 1 ]; then
  summary
  exit 1
fi

#---------------------------------------------------------------------------#
# 1. The Dockerfile exports the databases, from the stage that installed with
#    them, before the step that empties the directory.
#
# ⛔ The order is the whole assertion. After the delete this exports an empty
# directory, gen-evidence then refuses to start, and the failure reads as a
# broken export rather than as a Dockerfile whose two steps swapped places.
#---------------------------------------------------------------------------#
stage_line="$(awk 'index($0, "FROM scratch AS dbsnapshot") { print NR; exit }' "$DF")"
if [ -n "$stage_line" ]; then
  ok "the Dockerfile declares a dbsnapshot stage, at line $stage_line"
else
  fail "the Dockerfile declares a dbsnapshot stage" \
    "no 'FROM scratch AS dbsnapshot' line found" \
    "without it the build job has nothing to export and the evidence run fetches its own databases" \
    "reproduce: grep -n dbsnapshot Dockerfile"
fi

copy_from="$(awk 'index($0, "COPY --from=bootstrap /dbsnapshot") { print NR; exit }' "$DF")"
if [ -n "$copy_from" ]; then
  ok "the dbsnapshot stage takes its content from the bootstrap stage, at line $copy_from"
else
  fail "the dbsnapshot stage takes its content from the bootstrap stage" \
    "no 'COPY --from=bootstrap /dbsnapshot' line found" \
    "a stage that copies from anywhere else is not the databases this build used" \
    "reproduce: grep -n 'from=bootstrap' Dockerfile"
fi

export_line="$(awk 'index($0, "/dbsnapshot/") && index($0, "pacman/sync") { print NR; exit }' "$DF")"
delete_line="$(awk 'index($0, "pacman/sync") && index($0, "-delete") { print NR; exit }' "$DF")"

if [ -z "$export_line" ]; then
  fail "the bootstrap stage copies the synced databases into /dbsnapshot" \
    "no line copies from the sync directory into /dbsnapshot" \
    "the published image carries no databases, so this is the only place they can be taken from" \
    "reproduce: grep -n 'pacman/sync' Dockerfile"
elif [ -z "$delete_line" ]; then
  fail "the bootstrap stage still empties the synced database directory" \
    "no line deletes under the sync directory" \
    "shipping the databases would change the image, and a consumer would read a stale set" \
    "reproduce: grep -n 'pacman/sync' Dockerfile"
elif [ "$export_line" -lt "$delete_line" ]; then
  ok "the databases are copied out (line $export_line) before the directory is emptied (line $delete_line)"
else
  fail "the databases are copied out before the directory is emptied" \
    "the copy is at line $export_line, the delete at line $delete_line" \
    "in this order the export is empty and the evidence run has nothing to read" \
    "reproduce: grep -n 'pacman/sync' Dockerfile"
fi

#---------------------------------------------------------------------------#
# 2. The build job exports that target and hands it to gen-evidence.
#---------------------------------------------------------------------------#
if [ -n "$(awk 'index($0, "target: dbsnapshot") { print NR; exit }' "$WF")" ]; then
  ok "the build job builds the dbsnapshot target"
else
  fail "the build job builds the dbsnapshot target" \
    "no step names 'target: dbsnapshot'" \
    "the stage exists but nothing exports it, so the evidence run falls back to fetching" \
    "reproduce: grep -n dbsnapshot .github/workflows/build-deploy.yml"
fi

dest="$(awk 'index($0, "outputs: type=local,dest=") {
               sub(/.*dest=/, "")
               gsub(/[[:space:]]/, "")
               print
               exit }' "$WF")"
snap="$(awk 'index($0, "DB_SNAPSHOT:") {
               sub(/.*DB_SNAPSHOT:[[:space:]]*/, "")
               gsub(/[[:space:]]/, "")
               print
               exit }' "$WF")"

if [ -z "$snap" ]; then
  fail "the evidence step is given DB_SNAPSHOT" \
    "no DB_SNAPSHOT entry found in the workflow" \
    "⛔ without it gen-evidence fetches its own databases and the race is back, with nothing to show for the export" \
    "reproduce: grep -n DB_SNAPSHOT .github/workflows/build-deploy.yml"
elif [ -z "$dest" ]; then
  fail "the export names a local destination" \
    "no 'outputs: type=local,dest=' entry found, but DB_SNAPSHOT is $snap" \
    "reproduce: grep -n 'type=local' .github/workflows/build-deploy.yml"
elif [ "$dest" = "$snap" ]; then
  ok "the export destination and DB_SNAPSHOT are the same path ($snap)"
else
  fail "the export destination and DB_SNAPSHOT are the same path" \
    "the export writes $dest, the evidence step reads $snap" \
    "reproduce: grep -n 'dest=\\|DB_SNAPSHOT' .github/workflows/build-deploy.yml"
fi

#---------------------------------------------------------------------------#
# 3. gen-evidence refuses a snapshot it cannot use, and says which one.
#
# ⛔ Checked before the image is run, so a wrong path is reported in under a
# second rather than after a pull. That is what lets this run in the static
# suite, with no runtime and no network: CONTAINER_RUNTIME below names a
# command that does not exist, and the refusals happen before anything tries to
# use it.
#---------------------------------------------------------------------------#
work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/repo/scripts" "$work/repo/rootfs/fake/etc/pacman.d" \
  "$work/full" "$work/partial"
cp "$GEN" "$work/repo/scripts/gen-evidence"

printf '[options]\nArchitecture = x86_64\n\n[core]\nInclude = /etc/pacman.d/mirrorlist\n\n[extra]\nInclude = /etc/pacman.d/mirrorlist\n' \
  > "$work/repo/rootfs/fake/etc/pacman.conf"
# shellcheck disable=SC2016
# The two dollar signs are literal. pacman's mirrorlist syntax spells the
# repository and the architecture that way, and gen-evidence substitutes them.
# The host is unreachable on purpose: nothing here is allowed to fetch.
printf 'Server = https://example.invalid/$repo/os/$arch\n' \
  > "$work/repo/rootfs/fake/etc/pacman.d/mirrorlist"

# A complete snapshot, and one missing the database for the second enabled
# repository. The files are empty: the refusals under test happen before
# anything reads them.
: > "$work/full/core.db"
: > "$work/full/extra.db"
: > "$work/partial/core.db"

# run_gen SNAPSHOT -> the exit code, with stderr left in $work/err
run_gen() {
  local rc=0
  (
    cd "$work/repo" &&
    CONTAINER_RUNTIME=gen-evidence-has-no-runtime DB_SNAPSHOT="$1" \
      bash scripts/gen-evidence fake localhost/none:test linux/amd64 "$work/out.json"
  ) > "$work/out" 2> "$work/err" || rc=$?
  printf '%s\n' "$rc"
}

# said NEEDLE -> 0 when the captured stderr carries it
said() {
  awk -v n="$1" 'index($0, n) { found = 1 } END { exit found ? 0 : 1 }' "$work/err"
}

rc="$(run_gen "$work/no-such-directory")"
if [ "$rc" -ne 0 ] && said "which is not a directory"; then
  ok "a DB_SNAPSHOT that is not a directory is refused, exit $rc"
else
  fail "a DB_SNAPSHOT that is not a directory is refused" \
    "exit $rc, and stderr was: $(tr -d '\r' < "$work/err" | awk 'NF { last = $0 } END { print last }')" \
    "a path typo would otherwise be read as an empty snapshot" \
    "reproduce: bash tests/static/68-evidence-snapshot.sh, which keeps its fixtures under a temp dir"
fi

rc="$(run_gen "$work/partial")"
if [ "$rc" -ne 0 ] && said "carries no extra.db"; then
  ok "a snapshot missing a database for an enabled repository is refused, and names it"
else
  fail "a snapshot missing a database for an enabled repository is refused, and names it" \
    "exit $rc, and stderr was: $(tr -d '\r' < "$work/err" | awk 'NF { last = $0 } END { print last }')" \
    "⛔ an export that produced only some of the databases would otherwise join against a partial set" \
    "reproduce: bash tests/static/68-evidence-snapshot.sh, which keeps its fixtures under a temp dir"
fi

#---------------------------------------------------------------------------#
# The control. Without it the two assertions above are satisfied by a script
# that refuses everything.
#---------------------------------------------------------------------------#
rc="$(run_gen "$work/full")"
if said "DB_SNAPSHOT"; then
  fail "a snapshot holding every enabled repository's database is accepted" \
    "it was refused: $(tr -d '\r' < "$work/err" | awk 'NF { last = $0 } END { print last }')" \
    "a check that refuses every snapshot passes the two assertions above and means nothing" \
    "reproduce: bash tests/static/68-evidence-snapshot.sh, which keeps its fixtures under a temp dir"
else
  ok "a snapshot holding every enabled repository's database is accepted, and the run goes on to the image (exit $rc)"
fi

summary
