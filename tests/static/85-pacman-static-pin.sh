#!/usr/bin/env bash
#
# The static pacman pin and its build.
#
#   - Each input of bootstrap/pacman-static/sources.pin is pinned by content.
#   - Each mirror line names a record and the same file.
#   - The vendored signer keys have the fingerprints of the signer lines.
#   - scripts/build-pacman-static takes every target fact from scripts/ports
#     and carries no table of architectures.
#   - --check-evidence refuses an unverified tag, a binary that did not run,
#     and a dynamic binary.
#   - .github/workflows/pacman-static.yml reads its matrix from scripts/ports.
#   - The image build does not read the pin.
#   - A reused WORK gives the zig of the current pin, and --zig gives the
#     version that the zig binary reports.
#
# No network. The freshness workflow compares the pin with upstream.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

PIN="$REPO_ROOT/bootstrap/pacman-static/sources.pin"
KEYS="$REPO_ROOT/bootstrap/pacman-static/keys"
BUILD="$REPO_ROOT/scripts/build-pacman-static"
PORTS="$REPO_ROOT/scripts/ports"
WF="$REPO_ROOT/.github/workflows/pacman-static.yml"

for f in "$PIN" "$BUILD" "$PORTS" "$WF"; do
  if [ ! -f "$f" ]; then
    fail "${f#"$REPO_ROOT/"} exists" "reproduce: ls -l ${f#"$REPO_ROOT/"}"
    summary
    exit 1
  fi
done

work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

