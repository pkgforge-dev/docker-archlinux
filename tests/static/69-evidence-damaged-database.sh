#!/usr/bin/env bash
#
# gen-evidence on a database with a damaged entry:
#   - a damaged entry in a repository database costs that entry only
#   - the evidence has the anchor that the build resolved
#   - the commit and the time of the build come from the image when the
#     caller does not give them
#
# ⛔ A database can store a desc member as a sparse file. GNU tar writes a
# sparse member to standard output with a seek, and into a regular file the
# seek writes over the records before it. Arch RISC-V's extra.db has such a
# member. This test makes a database of that shape, a sparse member between
# ordinary ones, and runs scripts/gen-evidence on it. A stand-in runtime
# answers for the image, so there is no container and no network.
#
# ⚠ A sparse member needs GNU tar and a filesystem with holes. Without them
# the test skips, or fails under TESTS_REQUIRE_TOOLS=1.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

GEN="$REPO_ROOT/scripts/gen-evidence"
if [ ! -f "$GEN" ]; then
  fail "scripts/gen-evidence exists" "reproduce: ls scripts/gen-evidence"
  summary
  exit 1
fi
if ! need_tool tar gzip truncate jq; then
  summary
  exit 0
fi

work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/repo/scripts" "$work/repo/rootfs/fake/etc/pacman.d" \
  "$work/snap" "$work/bin" "$work/core" "$work/extra"
cp "$GEN" "$work/repo/scripts/gen-evidence"
printf '[options]\nArchitecture = x86_64\n\n[core]\nInclude = /etc/pacman.d/mirrorlist\n\n[extra]\nInclude = /etc/pacman.d/mirrorlist\n' \
  > "$work/repo/rootfs/fake/etc/pacman.conf"
# The host cannot be reached: with a snapshot nothing may be fetched.
printf 'Server = https://example.invalid/repo/os/arch\n' > "$work/repo/rootfs/fake/etc/pacman.d/mirrorlist"

# desc DIR NAME VERSION -> a desc member at DIR/NAME-VERSION/desc
#
# ⚠ Each member has a %DESC% of 1000 bytes. The records before the sparse
# member are then longer than its 576 bytes. So an extract into a file
# writes over them, and this test shows it.
LONG_DESC="$(printf '%01000d' 0)"
desc() {
  mkdir -p "$1/$2-$3"
  printf '%%FILENAME%%\n%s-%s-x86_64.pkg.tar.zst\n\n%%NAME%%\n%s\n\n%%VERSION%%\n%s\n\n%%DESC%%\n%s\n\n%%CSIZE%%\n1000\n\n%%ISIZE%%\n4000\n\n%%SHA256SUM%%\n%064d\n\n%%BUILDDATE%%\n1760000000\n\n' \
    "$2" "$3" "$2" "$3" "$LONG_DESC" 7 > "$1/$2-$3/desc"
}
desc "$work/core" pacman 7.1.0-1
desc "$work/core" zlib 1.3-1
desc "$work/extra" alpha 1.0-1
desc "$work/extra" beta 2.0-1
desc "$work/extra" zeta 3.0-1
# The damaged member: a hole and nothing else.
mkdir -p "$work/extra/ntk-1.3-4"
truncate -s 576 "$work/extra/ntk-1.3-4/desc"

tar -czf "$work/snap/core.db" -C "$work/core" pacman-7.1.0-1 zlib-1.3-1
# alpha and beta come before ntk in the archive: the order that matters.
rc=0
tar --sparse --format=posix --sparse-version=1.0 -czf "$work/snap/extra.db" \
  -C "$work/extra" alpha-1.0-1 beta-2.0-1 ntk-1.3-4 zeta-3.0-1 2> "$work/tar.err" || rc=$?
if [ "$rc" -ne 0 ] || ! gzip -dc "$work/snap/extra.db" | awk 'index($0, "GNU.sparse") { found = 1 } END { exit found ? 0 : 1 }'; then
  if [ "${TESTS_REQUIRE_TOOLS:-0}" = 1 ]; then
    fail "the fixture database stores a desc member sparse" "tar exit $rc: $(tr '\n' ' ' < "$work/tar.err")" \
      "it needs GNU tar and a filesystem with holes" \
      "reproduce: tar --sparse --format=posix --sparse-version=1.0 -czf x.tgz <dir with a sparse file>"
  else
    TESTS_RUN=$((TESTS_RUN + 1))
    printf 'ok %d - # SKIP this host cannot store a sparse tar member\n' "$TESTS_RUN"
  fi
  summary
  exit 0
