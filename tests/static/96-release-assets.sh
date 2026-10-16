#!/usr/bin/env bash
#
# The release rules.
#
#   - release.yml is the one workflow that a v* tag starts. It also runs on a
#     monthly schedule, and a dispatch publishes nothing.
#   - The publish job needs every producing job, and it is the one job with
#     contents: write. It uploads with --clobber to a draft and publishes the
#     draft last.
#   - The ports come from scripts/ports, never from a list in the workflow.
#   - scripts/release-notes refuses a release with a hole, and its body names
#     no version or date that its inputs do not give.
#   - scripts/gen-bootstrap-set and scripts/gen-manifest, against fixtures.
#   - Each gen-evidence call in a workflow sets CONTAINER_RUNTIME.
#
# The workflows are read with yq, not as text. No network.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

WF_DIR="$REPO_ROOT/.github/workflows"
RELEASE="$WF_DIR/release.yml"
PACMAN_WF="$WF_DIR/pacman-static.yml"
NOTES="$REPO_ROOT/scripts/release-notes"
MANIFEST="$REPO_ROOT/scripts/gen-manifest"
BSET="$REPO_ROOT/scripts/gen-bootstrap-set"

for f in "$RELEASE" "$PACMAN_WF" "$NOTES" "$MANIFEST" "$BSET"; do
  if [ ! -f "$f" ]; then
    fail "${f#"$REPO_ROOT/"} exists" "reproduce: ls -l ${f#"$REPO_ROOT/"}"
    summary
    exit 1
  fi
done

work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

