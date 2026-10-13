#!/usr/bin/env bash
#
# A damaged entry in a repository database costs that entry, never its
# neighbours.
#
# ⛔ The fault this guards is measured, not imagined. Arch RISC-V's extra.db
# stores ntk-1.3.1001-4/desc sparse: 576 NUL bytes, written as GNU.sparse 1.0.
# GNU tar extracts a sparse member to standard output by seeking, and when
# standard output is a regular file the seek lands near its start. Every record
# written before the member is overwritten and tar still exits 0. Three
# installed packages that sort before ntk fell out of the evidence, and every
# riscv64 build failed from 2026-10-05. HISTORY/outage-2026-09.md.
#
# This builds a database with the same shape, a sparse member between ordinary
# ones, and runs the real scripts/gen-evidence against it. The image read goes
# through a stand-in runtime, so there is no container and no network.
#
# ⚠ Creating a sparse member needs GNU tar and a filesystem with holes. A host
# without either says so and skips, out loud.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

GEN="$REPO_ROOT/scripts/gen-evidence"
if [ ! -f "$GEN" ]; then
  fail "scripts/gen-evidence exists" "expected: $GEN" \
    "reproduce: ls scripts/gen-evidence"
  summary
  exit 1
fi

work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/repo/scripts" "$work/repo/rootfs/fake/etc/pacman.d" \
  "$work/snap" "$work/bin" "$work/core" "$work/extra"
cp "$GEN" "$work/repo/scripts/gen-evidence"

printf '[options]\nArchitecture = x86_64\n\n[core]\nInclude = /etc/pacman.d/mirrorlist\n\n[extra]\nInclude = /etc/pacman.d/mirrorlist\n' \
  > "$work/repo/rootfs/fake/etc/pacman.conf"
# shellcheck disable=SC2016
# The two dollar signs are literal, in pacman's mirrorlist syntax. The host is
# unreachable on purpose: with a snapshot nothing may be fetched.
printf 'Server = https://example.invalid/$repo/os/$arch\n' \
  > "$work/repo/rootfs/fake/etc/pacman.d/mirrorlist"

# desc DIR NAME VERSION -> a repository desc member at DIR/NAME-VERSION/desc
desc() {
  mkdir -p "$1/$2-$3"
  printf '%%FILENAME%%\n%s-%s-x86_64.pkg.tar.zst\n\n%%NAME%%\n%s\n\n%%VERSION%%\n%s\n\n%%CSIZE%%\n1000\n\n%%ISIZE%%\n4000\n\n%%SHA256SUM%%\n%064d\n\n%%BUILDDATE%%\n1760000000\n\n' \
    "$2" "$3" "$2" "$3" 7 > "$1/$2-$3/desc"
}

desc "$work/core" pacman 7.1.0-1
desc "$work/core" zlib 1.3-1
desc "$work/extra" alpha 1.0-1
desc "$work/extra" beta 2.0-1
desc "$work/extra" zeta 3.0-1
# The damaged member: a hole and nothing else, which is what upstream carries.
mkdir -p "$work/extra/ntk-1.3-4"
truncate -s 576 "$work/extra/ntk-1.3-4/desc"

tar -czf "$work/snap/core.db" -C "$work/core" pacman-7.1.0-1 zlib-1.3-1
# Archive order is the order that matters: alpha and beta come before ntk, as
# libsysprof-capture, lmdb and nftables came before it in the real one.
tar --sparse --format=posix --sparse-version=1.0 -czf "$work/snap/extra.db" \
  -C "$work/extra" alpha-1.0-1 beta-2.0-1 ntk-1.3-4 zeta-3.0-1

if ! gzip -dc "$work/snap/extra.db" | awk 'index($0, "GNU.sparse") { found = 1 } END { exit found ? 0 : 1 }'; then
  diag "skipped: this host's tar did not store ntk-1.3-4/desc sparse, so the fault cannot be built here"
  diag "it needs GNU tar and a filesystem that keeps holes"
  ok "the fixture could not be built on this host, which is reported rather than passed as a test"
  summary
  exit 0
fi
ok "the fixture database stores a desc member sparse, as Arch RISC-V's extra.db does"

# The stand-in runtime. gen-evidence asks it two questions: what is installed,
# and what os-release says. Anything else is a call this test did not expect.
cat > "$work/bin/fake-runtime" <<'RT'
#!/usr/bin/env bash
case "$*" in
  *'/var/lib/pacman/local/'*) cat "$FAKE_LOCAL" ;;
  *'/etc/os-release'*) printf '2026.10.13\n' ;;
  *) echo "fake-runtime: unexpected call: $*" >&2; exit 2 ;;