fi
ok "the fixture database stores a desc member sparse"

# The stand-in runtime answers three questions: the installed set,
# os-release, and the labels of the image (the file FAKE_LABELS). Any other
# call is one this test did not expect.
cat > "$work/bin/fake-runtime" <<'RT'
#!/usr/bin/env bash
case "$*" in
  *'/var/lib/pacman/local/'*) cat "$FAKE_LOCAL" ;;
  *'/etc/os-release'*) printf '2030.01.02\n' ;;
  'image inspect '*'.Config.Labels'*) cat "$FAKE_LABELS" ;;
  *) echo "fake-runtime: unexpected call: $*" >&2; exit 2 ;;
esac
RT
chmod +x "$work/bin/fake-runtime"

# installed FILE NAME-VERSION... -> the stream that gen-evidence reads from an image
installed() {
  local out="$1" nv
  shift
  : > "$out"
  for nv in "$@"; do
    printf '%%NAME%%\n%s\n\n%%VERSION%%\n%s\n\n%%%%END%%%%\n' "${nv%% *}" "${nv#* }" >> "$out"
  done
}

# run_gen LOCAL [ENV=VALUE...] -> the exit code; stderr in $work/err, the file in $work/out.json
run_gen() {
  local local_file="$1" rc=0
  shift
  rm -f "$work/out.json"
  (
    cd "$work/repo" &&
      env FAKE_LOCAL="$local_file" FAKE_LABELS="$work/labels.json" \
        CONTAINER_RUNTIME="$work/bin/fake-runtime" DB_SNAPSHOT="$work/snap" \
        SOURCE_COMMIT=0000000000000000000000000000000000000000 BUILD_DATE=2030-01-02T00:00:00Z "$@" \
        bash scripts/gen-evidence fake "localhost/fake@sha256:$(printf '%064d' 1)" linux/amd64 "$work/out.json"
  ) > "$work/out" 2> "$work/err" || rc=$?
  printf '%s\n' "$rc"
}
said() { awk -v n="$1" 'index($0, n) { found = 1 } END { exit found ? 0 : 1 }' "$work/err"; }
last_words() { tr -d '\r' < "$work/err" | awk 'NF { last = $0 } END { print last }'; }
repro="bash tests/static/69-evidence-damaged-database.sh; the fixtures are made in the test"

#---------------------------------------------------------------------------#
# 1. The packages on each side of the damaged member are all there.
#---------------------------------------------------------------------------#
installed "$work/local-ok" "pacman 7.1.0-1" "zlib 1.3-1" "alpha 1.0-1" "beta 2.0-1" "zeta 3.0-1"
rc="$(run_gen "$work/local-ok")"
if [ "$rc" -eq 0 ] && [ -f "$work/out.json" ]; then
  ok "gen-evidence writes the evidence past a sparse member"
else
  fail "gen-evidence writes the evidence past a sparse member" "exit $rc: $(last_words)" \
    "⛔ the packages before the member are the ones that go missing" "reproduce: $repro"
fi

if [ -f "$work/out.json" ]; then
  missing="$(jq -r '[ .packages[] | select(.sha256 == "-") | .name ] | join(" ")' "$work/out.json")"
  count="$(jq -r '.package_count' "$work/out.json")"
  if [ -z "$missing" ] && [ "$count" = 5 ]; then
    ok "each of the five packages has a sha256, alpha and beta too"
  else
    fail "each of the five packages has a sha256, alpha and beta too" \
      "without one: ${missing:-none}; count: $count" "reproduce: $repro"
  fi
fi

if said "ntk-1.3-4"; then
  ok "the damaged member is named in the log"
else
  fail "the damaged member is named in the log" "stderr does not name ntk-1.3-4" "reproduce: $repro"
fi

#---------------------------------------------------------------------------#
# 2. An installed package with a damaged entry: exit 4, and the package named.
#---------------------------------------------------------------------------#
installed "$work/local-ntk" "pacman 7.1.0-1" "alpha 1.0-1" "ntk 1.3-4"
rc="$(run_gen "$work/local-ntk")"
if [ "$rc" -eq 4 ] && said "ntk 1.3-4" && [ ! -f "$work/out.json" ]; then
  ok "an installed package with a damaged entry is refused with exit 4, named, and no file is written"
else
  fail "an installed package with a damaged entry is refused with exit 4, named, and no file is written" \
    "exit $rc: $(last_words)" "reproduce: $repro"