#---------------------------------------------------------------------------#
# 1. The workflow structure.
#---------------------------------------------------------------------------#
if need_tool yq jq; then
  bad_yaml=""
  mkdir -p "$work/wf"
  for wf in "$WF_DIR"/*.yml; do
    rc=0
    yaml_json "$wf" > "$work/wf/$(basename "$wf" .yml).json" || rc=$?
    [ "$rc" -eq 0 ] || bad_yaml="$bad_yaml $(basename "$wf")"
  done
  if [ -n "$bad_yaml" ]; then
    fail "every workflow is valid YAML" "yq failed on:$bad_yaml" \
      "reproduce: yq . .github/workflows/<file>"
  fi
  R="$work/wf/release.json"
  r() { jq -r "$1" "$R"; }

  # ⛔ Two workflows on one tag race, and the second fails after the first
  # published.
  taggers=""
  for j in "$work"/wf/*.json; do
    n="$(jq -r '(.on // {}) | if type == "object" then ((.push.tags // []) | map(select(startswith("v"))) | length) else 0 end' "$j")"
    [ "$n" -eq 0 ] || taggers="$taggers $(basename "$j" .json).yml"
  done
  if [ "$taggers" = " release.yml" ]; then
    ok "release.yml is the one workflow that a v* tag starts"
  else
    fail "release.yml is the one workflow that a v* tag starts" \
      "workflows with a v* tag trigger:${taggers:- none}" \
      "reproduce: yq '.on.push.tags' .github/workflows/*.yml"
  fi

  cron="$(r '.on.schedule[0].cron // ""')"
  dispatch="$(r '.on | has("workflow_dispatch")')"
  if printf '%s\n' "$cron" | awk 'NF == 5 && $3 ~ /^[0-9]+$/ && $4 == "*" && $5 == "*" { hit = 1 } END { exit hit ? 0 : 1 }' \
    && [ "$dispatch" = true ]; then
    ok "release.yml runs once a month and on dispatch"
  else
    fail "release.yml runs once a month and on dispatch" \
      "cron: ${cron:-none}, workflow_dispatch: $dispatch" \
      "reproduce: yq '.on' .github/workflows/release.yml"
  fi

  perms="$(r '.permissions | tojson')"
  if [ "$perms" = "{}" ]; then
    ok "release.yml grants no permission at the top"
  else
    fail "release.yml grants no permission at the top" "permissions: $perms" \
      "reproduce: yq '.permissions' .github/workflows/release.yml"
  fi

  uses="$(r '.jobs.pacman.uses // ""')"
  called="$(jq -r '.on | has("workflow_call")' "$work/wf/pacman-static.json")"
  if [ "$uses" = "./.github/workflows/pacman-static.yml" ] && [ "$called" = true ]; then
    ok "release.yml calls pacman-static.yml for the binaries"
  else
    fail "release.yml calls pacman-static.yml for the binaries" \
      "jobs.pacman.uses: ${uses:-none}, pacman-static.yml workflow_call: $called" \
      "a second copy of the build recipe goes stale" \
      "reproduce: yq '.jobs.pacman' .github/workflows/release.yml"
  fi

  needs="$(r '.jobs.publish.needs // [] | if type == "array" then . else [.] end | sort | join(" ")')"
  missing=""
  for job in guard pacman rootfs manifest; do
    case " $needs " in *" $job "*) ;; *) missing="$missing $job" ;; esac
  done
  if [ -z "$missing" ]; then
    ok "the publish job needs every producing job: $needs"
  else
    fail "the publish job needs every producing job" \
      "needs: ${needs:-none}, missing:$missing" \
      "⛔ a release with a hole looks complete" \
      "reproduce: yq '.jobs.publish.needs' .github/workflows/release.yml"
  fi

  cond="$(r '.jobs.publish.if // ""')"
  case "$cond" in
    *"needs.guard.outputs.publish"*)
      ok "the publish job runs only when guard chose to publish"
      ;;
    *)
      fail "the publish job runs only when guard chose to publish" \
        "if: ${cond:-none}" \
        "without it a dispatch publishes a release" \
        "reproduce: yq '.jobs.publish.if' .github/workflows/release.yml"
      ;;
  esac

  writers="$(r '[.jobs | to_entries[] | select((.value.permissions // {} | if type == "object" then .contents else . end) == "write") | .key] | join(" ")')"
  if [ "$writers" = publish ]; then
    ok "publish is the one job with contents: write"
  else
    fail "publish is the one job with contents: write" \
      "jobs with contents: write: ${writers:- none}" \
      "reproduce: yq '.jobs[].permissions' .github/workflows/release.yml"
  fi

  # ⛔ The ports come from scripts/ports. A literal list goes stale.
  rmatrix="$(r '.jobs.rootfs.strategy.matrix.include // "" | tostring')"
  ports_step="$(r '[.jobs.guard.steps[] | select((.run // "") | test("scripts/ports matrix"))] | length')"
  notes_ports="$(r '[.jobs.publish.steps[] | select((.run // "") | test("scripts/ports list") and test("scripts/release-notes"))] | length')"
  literal="$(r '[.jobs | to_entries[] | select(.value.strategy.matrix != null) | select(.value.strategy.matrix | tostring | test("fromJSON") | not) | .key] | join(" ")')"
  # shellcheck disable=SC2016 # a GitHub expression, compared as text
  if [ "$rmatrix" = '${{ fromJSON(needs.guard.outputs.matrix) }}' ] && [ "$ports_step" -ge 1 ] \
    && [ "$notes_ports" -ge 1 ] && [ -z "$literal" ]; then
    ok "release.yml reads the ports from scripts/ports for the matrix and for the notes"
  else
    fail "release.yml reads the ports from scripts/ports for the matrix and for the notes" \
      "rootfs matrix: $rmatrix; guard steps with scripts/ports matrix: $ports_step;" \
      "publish steps with scripts/ports list and release-notes: $notes_ports; jobs with a literal matrix: ${literal:-none}" \
      "reproduce: yq '.jobs.rootfs.strategy, .jobs.guard.steps' .github/workflows/release.yml"
  fi

  static="$(r '[.jobs.guard.steps[] | select(.id == "static") | .run // ""] | first // ""')"
  case "$static" in
    *tests/run.sh*static*)
      ok "the guard job runs the static suite"
      ;;
    *)
      fail "the guard job runs the static suite" \
        "step id static runs: ${static:-nothing}" \
        "reproduce: yq '.jobs.guard.steps' .github/workflows/release.yml"
      ;;
  esac

  # ⭐ The step publish makes or finishes the draft, verify checks the
  # assets, and undraft publishes the draft as the last step. Section 7 runs
  # the steps.
  pos() { r "[.jobs.publish.steps | to_entries[] | select(.value.id == \"$1\") | .key] | first // -1"; }
  publish_at="$(pos publish)"
  check_at="$(pos verify)"
  undraft_at="$(pos undraft)"
  last="$(r '.jobs.publish.steps | length - 1')"
  undraft_run="$(r '[.jobs.publish.steps[] | select(.id == "undraft") | .run // ""] | first // ""')"
  if [ "$publish_at" -ge 0 ] && [ "$check_at" -gt "$publish_at" ] && [ "$undraft_at" -gt "$check_at" ] \
    && [ "$undraft_at" = "$last" ] && [[ $undraft_run == *--draft=false* ]]; then
    ok "the publish job makes the draft, checks the assets, then publishes the draft as its last step"
  else
    fail "the publish job makes the draft, checks the assets, then publishes the draft as its last step" \
      "step index: publish $publish_at, verify $check_at, undraft $undraft_at, last $last" \
      "reproduce: yq '.jobs.publish.steps[] | [.id, .run]' .github/workflows/release.yml"
  fi

  # ⛔ verify and undraft run only when publish left a draft. On a published
  # release they would compare new bytes with the old ones, or change it.
  guarded="$(r '[.jobs.publish.steps[] | select(.id == "verify" or .id == "undraft")
                 | select((.if // "") | test("steps\\.publish\\.outputs\\.state"))] | length')"
  if [ "$guarded" = 2 ]; then
    ok "the steps verify and undraft run only on the state that publish gives"
  else
    fail "the steps verify and undraft run only on the state that publish gives" \
      "steps with an if on steps.publish.outputs.state: $guarded of 2" \
      "reproduce: yq '.jobs.publish.steps[] | [.id, .if]' .github/workflows/release.yml"
  fi
fi

#---------------------------------------------------------------------------#
# 2. release-notes --next-tag: the next patch tag after the newest vX.Y.Z.
#---------------------------------------------------------------------------#
got="$(printf 'v0.1.0\nv0.2.0\nv0.1.9\nv1.0.0-rc1\nv01.2.3\nv2026.08.28\nfoo\n' | "$NOTES" --next-tag)"
none="$(printf 'foo\nv1.0\n' | "$NOTES" --next-tag)"
if [ "$got" = v0.2.1 ] && [ "$none" = v0.1.0 ]; then
  ok "release-notes --next-tag reads only vX.Y.Z tags and adds one to the patch"
else
  fail "release-notes --next-tag reads only vX.Y.Z tags and adds one to the patch" \
    "got $got (want v0.2.1), with no semver tag $none (want v0.1.0)" \
    "reproduce: printf 'v0.1.0\\nv0.2.0\\n' | scripts/release-notes --next-tag"
fi

#---------------------------------------------------------------------------#
# 3. release-notes against fixtures. Ports aa and bb: aa has every asset, bb
#    has no published image.
#---------------------------------------------------------------------------#
if need_tool jq sha256sum gzip; then
  export RELEASE_ARCHES="aa bb"
  mk_release() {
    rm -rf "$work/a" "$work/m"
    mkdir -p "$work/a" "$work/m"
    local p
    for p in aa bb; do
      printf 'binary %s\n' "$p" > "$work/a/pacman-static-$p"
      jq -n --arg p "$p" '{arch: $p, elf_machine: "Fixture Machine", size: 11,
              sha256: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
              reported_version: "Pacman v9.8.7 - libalpm v98.0.0",
              interp_segments: 0,
              pacman_commit: "abcdef1234567890abcdef1234567890abcdef12",
              pacman_describe_pinned: "9.8.7.r3.gabcdef1",
              pacman_signed_tag: "v9.8.7",
              pacman_tag_verified_by: "0123456789ABCDEF0123456789ABCDEF01234567",
              pacman_tag_signer: "Fixture Signer"}' > "$work/a/pacman-static-$p.json"
    done
    printf 'root\n' | gzip > "$work/a/rootfs-aa.tar.gz"
    printf 'oci\n' | gzip > "$work/a/oci-aa.tar.gz"
    printf '# set\nzlib 9.8.7-1 aa\n' > "$work/a/bootstrap-set-aa.txt"
    jq -n '{package_count: 1, anchor: {name: "pacman", version: "9.8.7.r3.gabcdef1-1"},
            digest: "sha256:1111111111111111111111111111111111111111111111111111111111111111"}' \
      > "$work/a/rootfs-aa.json"
    jq -n '{schema: "docker-archlinux/manifest/1", image: "ghcr.io/fixture/archlinux",
            tag_count: 4, resolved_count: 4}' > "$work/a/manifest.json"
    jq -n '{arch: "aa", evidence: "regenerated", digest: "sha256:1111111111111111111111111111111111111111111111111111111111111111"}' \
      > "$work/m/rootfs-aa.json"
    jq -n '{arch: "bb", reason: "ghcr.io/fixture/archlinux:bb does not exist"}' > "$work/m/absent-bb.json"
  }
  notes() { "$NOTES" "$work/a" v5.6.7 "$work/m" > "$work/body.md" 2> "$work/notes.err"; }

  mk_release
  rc=0
  notes || rc=$?
  if [ "$rc" -eq 0 ]; then
    ok "release-notes accepts a complete release with a port left out"
  else
    fail "release-notes accepts a complete release with a port left out" \
      "exit $rc: $(tr '\n' ';' < "$work/notes.err")" \
      "reproduce: RELEASE_ARCHES='aa bb' scripts/release-notes <assets> v5.6.7 <meta>"
  fi

  if [ "$rc" -eq 0 ]; then
    listed="$(awk '{ f = $2; sub(/^[*]/, "", f); print f }' "$work/a/SHA256SUMS" | LC_ALL=C sort | tr '\n' ' ')"
    files="$(find "$work/a" -mindepth 1 -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\n' | LC_ALL=C sort | tr '\n' ' ')"
    rc=0
    (cd "$work/a" && sha256sum -c --quiet SHA256SUMS) > "$work/sum.out" 2>&1 || rc=$?
    if [ "$listed" = "$files" ] && [ "$rc" -eq 0 ]; then
      ok "SHA256SUMS lists every asset but itself, and sha256sum -c passes"
    else
      fail "SHA256SUMS lists every asset but itself, and sha256sum -c passes" \
        "listed: $listed" "files:  $files" "sha256sum -c exit $rc" \
        "reproduce: cd <assets> && sha256sum -c SHA256SUMS"
    fi

    if awk -F'|' '$2 ~ /^ *bb *$/ { hit = 1 } END { exit hit ? 0 : 1 }' "$work/body.md" \
      && awk -F'|' '$2 ~ /^ *aa *$/ && $5 ~ /regenerated/ { hit = 1 } END { exit hit ? 0 : 1 }' "$work/body.md"; then
      ok "the body has a row for the port left out, and the evidence source of each rootfs"
    else
      fail "the body has a row for the port left out, and the evidence source of each rootfs" \
        "reproduce: RELEASE_ARCHES='aa bb' scripts/release-notes <assets> v5.6.7 <meta>"
    fi

    # ⛔ No hard coded version or date: each X.Y.Z and each date in the body
    # comes from the inputs.
    inputs="$(cat "$work"/a/*.json "$work"/m/*.json; echo v5.6.7)"
    foreign=""
    while IFS= read -r t; do
      [ -n "$t" ] || continue
      awk -v t="$t" 'index($0, t) { hit = 1 } END { exit hit ? 0 : 1 }' <<< "$inputs" || foreign="$foreign $t"
    done <<< "$(grep -oE '[0-9]{4}[-.][0-9]{2}[-.][0-9]{2}|v?[0-9]+\.[0-9]+\.[0-9]+' "$work/body.md" | LC_ALL=C sort -u)"
    if [ -z "$foreign" ]; then
      ok "the body names no version or date that its inputs do not give"
    else
      fail "the body names no version or date that its inputs do not give" \
        "not in the inputs:$foreign" \
        "a fixed version in the body goes stale at the next release" \
        "reproduce: grep -noE '[0-9]+[.][0-9]+[.][0-9]+' <body.md>"
    fi
  fi

  # Each case breaks one rule. release-notes must refuse it.
  refuse() { # refuse DESCRIPTION SHELL-CODE
    mk_release
    eval "$2"
    local rc=0
    notes || rc=$?
    if [ "$rc" -ne 0 ]; then
      ok "release-notes refuses $1"
    else
      fail "release-notes refuses $1" \
        "it exited 0 after: $2" \
        "reproduce: RELEASE_ARCHES='aa bb' scripts/release-notes <assets> v5.6.7 <meta>"
    fi
  }
  # The code runs inside refuse, so $work expands there.
  # shellcheck disable=SC2016
  {
  refuse "a rootfs with no package set and no note" 'rm "$work/a/bootstrap-set-aa.txt"'
  refuse "a port with no rootfs and no note" 'rm "$work/m/absent-bb.json"'
  refuse "rootfs assets for a port that the notes call absent" 'cp "$work/a/rootfs-aa.json" "$work/a/rootfs-bb.json"'
  refuse "an asset of a port outside RELEASE_ARCHES" 'cp "$work/a/pacman-static-aa" "$work/a/pacman-static-cc"'
  refuse "a binary with no evidence file" 'rm "$work/a/pacman-static-bb.json"'
  refuse "a binary that did not run" 'jq ".reported_version = \"NOT MEASURED\"" "$work/a/pacman-static-aa.json" > "$work/x" && mv "$work/x" "$work/a/pacman-static-aa.json"'
  refuse "a binary whose tag check was skipped" 'jq ".pacman_tag_verified_by = \"SKIPPED\"" "$work/a/pacman-static-aa.json" > "$work/x" && mv "$work/x" "$work/a/pacman-static-aa.json"'
  refuse "binaries from two pacman commits" 'jq ".pacman_commit = \"1111111111111111111111111111111111111111\"" "$work/a/pacman-static-bb.json" > "$work/x" && mv "$work/x" "$work/a/pacman-static-bb.json"'
  refuse "a release with no manifest.json" 'rm "$work/a/manifest.json"'
  }

  # ⛔ The body says that the anchor tags end in the describe value of the
  # binaries only when each image has that pacman. An image with another
  # pacman gets a ⚠ line with its port and its anchor.
  # warned BODY VERSION -> the count of ⚠ lines that name aa and VERSION
  warned() {
    awk -v v="$2" 'index($0, "⚠") == 1 && index($0, "aa") && index($0, v) { n++ } END { print n + 0 }' "$1"
  }
  # source_line BODY -> the line that names the pacman commit of the binaries
  source_line() {
    awk 'index($0, "abcdef1234567890abcdef1234567890abcdef12") && !/^[|]/ { print }' "$1"
  }
  mk_release
  rc_same=0
  notes || rc_same=$?
  same_warned="$(warned "$work/body.md" 9.8.7.r3.gabcdef1-1)"
  same_line="$(source_line "$work/body.md")"
  mk_release
  jq '.anchor.version = "9.9.0-1"' "$work/a/rootfs-aa.json" > "$work/x" && mv "$work/x" "$work/a/rootfs-aa.json"
  rc_other=0
  notes || rc_other=$?
  other_warned="$(warned "$work/body.md" 9.9.0-1)"
  other_line="$(source_line "$work/body.md")"
  if [ "$rc_same" -eq 0 ] && [ "$rc_other" -eq 0 ] && [ "$same_warned" = 0 ] && [ "$other_warned" -ge 1 ] \
    && [ -n "$same_line" ] && [ "$same_line" != "$other_line" ]; then
    ok "the body names an image whose pacman is not the describe value, and then drops the claim that they agree"
  else
    fail "the body names an image whose pacman is not the describe value, and then drops the claim that they agree" \
      "exit $rc_same and $rc_other; ⚠ lines for aa: $same_warned with the pinned anchor (want 0), $other_warned with 9.9.0-1 (want 1)" \
      "source line, same anchor:  $same_line" "source line, other anchor: $other_line" \
      "reproduce: set .anchor.version of rootfs-aa.json to 9.9.0-1; RELEASE_ARCHES='aa bb' scripts/release-notes <assets> v5.6.7 <meta>"
  fi
  unset RELEASE_ARCHES
fi

#---------------------------------------------------------------------------#
# 4. gen-bootstrap-set against a fixture.
#---------------------------------------------------------------------------#
if need_tool jq; then
  cat > "$work/ev.json" << 'EV'
{
  "image": "release:fixture",
  "platform": "linux/fixture",
  "digest": "sha256:aaaa",
  "built": "-",
  "source_commit": "cccc",
  "version_id": "-",
  "architecture": "fixture",
  "docker_architecture": "fixture",
  "anchor": { "name": "pacman", "version": "9.8.7-1" },
  "packages": [
    { "name": "zlib", "version": "1.3.1-2", "sha256": "aa" },
    { "name": "bash", "version": "5.3-1", "sha256": "-" }
  ],
  "package_count": 2
}
EV
  rc=0
  "$BSET" "$work/ev.json" "$work/set.txt" > "$work/bset.out" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    lines="$(awk '!/^#/ && NF { n++ } END { print n + 0 }' "$work/set.txt")"
    unhashed="$(awk '/^# without a sha256/ { print $NF }' "$work/set.txt")"
    header="$(awk '/^# packages / { print $3 }' "$work/set.txt")"
    if [ "$lines" = 2 ] && [ "$unhashed" = 1 ] && [ "$header" = 2 ]; then
      ok "gen-bootstrap-set writes one line per package and counts the lines with no sha256"
    else
      fail "gen-bootstrap-set writes one line per package and counts the lines with no sha256" \
        "lines $lines (want 2), without a sha256 $unhashed (want 1), header $header (want 2)" \
        "reproduce: scripts/gen-bootstrap-set <evidence.json> /tmp/set.txt"
    fi
    rc=0
    awk '!/^#/ && NF { print $1 }' "$work/set.txt" | LC_ALL=C sort -c > "$work/sort.out" 2>&1 || rc=$?
    if [ "$rc" -eq 0 ]; then
      ok "gen-bootstrap-set sorts by package name"
    else
      fail "gen-bootstrap-set sorts by package name" "$(cat "$work/sort.out")" \
        "reproduce: awk '!/^#/ && NF { print \$1 }' /tmp/set.txt | LC_ALL=C sort -c"
    fi
  else
    fail "gen-bootstrap-set writes a package set from an evidence file" \
      "exit $rc: $(tr '\n' ';' < "$work/bset.out")" \
      "reproduce: scripts/gen-bootstrap-set <evidence.json> /tmp/set.txt"
  fi

  jq '.package_count = 0 | .packages = []' "$work/ev.json" > "$work/empty.json"
  rc=0
  "$BSET" "$work/empty.json" "$work/empty.txt" > "$work/bset.out" 2>&1 || rc=$?
  if [ "$rc" -ne 0 ]; then
    ok "gen-bootstrap-set refuses an evidence file with no packages"
  else
    fail "gen-bootstrap-set refuses an evidence file with no packages" \
      "it exited 0" \
      "reproduce: jq '.package_count = 0 | .packages = []' ev.json > e.json; scripts/gen-bootstrap-set e.json /tmp/o"
  fi
fi

#---------------------------------------------------------------------------#
# 5. gen-manifest against a tag list: each per-port tag shape gets its port,
#    only the anchor shape gets an anchor, the index tags get no port.
#---------------------------------------------------------------------------#
# The tag list and the expected result are in tests/fixtures/96-release-assets.
if need_tool jq; then
  FIX="$(fixture_dir)"
  # expect_of KIND -> the expected tags of KIND (port, anchor or index)
  expect_of() {
    awk -F'\t' -v k="$1" '$1 == k { print $2 }' "$FIX/manifest-expect.txt"
  }
  want_port="$(expect_of port)"
  want_anchor="$(expect_of anchor)"
  want_index="$(expect_of index)"
  rc=0
  MANIFEST_TAGS_FILE="$FIX/manifest-tags.txt" "$MANIFEST" ghcr.io/x/y "$work/m.json" > "$work/man.out" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    got="$(jq -r '[.tags[] | select(.docker_architecture != null) | .tag] | sort | join(" ")' "$work/m.json")"
    anchors="$(jq -r '[.tags[] | select(.anchor != null) | .tag] | sort | join(" ")' "$work/m.json")"
    index="$(jq -r '[.tags[] | select(.docker_architecture == null) | .tag] | sort | join(" ")' "$work/m.json")"
    if [ -n "$want_port" ] && [ "$got" = "$want_port" ] \
      && [ "$anchors" = "$want_anchor" ] && [ "$index" = "$want_index" ]; then
      ok "gen-manifest gives each tag shape its port and its anchor"
    else
      fail "gen-manifest gives each tag shape its port and its anchor" \
        "per port: '$got', want '$want_port'" "anchors: '$anchors', want '$want_anchor'" \
        "index: '$index', want '$want_index'" \
        "reproduce: MANIFEST_TAGS_FILE=tests/fixtures/96-release-assets/manifest-tags.txt scripts/gen-manifest ghcr.io/x/y /tmp/m.json"
    fi
  else
    fail "gen-manifest runs against a tag list" \
      "exit $rc: $(tr '\n' ';' < "$work/man.out")" \
      "reproduce: MANIFEST_TAGS_FILE=tests/fixtures/96-release-assets/manifest-tags.txt scripts/gen-manifest ghcr.io/x/y /tmp/m.json"
  fi
fi

#---------------------------------------------------------------------------#
# 6. ⛔ Each step that calls scripts/gen-evidence sets CONTAINER_RUNTIME. The
#    runner has docker and podman, gen-evidence picks podman, and the image is
#    in the docker store.
#---------------------------------------------------------------------------#
if need_tool yq jq; then
  calls=0
  unset_runtime=""
  for wf in "$WF_DIR"/*.yml; do
    j="$work/wf/$(basename "$wf" .yml).json"
    [ -f "$j" ] || continue
    # A call is a run line that is not a comment and not a printf.
    while IFS=$'\t' read -r job idx has; do
      [ -n "$job" ] || continue
      calls=$((calls + 1))
      [ "$has" = true ] || unset_runtime="$unset_runtime $(basename "$wf"):$job/steps[$idx]"
    done <<< "$(jq -r '
      (.env // {}) as $wenv
      | .jobs | to_entries[] | .key as $job | (.value.env // {}) as $jenv
      | (.value.steps // []) | to_entries[]
      | select((.value.run // "") | split("\n")
               | map(select(test("^\\s*#") | not) | select(test("printf") | not))
               | any(test("scripts/gen-evidence")))
      | [$job, (.key | tostring),
         (($wenv.CONTAINER_RUNTIME // $jenv.CONTAINER_RUNTIME // .value.env.CONTAINER_RUNTIME // null) != null
          or ((.value.run // "") | test("CONTAINER_RUNTIME=")) | tostring)]
      | @tsv' "$j")"
  done
  if [ "$calls" -eq 0 ]; then
    fail "at least one workflow step calls scripts/gen-evidence" \
      "the scan found none, so it checked nothing" \
      "reproduce: grep -n scripts/gen-evidence .github/workflows/*.yml"
  elif [ -z "$unset_runtime" ]; then
    ok "all $calls workflow steps that call gen-evidence set CONTAINER_RUNTIME"
  else
    fail "all $calls workflow steps that call gen-evidence set CONTAINER_RUNTIME" \
      "without it:$unset_runtime" \
      "reproduce: yq '.jobs[].steps[] | select(.run // \"\" | test(\"gen-evidence\"))' .github/workflows/*.yml"
  fi
fi

# step_run JOB ID -> the run script of the step ID of JOB in release.yml
step_run() {
  jq -r --arg j "$1" --arg i "$2" '[.jobs[$j].steps[] | select(.id == $i) | .run // ""] | first // ""' "$work/wf/release.json"
}

#---------------------------------------------------------------------------#
# 7. ⭐ The steps publish and verify of release.yml, run against a stand-in
#    gh. A published release is never changed. A draft at another commit is
#    deleted and made again. A draft at this commit is finished, and an asset
#    that this run did not make goes.
#---------------------------------------------------------------------------#
if need_tool yq jq timeout && [ -f "$work/wf/release.json" ]; then
  pub="$work/pub"
  mkdir -p "$pub/bin"
  step_run publish publish > "$pub/publish.sh"
  step_run publish verify > "$pub/verify.sh"
  # The release is the directory GHS: GHS/release.json has isDraft and
  # targetCommitish, GHS/assets has one file per asset. Each call is a line
  # in GHS/calls.
  cat > "$pub/bin/gh" << 'GH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$GHS/calls"
[ "${1:-}" = release ] && [ "$#" -ge 3 ] || { echo "stand-in gh: unexpected call: $*" >&2; exit 2; }
sub="$2"
shift 3
json="" jqf="" target="" notes="" undraft=0 args=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo | --title) shift 2 ;;
    --json) json="$2"; shift 2 ;;
    --jq) jqf="$2"; shift 2 ;;
    --target) target="$2"; shift 2 ;;
    --notes-file) notes="$2"; shift 2 ;;
    --draft=false) undraft=1; shift ;;
    --draft | --clobber | --yes) shift ;;
    -*) echo "stand-in gh: unexpected option $1" >&2; exit 2 ;;
    *) args+=("$1"); shift ;;
  esac
done
rel="$GHS/release.json"
if [ "$sub" != create ] && [ ! -f "$rel" ]; then
  echo "release not found" >&2
  exit 1
fi
case "$sub" in
  view)
    assets="$(find "$GHS/assets" -mindepth 1 -maxdepth 1 -type f -printf '%f %s\n' | LC_ALL=C sort \
      | jq -Rn '[inputs | split(" ") | {name: .[0], size: (.[1] | tonumber)}]')"
    out="$(jq -c --argjson a "$assets" --arg f "$json" \
      '. + {assets: $a} | with_entries(select(.key as $k | $f | split(",") | index($k)))' "$rel")"
    if [ -n "$jqf" ]; then jq -r "$jqf" <<< "$out"; else printf '%s\n' "$out"; fi
    ;;
  create)
    [ ! -f "$rel" ] || { echo "stand-in gh: the release exists" >&2; exit 1; }
    mkdir -p "$GHS/assets"
    jq -n --arg t "$target" '{isDraft: true, targetCommitish: $t}' > "$rel"
    ;;
  upload) cp -- "${args[@]}" "$GHS/assets/" ;;
  edit)
    if [ "$undraft" -eq 1 ]; then jq '.isDraft = false' "$rel" > "$rel.new" && mv "$rel.new" "$rel"; fi
    [ -z "$notes" ] || cp -- "$notes" "$GHS/notes.md"
    ;;
  delete) rm -rf "$rel" "$GHS/assets" ;;
  delete-asset) rm -- "$GHS/assets/${args[0]}" ;;
  *) echo "stand-in gh: unexpected call: release $sub" >&2; exit 2 ;;
esac
GH
  chmod +x "$pub/bin/gh"
  OLD=1111111111111111111111111111111111111111
  NEW=2222222222222222222222222222222222222222

  # world STATE TARGET [ASSET...]: this run has manifest.json and SHA256SUMS.
  # STATE none has no release; draft and published have one at TARGET, with
  # an old file for each ASSET.
  world() {
    rm -rf "$pub/gh" "$pub/run"
    mkdir -p "$pub/gh" "$pub/run/assets"
    printf 'new manifest\n' > "$pub/run/assets/manifest.json"
    printf 'new sums\n' > "$pub/run/assets/SHA256SUMS"
    printf '## v5.6.7\n' > "$pub/run/body.md"
    local state="$1" target="$2" a
    shift 2
    [ "$state" != none ] || return 0
    mkdir -p "$pub/gh/assets"
    jq -n --argjson d "$([ "$state" = draft ] && echo true || echo false)" --arg t "$target" \
      '{isDraft: $d, targetCommitish: $t}' > "$pub/gh/release.json"
    for a in "$@"; do printf 'old %s\n' "$a" > "$pub/gh/assets/$a"; done
  }
  # run_step NAME -> the exit code. The step output is in $pub/out.
  run_step() {
    local rc=0
    : > "$pub/out"
    : > "$pub/gh/calls"
    (
      cd "$pub/run" &&
        env PATH="$pub/bin:$PATH" GHS="$pub/gh" TAG=v5.6.7 TARGET="$NEW" GH_TOKEN=fixture \
          GITHUB_REPOSITORY=fixture/archlinux GITHUB_OUTPUT="$pub/out" \
          bash --noprofile --norc -eo pipefail "$pub/$1.sh"
    ) > "$pub/log" 2>&1 || rc=$?
    printf '%s\n' "$rc"
  }
  # facts -> "EXIT STATE DRAFT TARGET ASSETS" after a run of the step publish
  facts() {
    local rc state rel assets
    rc="$(run_step publish)"
    state="$(awk -F= '$1 == "state" { s = $2 } END { print s }' "$pub/out")"
    rel="$(jq -r '"\(.isDraft) \(.targetCommitish)"' "$pub/gh/release.json")"
    assets="$(find "$pub/gh/assets" -mindepth 1 -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort | tr '\n' ' ')"
    printf '%s %s %s %s\n' "$rc" "${state:--}" "$rel" "${assets% }"
  }
  # called VERB -> the count of gh release VERB calls
  called() { awk -v v="release $1" 'index($0, v " ") == 1 { n++ } END { print n + 0 }' "$pub/gh/calls"; }
  # same -> yes when each remote asset has the bytes of this run
  same() {
    local f
    for f in "$pub"/run/assets/*; do
      cmp -s "$f" "$pub/gh/assets/$(basename "$f")" || { echo no; return 0; }
    done
    echo yes
  }
  prepro="bash tests/static/96-release-assets.sh; the stand-in gh is made in the test"

  world none -
  check_eq "with no release, publish makes a draft at the commit of the run with the assets of the run" \
    "0 draft true $NEW SHA256SUMS manifest.json yes" "$(facts) $(same)" "$prepro"

  world published "$OLD" manifest.json SHA256SUMS
  got="$(facts)"
  writes="$(( $(called upload) + $(called edit) + $(called create) + $(called delete) + $(called delete-asset) ))"
  check_eq "⛔ a published release is not changed: no upload, no edit, no delete, and the state published" \
    "0 published false $OLD SHA256SUMS manifest.json no 0" "$got $(same) $writes" "$prepro"

  world draft "$OLD" manifest.json rootfs-cc.tar.gz
  got="$(facts)"
  check_eq "a draft at another commit is deleted and made again at the commit of the run, with no old asset" \
    "0 draft true $NEW SHA256SUMS manifest.json yes 1" "$got $(same) $(called delete)" "$prepro"

  world draft "$NEW" manifest.json extra.txt
  got="$(facts)"
  check_eq "a draft at the commit of the run is finished: the extra asset goes, the draft stays" \
    "0 draft true $NEW SHA256SUMS manifest.json yes 0 1" "$got $(same) $(called delete) $(called delete-asset)" "$prepro"

  # verify: the draft has the assets of the run, and no other.
  world draft "$NEW"
  cp "$pub"/run/assets/* "$pub/gh/assets/"
  check_eq "verify passes a draft with each asset of the run and no other" "0" "$(run_step verify)" "$prepro"
  printf 'old\n' > "$pub/gh/assets/extra.txt"
  rc="$(run_step verify)"
  if [ "$rc" -ne 0 ]; then
    ok "verify refuses a draft with an asset that the run did not make (exit $rc)"
  else
    fail "verify refuses a draft with an asset that the run did not make" \
      "it exited 0; SHA256SUMS does not cover extra.txt" "reproduce: $prepro"
  fi
fi

#---------------------------------------------------------------------------#
# 8. ⛔ The step evidence of release.yml, with no evidence on the status
#    branch: gen-evidence makes the file again, and its source_commit and
#    built are the labels of the image, not the commit and the time of the
#    release run. Stand-in git, docker and a file:// mirror: no network.
#---------------------------------------------------------------------------#
if need_tool yq jq curl tar gzip && [ -f "$work/wf/release.json" ]; then
  ev="$work/ev"
  mkdir -p "$ev/repo/scripts" "$ev/repo/rootfs/zz/etc/pacman.d" "$ev/repo/assets" "$ev/repo/meta" \
    "$ev/bin" "$ev/desc/pacman-9.8.7-1" "$ev/mirror/core/os/x86_64"
  cp "$REPO_ROOT/scripts/gen-evidence" "$ev/repo/scripts/"
  step_run rootfs evidence > "$ev/evidence.sh"
  printf '[options]\nArchitecture = x86_64\n\n[core]\nInclude = /etc/pacman.d/mirrorlist\n' \
    > "$ev/repo/rootfs/zz/etc/pacman.conf"
  # shellcheck disable=SC2016 # $repo and $arch are for gen-evidence, written literally
  printf 'Server = file://%s/mirror/$repo/os/$arch\n' "$ev" > "$ev/repo/rootfs/zz/etc/pacman.d/mirrorlist"
  printf '%%FILENAME%%\npacman-9.8.7-1-x86_64.pkg.tar.zst\n\n%%NAME%%\npacman\n\n%%VERSION%%\n9.8.7-1\n\n%%CSIZE%%\n1000\n\n%%ISIZE%%\n4000\n\n%%SHA256SUM%%\n%064d\n\n%%BUILDDATE%%\n1760000000\n\n' 7 \
    > "$ev/desc/pacman-9.8.7-1/desc"
  tar -czf "$ev/mirror/core/os/x86_64/core.db" -C "$ev/desc" pacman-9.8.7-1
  cat > "$ev/bin/docker" << 'RT'
#!/usr/bin/env bash
case "$*" in
  *'/var/lib/pacman/local/'*) printf '%%NAME%%\npacman\n\n%%VERSION%%\n9.8.7-1\n\n%%%%END%%%%\n' ;;
  *'/etc/os-release'*) printf '2030.01.02\n' ;;
  'image inspect '*'.Config.Labels'*) cat "$FAKE_LABELS" ;;
  *) echo "stand-in docker: unexpected call: $*" >&2; exit 2 ;;
esac
RT
  printf '#!/bin/sh\necho "stand-in git: no network here" >&2\nexit 128\n' > "$ev/bin/git"
  chmod +x "$ev/bin/docker" "$ev/bin/git"
  REV=1a2b1da778e1f26a5e92f92974e322e25c90ac02
  CREATED=2030-01-01T09:11:41Z
  RUN_SHA=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
  # regenerate LABELS-JSON -> "EXIT EVIDENCE SOURCE_COMMIT BUILT"
  # SOURCE_COMMIT and BUILD_DATE of the release run are in the environment:
  # the step must not pass them on.
  regenerate() {
    local rc=0
    printf '%s\n' "$1" > "$ev/labels.json"
    rm -f "$ev/repo/assets/rootfs-zz.json" "$ev/repo/meta/rootfs-zz.json"
    (
      cd "$ev/repo" &&
        env PATH="$ev/bin:$PATH" FAKE_LABELS="$ev/labels.json" ARCH=zz PLATFORM=linux/amd64 \
          IMAGE="ghcr.io/fixture/archlinux@sha256:$(printf '%064d' 1)" DIGEST="sha256:$(printf '%064d' 1)" \
          CONTAINER_RUNTIME=docker GITHUB_SHA="$RUN_SHA" SOURCE_COMMIT="$RUN_SHA" BUILD_DATE=2031-02-03T04:05:06Z \
          bash --noprofile --norc -eo pipefail "$ev/evidence.sh"
    ) > "$ev/log" 2>&1 || rc=$?
    if [ -f "$ev/repo/assets/rootfs-zz.json" ] && [ -f "$ev/repo/meta/rootfs-zz.json" ]; then
      printf '%s %s %s\n' "$rc" "$(jq -r .evidence "$ev/repo/meta/rootfs-zz.json")" \
        "$(jq -r '.source_commit + " " + .built' "$ev/repo/assets/rootfs-zz.json")"
    else
      printf '%s - - - %s\n' "$rc" "$(tr -d '\r' < "$ev/log" | awk 'NF { last = $0 } END { print last }')"
    fi
  }
  erepro="bash tests/static/96-release-assets.sh; yq '.jobs.rootfs.steps[] | select(.id == \"evidence\")' .github/workflows/release.yml"
  check_eq "regenerated release evidence has the revision and created labels of the image, not the release run" \
    "0 regenerated $REV $CREATED" \
    "$(regenerate "$(jq -cn --arg r "$REV" --arg c "$CREATED" '{"org.opencontainers.image.revision": $r, "org.opencontainers.image.created": $c}')")" \
    "$erepro"
  check_eq "regenerated release evidence of an image with no labels says unknown" \
    "0 regenerated unknown unknown" "$(regenerate '{}')" "$erepro"
fi

#---------------------------------------------------------------------------#
# 9. ⭐ The job report of release.yml: one failed scheduled run raises
#    failing-release, a scheduled run that succeeds clears it. The step runs
#    against a stand-in scripts/track-issue.
#---------------------------------------------------------------------------#
if need_tool yq jq && [ -f "$work/wf/release.json" ]; then
  R="$work/wf/release.json"
  rrepro="yq '.jobs.report' .github/workflows/release.yml"
  others="$(jq -r '[.jobs | keys[] | select(. != "report")] | sort | join(" ")' "$R")"
  check_eq "report needs every other job of release.yml" "$others" \
    "$(jq -r '[.jobs.report.needs // [] | if type == "string" then [.] else . end | .[]] | sort | join(" ")' "$R")" "$rrepro"
  check_eq "report runs after a failure, and only for a scheduled run" "yes" \
    "$(jq -r '(.jobs.report.if // "" | tostring) as $c
      | if ($c | test("always\\(\\)")) and ($c | test("github[.]event_name *== *.schedule.")) then "yes" else $c end' "$R")" "$rrepro"
  check_eq "report has contents read and issues write, nothing more" '{"contents":"read","issues":"write"}' \
    "$(jq -cS '.jobs.report.permissions // {}' "$R")" "$rrepro"

  rep="$work/report"
  mkdir -p "$rep/tree/scripts"
  step_run report report > "$rep/report.sh"
  cat > "$rep/tree/scripts/track-issue" << 'TI'
#!/usr/bin/env bash
set -euo pipefail
printf '%s %s\n' "$1" "$2" >> "$CALLS"
if [ "$1" = raise ]; then cp -- "$4" "$CALLS.body"; fi
TI
  chmod +x "$rep/tree/scripts/track-issue"
  # report_case NEEDS_JSON -> "<exit> <calls>", and the body has the run URL
  report_case() {
    local rc=0 calls
    rm -f "$rep/calls" "$rep/calls.body"
    mkdir -p "$rep/tmp"
    (
      cd "$rep/tree" &&
        env CALLS="$rep/calls" NEEDS="$1" RUNNER_TEMP="$rep/tmp" \
          RUN_URL="https://github.com/o/r/actions/runs/77" \
          bash --noprofile --norc -eo pipefail "$rep/report.sh"
    ) > "$rep/log" 2>&1 || rc=$?
    calls=""
    [ ! -f "$rep/calls" ] || calls="$(tr '\n' ',' < "$rep/calls" | tr -d '\r')"
    if [ -f "$rep/calls.body" ] && grep -q 'actions/runs/77' "$rep/calls.body"; then
      calls="$calls body"
    fi
    printf '%s %s\n' "$rc" "${calls:-none}"
  }
  needs_of() {
    jq -cn --arg g "$1" --arg p "$2" --arg r "$3" --arg m "$4" --arg u "$5" \
      '{guard: {result: $g}, pacman: {result: $p}, rootfs: {result: $r}, manifest: {result: $m}, publish: {result: $u}}'
  }
  check_eq "report: every job passed clears failing-release" "0 clear failing-release," \
    "$(report_case "$(needs_of success success success success success)")" "$rrepro"
  check_eq "report: a publish that guard skipped clears failing-release" "0 clear failing-release," \
    "$(report_case "$(needs_of success success success success skipped)")" "$rrepro"
  check_eq "report: one failed job raises failing-release, with the run in the body" "0 raise failing-release, body" \
    "$(report_case "$(needs_of success success failure success skipped)")" "$rrepro"
  check_eq "report: a cancelled job raises failing-release" "0 raise failing-release, body" \
    "$(report_case "$(needs_of success cancelled success success skipped)")" "$rrepro"
fi

summary