#---------------------------------------------------------------------------#
# 1. Each source record has a name, a version, an https URL and a sha256.
#---------------------------------------------------------------------------#
bad="$(awk '
  $1 == "source" {
    n++
    if (NF != 5) { print $2 " has " NF " fields, expected 5"; next }
    if ($4 !~ /^https:\/\//) print $2 " URL is not https"
    if ($5 !~ /^[0-9a-f]{64}$/) print $2 " sha256 is not 64 hex digits"
    if (seen[$2]++) print $2 " has two source records"
  }
  END { if (n == 0) print "no source record" }
' "$PIN")"
if [ -z "$bad" ]; then
  ok "each source record has an https URL and a sha256"
else
  fail "each source record has an https URL and a sha256" \
    "$(printf '%s' "$bad" | tr '\n' '|')" \
    "reproduce: awk '\$1 == \"source\"' bootstrap/pacman-static/sources.pin"
fi

#---------------------------------------------------------------------------#
# 2. zig is pinned by sha256, and for x86_64-linux: the host of the runner.
#---------------------------------------------------------------------------#
bad="$(awk '
  $1 == "zig" {
    if (NF != 5) { print $3 " has " NF " fields, expected 5"; next }
    if ($4 !~ /^https:\/\//) print $3 " URL is not https"
    if ($5 !~ /^[0-9a-f]{64}$/) print $3 " sha256 is not 64 hex digits"
    host[$3] = 1
  }
  END { if (!("x86_64-linux" in host)) print "no zig record for x86_64-linux" }
' "$PIN")"
if [ -z "$bad" ]; then
  ok "zig is pinned by sha256, with a record for the x86_64-linux runner"
else
  fail "zig is pinned by sha256, with a record for the x86_64-linux runner" \
    "$(printf '%s' "$bad" | tr '\n' '|')" \
    "reproduce: awk '\$1 == \"zig\"' bootstrap/pacman-static/sources.pin"
fi

#---------------------------------------------------------------------------#
# 3. Each mirror line is `mirror = NAME URL`. NAME is a source record or
#    zig-HOST. The URL is https, another URL than the record's, and ends in
#    the same file name. ⭐ The sha256 of the record decides, so a mirror line
#    can add a host and never other bytes.
#---------------------------------------------------------------------------#
bad="$(awk '
  function base(u) { sub(/[?#].*$/, "", u); sub(/^.*\//, "", u); return u }
  $1 == "source" { url[$2] = $4 }
  $1 == "zig" { url["zig-" $3] = $4 }
  $1 == "mirror" {
    n++
    line[n] = $0; nf[n] = NF; eq[n] = $2; name[n] = $3; murl[n] = $4
  }
  END {
    for (i = 1; i <= n; i++) {
      if (nf[i] != 4 || eq[i] != "=") { print "not mirror = NAME URL: " line[i]; continue }
      if (!(name[i] in url)) { print "no record named " name[i] ": " line[i]; continue }
      if (murl[i] !~ /^https:\/\//) print "not https: " line[i]
      if (murl[i] == url[name[i]]) print "the URL of the record again: " line[i]
      if (base(murl[i]) != base(url[name[i]])) print "another file name than " base(url[name[i]]) ": " line[i]
      if (dup[murl[i]]++) print "twice: " line[i]
    }
    if (n == 0) print "no mirror line"
  }
' "$PIN")"
if [ -z "$bad" ]; then
  ok "$(awk '$1 == "mirror" { n++ } END { print n + 0 }' "$PIN") mirror lines, each for a record and the same file name"
else
  fail "each mirror line names a record and the same file name" \
    "$(printf '%s' "$bad" | tr '\n' '|')" \
    "reproduce: awk '\$1 == \"mirror\"' bootstrap/pacman-static/sources.pin"
fi

#---------------------------------------------------------------------------#
# 4. pacman is pinned by a full commit, and describe ends in its start.
#---------------------------------------------------------------------------#
commit="$(awk '$1 == "pacman" && !done { print $2; done = 1 }' "$PIN")"
purl="$(awk '$1 == "pacman" && !done { print $3; done = 1 }' "$PIN")"
if [[ "$commit" =~ ^[0-9a-f]{40}$ ]] && [[ "$purl" == https://* ]]; then
  ok "pacman is pinned at a 40 digit commit from an https URL"
else
  fail "pacman is pinned at a 40 digit commit from an https URL" \
    "commit: ${commit:-none}, URL: ${purl:-none}" \
    "reproduce: awk '\$1 == \"pacman\"' bootstrap/pacman-static/sources.pin"
fi

describe="$(awk '$1 == "describe" && !done { print $2; done = 1 }' "$PIN")"
abbrev="$(printf '%s' "$describe" | awk -F'.g' 'NF > 1 { print $NF }')"
if [ -n "$abbrev" ] && [ "${commit:0:${#abbrev}}" = "$abbrev" ]; then
  ok "describe $describe names the pinned commit"
else
  fail "describe names the pinned commit" \
    "describe: ${describe:-none}, commit: ${commit:-none}" \
    "⛔ the anchor tags of the images end in describe, so the two must agree" \
    "reproduce: awk '\$1 == \"pacman\" || \$1 == \"describe\"' bootstrap/pacman-static/sources.pin"
fi

#---------------------------------------------------------------------------#
# 5. The signed tag, the signers and the keyservers.
#---------------------------------------------------------------------------#
tag_line="$(awk '$1 == "tag" { n++; l = $0 } END { if (n == 1) print l }' "$PIN")"
if printf '%s\n' "$tag_line" | awk 'NF == 3 && $3 ~ /^[0-9a-f]{40}$/ { hit = 1 } END { exit hit ? 0 : 1 }'; then
  ok "one tag line names the tag and its 40 digit object sha"
else
  fail "one tag line names the tag and its 40 digit object sha" \
    "got: ${tag_line:-none, or more than one}" \
    "reproduce: awk '\$1 == \"tag\"' bootstrap/pacman-static/sources.pin"
fi

bad="$(awk '
  $1 == "signer" {
    n++
    if ($2 !~ /^[0-9A-F]{40}$/) print "not 40 upper case hex digits: " $2
    if (seen[$2]++) print "twice: " $2
  }
  END { if (n == 0) print "no signer line" }
' "$PIN")"
if [ -z "$bad" ]; then
  ok "each signer line is a 40 digit fingerprint"
else
  fail "each signer line is a 40 digit fingerprint" \
    "$(printf '%s' "$bad" | tr '\n' '|')" \
    "reproduce: awk '\$1 == \"signer\"' bootstrap/pacman-static/sources.pin"
fi

ks="$(awk '$1 == "keyserver" && $2 ~ /^hkps:\/\// { n++ } END { print n + 0 }' "$PIN")"
ks_all="$(awk '$1 == "keyserver" { n++ } END { print n + 0 }' "$PIN")"
if [ "$ks" -ge 2 ] && [ "$ks" = "$ks_all" ]; then
  ok "$ks hkps keyservers"
else
  fail "at least two keyservers, all hkps" \
    "hkps: $ks, all: $ks_all" \
    "reproduce: awk '\$1 == \"keyserver\"' bootstrap/pacman-static/sources.pin"
fi

#---------------------------------------------------------------------------#
# 6. keys/<FINGERPRINT>.asc holds the key of each signer line, and nothing
#    else is in keys/. The build imports these files first.
#---------------------------------------------------------------------------#
if need_tool gpg; then
  export GNUPGHOME="$work/gnupg"
  mkdir -p "$GNUPGHOME"
  chmod 700 "$GNUPGHOME"
  bad=""
  signers="$(awk '$1 == "signer" { print $2 }' "$PIN")"
  while IFS= read -r fp; do
    [ -n "$fp" ] || continue
    f="$KEYS/$fp.asc"
    if [ ! -f "$f" ]; then
      bad="$bad|no file keys/$fp.asc"
      continue
    fi
    rc=0
    shown="$(gpg --batch --with-colons --show-keys "$f" 2>&1)" || rc=$?
    if [ "$rc" -ne 0 ]; then
      bad="$bad|gpg --show-keys keys/$fp.asc exited $rc"
      continue
    fi
    primaries="$(printf '%s\n' "$shown" | awk -F: '
      $1 == "pub" { want = 1; next }
      want && $1 == "fpr" { printf "%s ", $10; want = 0 }')"
    [ "$primaries" = "$fp " ] || bad="$bad|keys/$fp.asc holds the primary keys: ${primaries:-none}"
  done <<< "$signers"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in
      *.asc) printf '%s\n' "$signers" | awk -v s="${f%.asc}" '$0 == s { hit = 1 } END { exit hit ? 0 : 1 }' \
        || bad="$bad|keys/$f is the key of no signer line" ;;
      *) bad="$bad|keys/$f is not a key file" ;;
    esac
  done <<< "$(find "$KEYS" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort)"
  if [ -z "$bad" ]; then
    ok "keys/ holds one key file per signer line, with that fingerprint"
  else
    fail "keys/ holds one key file per signer line, with that fingerprint" \
      "$(printf '%s' "${bad#|}" | tr '|' ';')" \
      "reproduce: gpg --show-keys --with-colons bootstrap/pacman-static/keys/<FINGERPRINT>.asc"
  fi
fi

#---------------------------------------------------------------------------#
# 7. ⛔ The target facts come from scripts/ports. --describe reads a fixture
#    port table, so the script cannot hold the values itself.
#---------------------------------------------------------------------------#
mkdir -p "$work/ports"
cat > "$work/ports/zz9.conf" << 'CONF'
arch = zz9
platform = linux/zz9
pacman_arch = zz9pacman
aliases = zz9 zz9alias
distribution = Fixture
homepage = https://example.invalid
repos = core
keyring = none
binfmt = native
qemu = qemu-zz9emu
zig_triple = zz9-linux-fixture
host_triplet = zz9-unknown-linux-fixture
openssl_target = linux-zz9fixture
elf_machine = Fixture Machine 9
meson_cpu_family = zz9family
endian = big
CONF
want="arch=zz9
zig_triple=zz9-linux-fixture
host_triplet=zz9-unknown-linux-fixture
openssl_target=linux-zz9fixture
elf_machine=Fixture Machine 9
emulator=qemu-zz9emu-static
pacman_arch=zz9pacman
meson_cpu_family=zz9family
endian=big"
rc=0
got="$(PORTS_DIR="$work/ports" "$BUILD" --describe zz9 2>&1)" || rc=$?
if [ "$rc" -eq 0 ] && [ "$got" = "$want" ]; then
  ok "build-pacman-static --describe reads each target fact from the port table"
else
  fail "build-pacman-static --describe reads each target fact from the port table" \
    "exit $rc, got: $(printf '%s' "$got" | tr '\n' ';')" \
    "want: $(printf '%s' "$want" | tr '\n' ';')" \
    "reproduce: PORTS_DIR=<dir with zz9.conf> scripts/build-pacman-static --describe zz9"
fi

rc=0
PORTS_DIR="$work/ports" "$BUILD" --describe zz8 > "$work/describe.out" 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then
  ok "build-pacman-static refuses a port that the port table does not have"
else
  fail "build-pacman-static refuses a port that the port table does not have" \
    "exit 0 for zz8: $(tr '\n' ';' < "$work/describe.out")" \
    "reproduce: PORTS_DIR=<dir with zz9.conf> scripts/build-pacman-static --describe zz8"
fi

# No fact of the real port table is written in the script: no case label for
# a port, and no zig triple, host triplet or OpenSSL target.
copies=""
for a in $("$PORTS" list); do
  awk -v a="$a" '{ l = $0; sub(/#.*/, "", l) } l ~ "^[[:space:]]*" a "[[:space:]]*\\)" { hit = 1 } END { exit hit ? 0 : 1 }' "$BUILD" \
    && copies="$copies case label $a;"
  for k in zig_triple host_triplet openssl_target; do
    v="$("$PORTS" get "$a" "$k")"
    awk -v v="$v" 'index($0, v) { hit = 1 } END { exit hit ? 0 : 1 }' "$BUILD" \
      && copies="$copies $k $v;"
  done
done
if [ -z "$copies" ]; then
  ok "build-pacman-static writes no fact of ports/*.conf itself"
else
  fail "build-pacman-static writes no fact of ports/*.conf itself" \
    "found:$copies" \
    "⛔ a second copy of the port table goes stale when a port changes" \
    "reproduce: grep -n -e ')' scripts/build-pacman-static"
fi

#---------------------------------------------------------------------------#
# 8. One build function per source record, and no function for a record that
#    is not there. The script builds the records in pin order.
#---------------------------------------------------------------------------#
records="$(awk '$1 == "source" { n = $2; gsub(/-/, "_", n); print "build_" n }' "$PIN" | LC_ALL=C sort)"
functions="$(awk 'match($0, /^build_[a-z0-9_]+\(\)/) { f = substr($0, 1, RLENGTH - 2); if (f != "build_pacman") print f }' "$BUILD" | LC_ALL=C sort)"
if [ -n "$records" ] && [ "$records" = "$functions" ]; then
  ok "one build function for each of the $(awk 'NF { n++ } END { print n + 0 }' <<< "$records") source records"
else
  fail "one build function for each source record" \
    "records:   $(printf '%s' "$records" | tr '\n' ' ')" \
    "functions: $(printf '%s' "$functions" | tr '\n' ' ')" \
    "reproduce: grep -n '^build_' scripts/build-pacman-static"
fi

#---------------------------------------------------------------------------#
# 9. ⛔ Progress goes to stderr. ensure_zig, fetch and src_of give a path on
#    stdout, and a caller takes stdout as that path. step writes to stderr, so
#    an echo is the remaining risk.
#---------------------------------------------------------------------------#
step_def="$(awk '/^step\(\)/ && !done { print; done = 1 }' "$BUILD")"
if [[ "$step_def" == *'>&2'* ]]; then
  ok "step writes progress to stderr"
else
  fail "step writes progress to stderr" "found: ${step_def:-no step()}" \
    "reproduce: grep -n 'step()' scripts/build-pacman-static"
fi

leaky=""
for fn in ensure_zig fetch src_of; do
  body="$(awk -v f="^$fn\\\\(\\\\) \\\\{" '$0 ~ f { inside = 1 } inside { print } inside && /^}/ { inside = 0 }' "$BUILD")"
  if [ -z "$body" ]; then
    leaky="$leaky $fn(not found)"
    continue
  fi
  printf '%s\n' "$body" | awk '
    /^[[:space:]]+echo[[:space:]]/ && !/>&2/ { hit = 1 }
    END { exit hit ? 0 : 1 }' && leaky="$leaky $fn"
done
if [ -z "$leaky" ]; then
  ok "ensure_zig, fetch and src_of write no progress to stdout"
else
  fail "ensure_zig, fetch and src_of write no progress to stdout" \
    "these do:$leaky" \
    "reproduce: sed -n '/^fetch()/,/^}/p' scripts/build-pacman-static"
fi

if awk '/(configure|make|Configure)[^|]*> *\/dev\/null/ { hit = 1 } END { exit hit ? 0 : 1 }' "$BUILD"; then
  fail "no library build sends its output to /dev/null" \
    "a configure that fails then stops the run with no message" \
    "reproduce: grep -n '/dev/null' scripts/build-pacman-static"
else
  ok "no library build sends its output to /dev/null"
fi

#---------------------------------------------------------------------------#
# 10. --check-evidence refuses what must not reach a release.
#---------------------------------------------------------------------------#
if need_tool jq; then
  jq -n '{arch: "zz9", pacman_tag_verified_by: "6645B0A8C7005E78DB1D7864F99FFE0FEAE999BD",
          reported_version: "Pacman v9.9.9 - libalpm v99.0.0", interp_segments: 0,
          sha256: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"}' > "$work/good.json"
  rc=0
  "$BUILD" --check-evidence "$work/good.json" > "$work/check.out" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    ok "--check-evidence passes a verified, run, static binary"
  else
    fail "--check-evidence passes a verified, run, static binary" \
      "exit $rc: $(tr '\n' ';' < "$work/check.out")" \
      "reproduce: scripts/build-pacman-static --check-evidence <evidence.json>"
  fi
  for case_ in '.pacman_tag_verified_by = "NOT VERIFIED"' '.pacman_tag_verified_by = "SKIPPED"' \
    '.reported_version = "NOT MEASURED"' '.interp_segments = 1' 'del(.sha256)'; do
    jq "$case_" "$work/good.json" > "$work/bad.json"
    rc=0
    "$BUILD" --check-evidence "$work/bad.json" > "$work/check.out" 2>&1 || rc=$?
    if [ "$rc" -ne 0 ]; then
      ok "--check-evidence refuses $case_"
    else
      fail "--check-evidence refuses $case_" \
        "it exited 0" \
        "reproduce: jq '$case_' good.json > bad.json; scripts/build-pacman-static --check-evidence bad.json"
    fi
  done
fi

#---------------------------------------------------------------------------#
# 11. pacman-static.yml: matrix from scripts/ports, the evidence check, the
#     weekly schedule, workflow_call, and meson from scripts/install-tools at
#     or above the minimum.
#---------------------------------------------------------------------------#
if need_tool yq jq; then
  rc=0
  yaml_json "$WF" > "$work/ps.json" || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "pacman-static.yml is valid YAML" "yq exited $rc" "reproduce: yq . .github/workflows/pacman-static.yml"
  else
    j() { jq -r "$1" "$work/ps.json"; }
    matrix="$(j '.jobs.build.strategy.matrix.include // "" | tostring')"
    ports_step="$(j '[.jobs.setup.steps[] | select((.run // "") | test("scripts/ports matrix"))] | length')"
    # shellcheck disable=SC2016 # a GitHub expression, compared as text
    if [ "$matrix" = '${{ fromJSON(needs.setup.outputs.matrix) }}' ] && [ "$ports_step" -ge 1 ]; then
      ok "pacman-static.yml builds the ports of scripts/ports matrix"
    else
      fail "pacman-static.yml builds the ports of scripts/ports matrix" \
        "matrix.include: $matrix, setup steps that run scripts/ports matrix: $ports_step" \
        "⛔ a list of ports in a workflow goes stale when a port is added" \
        "reproduce: yq '.jobs.build.strategy.matrix' .github/workflows/pacman-static.yml"
    fi

    checks="$(j '[.jobs.build.steps[] | select((.run // "") | test("scripts/build-pacman-static --check-evidence"))] | length')"
    # shellcheck disable=SC2016 # $ARCH is text in the workflow, matched by jq
    build_at="$(j '[.jobs.build.steps | to_entries[] | select((.value.run // "") | test("scripts/build-pacman-static \"\\$ARCH\"")) | .key] | first // -1')"
    check_at="$(j '[.jobs.build.steps | to_entries[] | select((.value.run // "") | test("--check-evidence")) | .key] | first // -1')"
    upload_at="$(j '[.jobs.build.steps | to_entries[] | select((.value.uses // "") | test("upload-artifact")) | .key] | first // -1')"
    if [ "$checks" -ge 1 ] && [ "$build_at" -ge 0 ] && [ "$build_at" -lt "$check_at" ] && [ "$check_at" -lt "$upload_at" ]; then
      ok "pacman-static.yml checks the evidence after the build and before the upload"
    else
      fail "pacman-static.yml checks the evidence after the build and before the upload" \
        "step index: build $build_at, check $check_at, upload $upload_at" \
        "reproduce: yq '.jobs.build.steps[].name' .github/workflows/pacman-static.yml"
    fi

    cron="$(j '.on.schedule[0].cron // ""')"
    called="$(j '.on | has("workflow_call")')"
    if printf '%s\n' "$cron" | awk 'NF == 5 && $3 == "*" && $4 == "*" && $5 ~ /^[0-6]$/ { hit = 1 } END { exit hit ? 0 : 1 }' \
      && [ "$called" = true ]; then
      ok "pacman-static.yml runs once a week and release.yml can call it"
    else
      fail "pacman-static.yml runs once a week and release.yml can call it" \
        "cron: ${cron:-none}, workflow_call: $called" \
        "reproduce: yq '.on' .github/workflows/pacman-static.yml"
    fi

    # meson has one pin: MESON_VERSION of scripts/install-tools, with its sha256.
    installs="$(j '[.jobs.build.steps[] | select((.run // "") | test("scripts/install-tools [^\n]* meson"))] | length')"
    pinned="$(awk -F= '/^MESON_VERSION=/ { print $2 }' "$REPO_ROOT/scripts/install-tools")"
    min="$(awk -F= '/^MESON_MIN=/ { print $2 }' "$BUILD")"
    if [ "$installs" -ge 1 ] && [[ $pinned =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]] && [ -n "$min" ] \
      && [ "$(printf '%s\n%s\n' "$min" "$pinned" | sort -V | awk 'NR == 1')" = "$min" ]; then
      ok "pacman-static.yml installs meson $pinned with scripts/install-tools, at or above MESON_MIN $min"
    else
      fail "pacman-static.yml installs meson with scripts/install-tools, at or above MESON_MIN of the build script" \
        "build steps that run scripts/install-tools for meson: $installs" \
        "MESON_VERSION of scripts/install-tools: ${pinned:-none}, MESON_MIN: ${min:-none}" \
        "reproduce: grep -n MESON_ scripts/install-tools scripts/build-pacman-static; yq '.jobs.build.steps[].run' .github/workflows/pacman-static.yml"
    fi
  fi
fi

#---------------------------------------------------------------------------#
# 12. ⛔ The image build does not read the pin or fetch the static pacman.
#---------------------------------------------------------------------------#
leaks=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  awk '/pacman-static|sources\.pin/ { hit = 1 } END { exit hit ? 0 : 1 }' "$f" \
    && leaks="$leaks ${f#"$REPO_ROOT/"}"
done <<< "$(printf '%s\n' "$REPO_ROOT/Dockerfile"; find "$REPO_ROOT/bootstrap/any" -type f | LC_ALL=C sort)"
if [ -z "$leaks" ]; then
  ok "the Dockerfile and bootstrap/any do not name the static pacman"
else
  fail "the Dockerfile and bootstrap/any do not name the static pacman" \
    "named in:$leaks" \
    "an image that downloads a prebuilt binary at build time is not bootstrappable from the base image" \
    "reproduce: grep -rn -e pacman-static -e sources.pin Dockerfile bootstrap/any"
fi

#---------------------------------------------------------------------------#
# 13. ⭐ A reused WORK gives the zig of the current pin, and the build records
#     the version that the zig binary reports. Two stand-in zig tarballs are
#     put in WORK/dl under their sha256, so nothing is downloaded.
#---------------------------------------------------------------------------#
if need_tool tar gzip sha256sum; then
  zr="$work/zig-reuse"
  mkdir -p "$zr/repo/scripts" "$zr/repo/bootstrap/pacman-static" "$zr/work/dl" "$zr/t"
  cp "$BUILD" "$REPO_ROOT/scripts/lib.sh" "$zr/repo/scripts/"
  host="$(uname -m)-linux"
  # stand_in VERSION -> the sha256 of a zig tarball whose zig reports VERSION
  stand_in() {
    mkdir -p "$zr/t/zig-$1"
    # shellcheck disable=SC2016 # $1 is for the stand-in, written literally
    printf '#!/bin/sh\n[ "$1" = version ] && echo %s\n' "$1" > "$zr/t/zig-$1/zig"
    chmod +x "$zr/t/zig-$1/zig"
    tar -czf "$zr/zig-$1.tar.gz" -C "$zr/t" "zig-$1"
    local sum
    sum="$(sha256sum "$zr/zig-$1.tar.gz" | awk '{ print $1 }')"
    cp "$zr/zig-$1.tar.gz" "$zr/work/dl/$sum"
    printf '%s\n' "$sum"
  }
  # zig_of VERSION SHA256 -> what --zig prints for a pin of that zig
  zig_of() {
    printf 'zig %s %s https://example.invalid/zig-%s.tar.gz %s\n' "$1" "$host" "$1" "$2" \
      > "$zr/repo/bootstrap/pacman-static/sources.pin"
    local rc=0 out
    out="$(env -u ZIG WORK="$zr/work" bash "$zr/repo/scripts/build-pacman-static" --zig 2> "$zr/err")" || rc=$?
    printf '%s %s\n' "$rc" "$(printf '%s' "$out" | awk '{ print $NF }')"
  }
  zrepro="bash tests/static/85-pacman-static-pin.sh; WORK=<dir> scripts/build-pacman-static --zig"
  check_eq "--zig unpacks the pinned zig and gives the version that it reports" \
    "0 1.0.0" "$(zig_of 1.0.0 "$(stand_in 1.0.0)")" "$zrepro"
  check_eq "after a pin change, a reused WORK gives the zig of the new pin" \
    "0 2.0.0" "$(zig_of 2.0.0 "$(stand_in 2.0.0)")" "$zrepro"
  mkdir -p "$zr/own"
  # shellcheck disable=SC2016 # $1 is for the stand-in, written literally
  printf '#!/bin/sh\n[ "$1" = version ] && echo 3.0.0\n' > "$zr/own/zig"
  chmod +x "$zr/own/zig"
  rc=0
  got="$(ZIG="$zr/own/zig" WORK="$zr/work" bash "$zr/repo/scripts/build-pacman-static" --zig 2> "$zr/err")" || rc=$?
  check_eq "with ZIG set, --zig gives that binary and the version that it reports, not the pinned one" \
    "0 $zr/own/zig 3.0.0" "$rc $got" "$zrepro"
fi

summary