fi

#---------------------------------------------------------------------------#
# 3. A package that is in no database: exit 5.
#---------------------------------------------------------------------------#
installed "$work/local-gone" "pacman 7.1.0-1" "omega 9.0-1"
rc="$(run_gen "$work/local-gone")"
if [ "$rc" -eq 5 ] && said "omega 9.0-1" && [ ! -f "$work/out.json" ]; then
  ok "a package that the snapshot does not have is refused with exit 5, and named"
else
  fail "a package that the snapshot does not have is refused with exit 5, and named" "exit $rc: $(last_words)" "reproduce: $repro"
fi

#---------------------------------------------------------------------------#
# 4. EXPECT_ANCHOR: the image must have the anchor that the build resolved.
#---------------------------------------------------------------------------#
rc="$(run_gen "$work/local-ok" EXPECT_ANCHOR=7.1.0-1)"
if [ "$rc" -eq 0 ] && [ "$(jq -r '.anchor.version' "$work/out.json")" = 7.1.0-1 ]; then
  ok "the evidence anchor equals EXPECT_ANCHOR, and the file is written"
else
  fail "the evidence anchor equals EXPECT_ANCHOR, and the file is written" "exit $rc: $(last_words)" "reproduce: $repro"
fi

rc="$(run_gen "$work/local-ok" EXPECT_ANCHOR=7.1.0-2)"
if [ "$rc" -eq 6 ] && [ ! -f "$work/out.json" ]; then
  ok "an anchor that is not EXPECT_ANCHOR stops the leg with exit 6, and no file is written"
else
  fail "an anchor that is not EXPECT_ANCHOR stops the leg with exit 6, and no file is written" \
    "exit $rc: $(last_words)" "⛔ the tag <alias>-<anchor> would name a version the image does not have" "reproduce: $repro"
fi

#---------------------------------------------------------------------------#
# 5. ⛔ The commit and the time of the build. With no SOURCE_COMMIT and no
#    BUILD_DATE they are the labels of the image, and unknown for a label
#    that is absent or empty. A release that makes the evidence again gives
#    neither, so the file names the build, not the release.
#---------------------------------------------------------------------------#
REV=1a2b1da778e1f26a5e92f92974e322e25c90ac02
CREATED=2030-01-01T09:11:41Z
# labels_of REVISION CREATED -> the labels JSON of an image with those values
labels_of() {
  jq -cn --arg r "$1" --arg c "$2" \
    '{"org.opencontainers.image.revision": $r, "org.opencontainers.image.created": $c}'
}
# provenance LABELS-JSON [ENV=VALUE...] -> "EXIT SOURCE_COMMIT BUILT"
provenance() {
  local rc
  printf '%s\n' "$1" > "$work/labels.json"
  shift
  rc="$(run_gen "$work/local-ok" "$@")"
  if [ -f "$work/out.json" ]; then
    printf '%s %s\n' "$rc" "$(jq -r '.source_commit + " " + .built' "$work/out.json")"
  else
    printf '%s - -\n' "$rc"
  fi
}
check_eq "with no SOURCE_COMMIT and no BUILD_DATE, the evidence has the revision and created labels of the image" \
  "0 $REV $CREATED" "$(provenance "$(labels_of "$REV" "$CREATED")" SOURCE_COMMIT= BUILD_DATE=)" "$repro"
check_eq "an image with no labels gives unknown for the commit and the time" \
  "0 unknown unknown" "$(provenance null SOURCE_COMMIT= BUILD_DATE=)" "$repro"
check_eq "an empty revision label gives unknown, and the created label stays" \
  "0 unknown $CREATED" "$(provenance "$(labels_of "" "$CREATED")" SOURCE_COMMIT= BUILD_DATE=)" "$repro"
check_eq "SOURCE_COMMIT and BUILD_DATE, when set, are recorded as they are" \
  "0 0000000000000000000000000000000000000000 2030-01-02T00:00:00Z" \
  "$(provenance "$(labels_of "$REV" "$CREATED")")" "$repro"
got="$(provenance 'not json' SOURCE_COMMIT= BUILD_DATE=)"
if [ "${got%% *}" -ne 0 ] && [ ! -f "$work/out.json" ]; then
  ok "labels that are not JSON stop gen-evidence, and no file is written (exit ${got%% *})"
else
  fail "labels that are not JSON stop gen-evidence, and no file is written" \
    "got: $got: $(last_words)" "reproduce: $repro"
fi

summary