esac
RT
chmod +x "$work/bin/fake-runtime"

# installed FILE NAME-VERSION... -> the stream gen-evidence reads out of an image
installed() {
  local out="$1" nv
  shift
  : > "$out"
  for nv in "$@"; do
    printf '%%NAME%%\n%s\n\n%%VERSION%%\n%s\n\n%%%%END%%%%\n' "${nv%% *}" "${nv#* }" >> "$out"
  done
}

# run_gen LOCAL -> the exit code, with stderr in $work/err and the file in $work/out.json
run_gen() {
  local rc=0
  rm -f "$work/out.json"
  (
    cd "$work/repo" &&
    FAKE_LOCAL="$1" CONTAINER_RUNTIME="$work/bin/fake-runtime" DB_SNAPSHOT="$work/snap" \
      SOURCE_COMMIT=0000000000000000000000000000000000000000 BUILD_DATE=2026-10-13T00:00:00Z \
      bash scripts/gen-evidence fake \
        "localhost/fake@sha256:$(printf '%064d' 1)" linux/amd64 "$work/out.json"
  ) > "$work/out" 2> "$work/err" || rc=$?
  printf '%s\n' "$rc"
}

said() {
  awk -v n="$1" 'index($0, n) { found = 1 } END { exit found ? 0 : 1 }' "$work/err"
}

last_words() {
  tr -d '\r' < "$work/err" | awk 'NF { last = $0 } END { print last }'
}

#---------------------------------------------------------------------------#
# 1. The packages either side of the damaged member are all accounted for.
#---------------------------------------------------------------------------#
installed "$work/local-ok" "pacman 7.1.0-1" "zlib 1.3-1" "alpha 1.0-1" "beta 2.0-1" "zeta 3.0-1"
rc="$(run_gen "$work/local-ok")"
if [ "$rc" -eq 0 ] && [ -f "$work/out.json" ]; then
  ok "gen-evidence writes evidence past a sparse member in the database"
else
  fail "gen-evidence writes evidence past a sparse member in the database" \
    "exit $rc, and stderr ended: $(last_words)" \
    "⛔ the packages before the member are the ones that go missing" \
    "reproduce: bash tests/static/69-evidence-damaged-database.sh, which keeps its fixtures under a temp dir"
fi

if [ -f "$work/out.json" ]; then
  missing="$(jq -r '[ .packages[] | select(.sha256 == "-") | .name ] | join(" ")' "$work/out.json" | tr -d '\r')"
  if [ -z "$missing" ] && [ "$(jq -r '.package_count' "$work/out.json" | tr -d '\r')" = "5" ]; then
    ok "all five installed packages carry a sha256, including alpha and beta which sort before the damage"
  else
    fail "all five installed packages carry a sha256" \
      "without one: ${missing:-none}, recorded: $(jq -r '.package_count' "$work/out.json" | tr -d '\r')" \
      "reproduce: bash tests/static/69-evidence-damaged-database.sh, which keeps its fixtures under a temp dir"
  fi
fi

if said "ntk-1.3-4"; then
  ok "the damaged member is named in the log"
else
  fail "the damaged member is named in the log" \
    "stderr does not mention ntk-1.3-4, so a damaged entry upstream would pass unseen" \
    "reproduce: bash tests/static/69-evidence-damaged-database.sh, which keeps its fixtures under a temp dir"
fi

#---------------------------------------------------------------------------#
# 2. An installed package whose own entry is damaged is refused, and the
#    refusal says that rather than blaming a cache miss.
#---------------------------------------------------------------------------#
installed "$work/local-ntk" "pacman 7.1.0-1" "alpha 1.0-1" "ntk 1.3-4"
rc="$(run_gen "$work/local-ntk")"
if [ "$rc" -ne 0 ] && said "damaged upstream" && said "ntk 1.3-4"; then
  ok "an installed package with a damaged entry is refused, and named as damaged upstream"
else
  fail "an installed package with a damaged entry is refused, and named as damaged upstream" \
    "exit $rc, and stderr ended: $(last_words)" \
    "a diagnostic that blames the snapshot sends the reader to re-export something that is not at fault" \
    "reproduce: bash tests/static/69-evidence-damaged-database.sh, which keeps its fixtures under a temp dir"
fi

summary
