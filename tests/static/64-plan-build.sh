#!/usr/bin/env bash
#
# The inputs of the build legs:
#   1. scripts/plan-build decides the ports to build and the targets.
#   2. scripts/binfmt-register has a fallback registration for each port that
#      needs an emulator, with the magic and mask of qemu.
#   3. scripts/pick-base-image picks the first registry that serves the base
#      image digest, or the digest of --image. With --after VALUE, it asks
#      only the registries after the one of VALUE.
#
# No registry is called: each script reads its registry facts from fixtures.
# The ports come from scripts/ports.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

PLAN="$REPO_ROOT/scripts/plan-build"
BINFMT="$REPO_ROOT/scripts/binfmt-register"
BASE="$REPO_ROOT/scripts/pick-base-image"
PORTS="$REPO_ROOT/scripts/ports"
FX="$(fixture_dir)"

for f in "$PLAN" "$BINFMT" "$BASE"; do
  if [ ! -x "$f" ]; then
    fail "${f#"$REPO_ROOT/"} is executable" "reproduce: ls -l ${f#"$REPO_ROOT/"}"
    summary
    exit 1
  fi
done
if ! need_tool jq; then
  summary
  exit 0
fi

work="$(work_dir)"
trap 'rm -rf "$work"' EXIT
repro="bash tests/static/64-plan-build.sh; the fixtures are made in the test"

GHCR="ghcr.io/example/archlinux"
HUB="docker.io/example/archlinux"
NOW="2030-01-02T05:30:00Z"
VERSION="2030.01.02"
mapfile -t ARCHES < <("$PORTS" list)
P1="${ARCHES[0]}"
P2="${ARCHES[1]}"
A1="$("$PORTS" aliases "$P1" | awk 'NR == 1')"

#---------------------------------------------------------------------------#
# 1. scripts/plan-build
#---------------------------------------------------------------------------#
mkdir -p "$work/plan"
# Today's dated tag of P1 is on the real image; nothing is on the scratch one.
printf 'ghcr.io\texample/archlinux\t%s\n' latest "$A1-v$VERSION" "$A1-v2030.01.01" > "$work/plan/tags.tsv"

# plan NAME ENV... -> exit code; stdout in $work/plan/NAME
plan() {
  local name="$1" rc=0
  shift
  env -u GITHUB_OUTPUT GHCR_IMAGE="$GHCR" HUB_IMAGE="$HUB" PLAN_NOW="$NOW" "$@" \
    "$PLAN" --dry-plan --fixtures "$work/plan" > "$work/plan/$name" 2> "$work/plan/$name.err" || rc=$?
  printf '%s\n' "$rc"
}
# output NAME KEY -> the value of an output
output() { awk -v k="output $2=" 'index($0, k) == 1 { print substr($0, length(k) + 1) }' "$work/plan/$1"; }
others="$(printf '%s\n' "${ARCHES[@]}" | awk -v a="$P1" '$0 != a' | tr '\n' ' ' | sed 's/ $//')"

rc="$(plan day)"
if [ "$rc" -eq 0 ] && [ "$(output day arches)" = "$others" ] && [ "$(output day skipped)" = "$P1" ] &&
  grep -qxF "skip $P1 $A1-v$VERSION" "$work/plan/day"; then
  ok "a port that has its dated tag for today is not built again"
else
  fail "a port that has its dated tag for today is not built again" \
    "exit $rc; arches '$(output day arches)', skipped '$(output day skipped)'" "reproduce: $repro"
fi

if [ "$(output day version)" = "$VERSION" ] && [ "$(output day build_date)" = "$NOW" ]; then
  ok "the version is the UTC date of the plan"
else
  fail "the version is the UTC date of the plan" "version '$(output day version)'" "reproduce: $repro"
fi

m_arches="$(output day matrix | jq -r '[.[].arch] | join(" ")')"
m_keys="$(output day matrix | jq -r '[.[] | has("platform") and has("aliases")] | all')"
if [ "$m_arches" = "$others" ] && [ "$m_keys" = true ]; then
  ok "the matrix is scripts/ports matrix of the planned ports"
else
  fail "the matrix is scripts/ports matrix of the planned ports" "matrix arches '$m_arches', keys $m_keys" "reproduce: $repro"
fi

if [ "$(output day target_image)" = "$GHCR" ] && [ "$(output day hub_target)" = "$HUB" ] &&
  [ "$(output day publish_hub)" = true ]; then
  ok "a real run targets the published images and copies to Docker Hub"
else
  fail "a real run targets the published images and copies to Docker Hub" \
    "$(awk '/^output /' "$work/plan/day" | tr '\n' '|')" "reproduce: $repro"
fi

rc="$(plan force FORCE=true)"
if [ "$rc" -eq 0 ] && [ "$(output force arches)" = "$(tr '\n' ' ' <<< "$(printf '%s\n' "${ARCHES[@]}")" | sed 's/ $//')" ]; then
  ok "FORCE=true builds every port"
else
  fail "FORCE=true builds every port" "exit $rc; arches '$(output force arches)'" "reproduce: $repro"
fi

rc="$(plan pick ARCHES="$P2 $P1 $P2")"
if [ "$rc" -eq 0 ] && [ "$(output pick arches)" = "$P2" ] && [ "$(output pick skipped)" = "$P1" ]; then
  ok "ARCHES limits the plan, each port once"
else
  fail "ARCHES limits the plan, each port once" "exit $rc; arches '$(output pick arches)'" "reproduce: $repro"
fi

rc="$(plan unknown ARCHES="$P1 notaport")"
if [ "$rc" -ne 0 ]; then
  ok "ARCHES with a name that is not a port stops the plan"
else
  fail "ARCHES with a name that is not a port stops the plan" "exit 0" "reproduce: $repro"
fi

rc="$(plan published ARCHES="$P1")"
if [ "$rc" -eq 0 ] && [ "$(output published arches)" = "" ] && [ "$(output published matrix)" = "[]" ]; then
  ok "when each planned port has its dated tag, the matrix is [] and the run stands down"
else
  fail "when each planned port has its dated tag, the matrix is [] and the run stands down" \
    "exit $rc; matrix '$(output published matrix)'" "reproduce: $repro"
fi

printf 'ghcr.io\texample/archlinux\n' > "$work/plan/unreadable"
rc="$(plan blind)"
rm -f "$work/plan/unreadable"
if [ "$rc" -eq 0 ] && [ -z "$(output blind skipped)" ] && [ "$(output blind arches | wc -w)" -eq "${#ARCHES[@]}" ]; then
  ok "a tag list that cannot be read builds every port"
else
  fail "a tag list that cannot be read builds every port" "exit $rc; arches '$(output blind arches)'" "reproduce: $repro"
fi

rc="$(plan dry DRY_RUN=true)"
if [ "$rc" -eq 0 ] && [ "$(output dry target_image)" = "$GHCR-ci" ] && [ "$(output dry hub_target)" = "$HUB-ci" ] &&
  [ "$(output dry publish_hub)" = false ] && [ "$(output dry carry_image)" = "$GHCR" ] &&
  [ -z "$(output dry skipped)" ]; then
  ok "a dry run targets the scratch images, reads the scratch tag list and copies nothing to Docker Hub"
else
  fail "a dry run targets the scratch images, reads the scratch tag list and copies nothing to Docker Hub" \
    "exit $rc; $(awk '/^output /' "$work/plan/dry" | tr '\n' '|')" "reproduce: $repro"
fi

rc="$(plan dryhub DRY_RUN=true DRY_RUN_HUB=true)"
if [ "$rc" -eq 0 ] && [ "$(output dryhub publish_hub)" = true ] && [ "$(output dryhub hub_target)" = "$HUB-ci" ]; then
  ok "dry_run with dry_run_hub copies to the Docker Hub scratch image"
else
  fail "dry_run with dry_run_hub copies to the Docker Hub scratch image" "exit $rc" "reproduce: $repro"
fi

rc="$(plan hubonly DRY_RUN_HUB=true)"
if [ "$rc" -ne 0 ] && [ -z "$(output hubonly target_image)" ]; then
  ok "dry_run_hub without dry_run stops the plan"
else
  fail "dry_run_hub without dry_run stops the plan" "exit $rc" \
    "alone it would take the real images and look like a test" "reproduce: $repro"
fi

rc="$(plan badtime PLAN_NOW=2030-01-02)"
if [ "$rc" -ne 0 ]; then
  ok "a plan time that is not YYYY-MM-DDTHH:MM:SSZ stops the plan"
else
  fail "a plan time that is not YYYY-MM-DDTHH:MM:SSZ stops the plan" "exit 0" "reproduce: $repro"
fi

#---------------------------------------------------------------------------#
# 2. scripts/binfmt-register
#---------------------------------------------------------------------------#
"$BINFMT" --table | awk 'NF { print $1, $2, $3 }' | LC_ALL=C sort > "$work/table"
awk -F'\t' '!/^#/ && NF { print $1, $2, $3 }' "$FX/binfmt.tsv" | LC_ALL=C sort > "$work/want-table"
if cmp -s "$work/table" "$work/want-table"; then
  ok "the fallback table has the magic and mask of qemu for each emulator"
else
  fail "the fallback table has the magic and mask of qemu for each emulator" \
    "diff: $(diff "$work/want-table" "$work/table" | tr '\n' '|')" \
    "reproduce: scripts/binfmt-register --table; compare tests/fixtures/64-plan-build/binfmt.tsv"
fi

# Each port that needs an emulator has a fallback entry whose byte order
# (ELF byte 5: \x01 little, \x02 big) is the endian of the port.
missing=""
wrong=""
n_emulated=0
for a in "${ARCHES[@]}"; do
  [ "$("$PORTS" get "$a" binfmt)" != native ] || continue
  n_emulated=$((n_emulated + 1))
  q="$("$PORTS" get "$a" qemu)"
  magic="$(awk -v q="$q" '$1 == q { print $2 }' "$work/table")"
  if [ -z "$magic" ]; then
    missing="$missing $a($q)"
    continue
  fi
  # The text \x7f is 4 characters and ELF is 3, so byte 4 starts at 8 and byte 5 at 12.
  data="$(M="$magic" awk 'BEGIN { print substr(ENVIRON["M"], 12, 4) }')"
  case "$("$PORTS" get "$a" endian):$data" in
    little:'\x01' | big:'\x02') ;;
    *) wrong="$wrong $a(endian $("$PORTS" get "$a" endian), byte 5 $data)" ;;
  esac
done
if [ "$n_emulated" -gt 0 ] && [ -z "$missing$wrong" ]; then
  ok "each of the $n_emulated emulated ports has a fallback registration with its byte order"
else
  fail "each emulated port has a fallback registration with its byte order" \
    "no entry:${missing:- none}; wrong byte order:${wrong:- none}" \
    "reproduce: scripts/binfmt-register --table; scripts/ports field qemu"
fi

# bytes TEXT -> the bytes of TEXT, the \xHH escapes read, as hex pairs
# Through the environment: awk -v would read the escapes.
bytes() {
  S="$1" awk 'BEGIN {
    s = ENVIRON["S"]; out = ""
    while (length(s) > 0) {
      if (substr(s, 1, 2) == "\\x") { out = out tolower(substr(s, 3, 2)) " "; s = substr(s, 5) }
      else { out = out sprintf("%02x ", index("ABCDEFGHIJKLMNOPQRSTUVWXYZ", substr(s, 1, 1)) + 64); s = substr(s, 2) }
    }
    print out
  }'
}
bad_len=""
while read -r name magic mask; do
  b_magic="$(bytes "$magic")"
  n_magic="$(wc -w <<< "$b_magic")"
  n_mask="$(bytes "$mask" | wc -w)"
  case "$b_magic" in '7f 45 4c 46 '*) ;; *) bad_len="$bad_len $name(no ELF magic: ${b_magic:0:12})" ;; esac
  # The kernel reads at most 128 bytes of a file for binfmt_misc.
  [ "$n_magic" -ge 20 ] && [ "$n_magic" -le 128 ] && [ "$n_mask" -eq "$n_magic" ] ||
    bad_len="$bad_len $name(magic $n_magic, mask $n_mask bytes)"
done < "$work/table"
if [ -z "$bad_len" ]; then
  ok "each magic starts with the ELF magic, and each mask has the length of its magic"
else
  fail "each magic starts with the ELF magic, and each mask has the length of its magic" "bad:$bad_len" \
    "reproduce: scripts/binfmt-register --table"
fi

# ⭐ The table is keyed by emulator, not by port. A port whose emulator is in
# the table needs no edit of the script. A port whose emulator is not there
# stops, and the message names the file to edit.
mkdir -p "$work/ports"
unused="$(awk 'NR == FNR { if (NF) used[$2] = 1; next } !($1 in used) { print $1 }' \
  <("$PORTS" field qemu) "$work/table" | awk 'NR == 1')"
emu_port="$(for a in "${ARCHES[@]}"; do [ "$("$PORTS" get "$a" binfmt)" = native ] || printf '%s\n' "$a"; done | awk 'NR == 1')"
if [ -n "$unused" ] && [ -n "$emu_port" ]; then
  awk -v q="$unused" '/^[[:space:]]*qemu[[:space:]]*=/ { print "qemu = " q; next } { print }' \
    "$REPO_ROOT/ports/$emu_port.conf" > "$work/ports/$emu_port.conf"
  rc=0
  line="$(PORTS_DIR="$work/ports" "$BINFMT" --line "$emu_port" 2> "$work/known.err")" || rc=$?
  if [ "$rc" -eq 0 ] && [[ "$line" =~ ^:$unused:M::.*:/usr/bin/$unused-static:F$ ]]; then
    ok "a port with an emulator of the table that no port uses yet ($unused) needs no edit of the script"
  else
    fail "a port with an emulator of the table that no port uses yet ($unused) needs no edit of the script" \
      "exit $rc; line: ${line:-none}; $(tr '\n' '|' < "$work/known.err")" \
      "reproduce: PORTS_DIR=<dir with qemu = $unused> scripts/binfmt-register --line $emu_port"
  fi

  awk '/^[[:space:]]*qemu[[:space:]]*=/ { print "qemu = qemu-notanemulator"; next } { print }' \
    "$REPO_ROOT/ports/$emu_port.conf" > "$work/ports/$emu_port.conf"
  rc=0
  PORTS_DIR="$work/ports" "$BINFMT" --line "$emu_port" > "$work/unknown.out" 2> "$work/unknown.err" || rc=$?
  rc2=0
  mkdir -p "$work/binfmt-empty"
  PORTS_DIR="$work/ports" BINFMT_DIR="$work/binfmt-empty" BINFMT_SOURCES=ubuntu \
    "$BINFMT" "$emu_port" > "$work/unknown2.out" 2> "$work/unknown2.err" || rc2=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$work/unknown.out" ] && grep -qF scripts/binfmt-register "$work/unknown.err" &&
    grep -qF tests/fixtures/64-plan-build/binfmt.tsv "$work/unknown.err" &&
    [ "$rc2" -eq 1 ] && grep -qF scripts/binfmt-register "$work/unknown2.err"; then
    ok "an emulator that the table does not have stops binfmt-register, and the message names the files to edit"
  else
    fail "an emulator that the table does not have stops binfmt-register, and the message names the files to edit" \
      "--line: exit $rc, $(tr '\n' '|' < "$work/unknown.err"); register: exit $rc2, $(tr '\n' '|' < "$work/unknown2.err")" \
      "reproduce: PORTS_DIR=<dir with qemu = qemu-notanemulator> scripts/binfmt-register --line $emu_port"
  fi
elif [ -n "$emu_port" ]; then
  fail "the fallback table has an emulator that no port uses yet" "every NAME of the table is the qemu of a port" \
    "the table holds every emulator of qemu's scripts/qemu-binfmt-conf.sh" \
    "reproduce: scripts/binfmt-register --table; scripts/ports field qemu"
fi

emulated="$(for a in "${ARCHES[@]}"; do [ "$("$PORTS" get "$a" binfmt)" = native ] || printf '%s\n' "$a"; done | awk 'NR == 1')"
if [ -n "$emulated" ]; then
  q="$("$PORTS" get "$emulated" qemu)"
  line="$("$BINFMT" --line "$emulated")"
  if [[ "$line" =~ ^:$q:M::\\x7fELF[^:]*:[^:]*:/usr/bin/$q-static:F$ ]]; then
    ok "the fallback registration line names /usr/bin/$q-static with the F flag"
  else
    fail "the fallback registration line names /usr/bin/$q-static with the F flag" "line: $line" \
      "reproduce: scripts/binfmt-register --line $emulated"
  fi

  # The check after registration, with a fake binfmt_misc and no source.
  mkdir -p "$work/binfmt"
  printf 'enabled\ninterpreter /usr/bin/%s-static\nflags: F\noffset 0\n' "$q" > "$work/binfmt/$q"
  rc=0
  BINFMT_DIR="$work/binfmt" BINFMT_SOURCES="" "$BINFMT" "$emulated" > "$work/binfmt.out" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    ok "a registration that is enabled with the F flag passes the check"
  else
    fail "a registration that is enabled with the F flag passes the check" "exit $rc" \
      "reproduce: BINFMT_DIR=<dir> BINFMT_SOURCES= scripts/binfmt-register $emulated"
  fi
  printf 'enabled\ninterpreter /usr/bin/%s-static\nflags: OC\noffset 0\n' "$q" > "$work/binfmt/$q"
  rc=0
  BINFMT_DIR="$work/binfmt" BINFMT_SOURCES="" "$BINFMT" "$emulated" > "$work/binfmt.out" 2>&1 || rc=$?
  if [ "$rc" -ne 0 ]; then
    ok "a registration without the F flag fails the check"
  else
    fail "a registration without the F flag fails the check" "exit 0" \
      "⚠ without F the kernel opens the emulator inside the build container" \
      "reproduce: BINFMT_DIR=<dir> BINFMT_SOURCES= scripts/binfmt-register $emulated"
  fi
fi

native="$(for a in "${ARCHES[@]}"; do [ "$("$PORTS" get "$a" binfmt)" != native ] || printf '%s\n' "$a"; done | awk 'NR == 1')"
if [ -n "$native" ]; then
  rc=0
  BINFMT_DIR="$work/no-such-dir" "$BINFMT" "$native" > "$work/native.out" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    ok "a native port needs no emulator"
  else
    fail "a native port needs no emulator" "exit $rc" "reproduce: scripts/binfmt-register $native"
  fi
fi

#---------------------------------------------------------------------------#
# 3. scripts/pick-base-image
#---------------------------------------------------------------------------#
DF="$FX/base-image-arg.txt"
d="$(awk -F@ '/^ARG BASE_IMAGE=/ { print $2 }' "$DF")"
mkdir -p "$work/base"
# base NAME HEADS -> exit code; stdout in $work/base/NAME
base() {
  local rc=0
  printf '%b' "$2" > "$work/base/heads.tsv"
  "$BASE" --fixtures "$work/base" "$DF" > "$work/base/$1" 2> "$work/base/$1.err" || rc=$?
  printf '%s\n' "$rc"
}
rc="$(base hub "docker.io\tlibrary/archlinux\t$d\t200\t$d\n")"
if [ "$rc" -eq 0 ] && [ "$(cat "$work/base/hub")" = "$(awk -F= '/^ARG BASE_IMAGE=/ { print $2 }' "$DF")" ]; then
  ok "when docker.io serves the digest, BASE_IMAGE is the Dockerfile value"
else
  fail "when docker.io serves the digest, BASE_IMAGE is the Dockerfile value" "exit $rc: $(cat "$work/base/hub")" "reproduce: $repro"
fi
rc="$(base gcr "docker.io\tlibrary/archlinux\t$d\t429\t\nmirror.gcr.io\tlibrary/archlinux\t$d\t200\t$d\n")"
if [ "$rc" -eq 0 ] && [ "$(cat "$work/base/gcr")" = "mirror.gcr.io/library/archlinux@$d" ]; then
  ok "when docker.io does not answer, BASE_IMAGE is the same digest on mirror.gcr.io"
else
  fail "when docker.io does not answer, BASE_IMAGE is the same digest on mirror.gcr.io" \
    "exit $rc: $(cat "$work/base/gcr")" "reproduce: $repro"
fi
rc="$(base ecr "mirror.gcr.io\tlibrary/archlinux\t$d\t200\tsha256:$(printf '%064d' 9)\npublic.ecr.aws\tdocker/library/archlinux\t$d\t200\t$d\n")"
if [ "$rc" -eq 0 ] && [ "$(cat "$work/base/ecr")" = "public.ecr.aws/docker/library/archlinux@$d" ]; then
  ok "a registry that answers with another digest is passed over"
else
  fail "a registry that answers with another digest is passed over" "exit $rc: $(cat "$work/base/ecr")" "reproduce: $repro"
fi
rc="$(base limit "docker.io\tlibrary/archlinux\t$d\t200\t$d\t0\nmirror.gcr.io\tlibrary/archlinux\t$d\t200\t$d\n")"
if [ "$rc" -eq 0 ] && [ "$(cat "$work/base/limit")" = "mirror.gcr.io/library/archlinux@$d" ]; then
  ok "⭐ when the Docker Hub pull limit is used up (ratelimit-remaining 0), BASE_IMAGE is the same digest on mirror.gcr.io"
else
  fail "⭐ when the Docker Hub pull limit is used up (ratelimit-remaining 0), BASE_IMAGE is the same digest on mirror.gcr.io" \
    "exit $rc: $(cat "$work/base/limit")" "reproduce: $repro"
fi
rc="$(base limit-left "docker.io\tlibrary/archlinux\t$d\t200\t$d\t3\nmirror.gcr.io\tlibrary/archlinux\t$d\t200\t$d\n")"
if [ "$rc" -eq 0 ] && [ "$(cat "$work/base/limit-left")" = "$(awk -F= '/^ARG BASE_IMAGE=/ { print $2 }' "$DF")" ]; then
  ok "a Docker Hub answer with pulls left keeps docker.io"
else
  fail "a Docker Hub answer with pulls left keeps docker.io" "exit $rc: $(cat "$work/base/limit-left")" "reproduce: $repro"
fi
# reg_head_limit of scripts/lib.sh reads the count of ratelimit-remaining.
# A stand-in curl writes the status and the headers of one answer.
mkdir -p "$work/rl/bin"
cat > "$work/rl/bin/curl" << 'CURL'
#!/usr/bin/env bash
set -euo pipefail
hdr=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -D) hdr="$2"; shift 2 ;;
    -o) : > "$2"; shift 2 ;;
    *) shift ;;
  esac
done
[ -z "$hdr" ] || printf '%b' "$FAKE_HDR" > "$hdr"
printf '%s' "$FAKE_CODE"
CURL
chmod +x "$work/rl/bin/curl"
# rl CODE HEADERS -> the line that reg_head_limit prints
rl() {
  local rc=0 out
  out="$(FAKE_CODE="$1" FAKE_HDR="$2" PATH="$work/rl/bin:$PATH" HTTP_TRIES=1 \
    bash -c 'PROG=t; . "$1"; reg_head_limit docker.io library/archlinux "$2" ""' _ "$REPO_ROOT/scripts/lib.sh" "$d")" || rc=$?
  printf '%s %s\n' "$rc" "$out"
}
rlrepro="PROG=t; . scripts/lib.sh; reg_head_limit docker.io library/archlinux $d"
got="$(rl 200 "HTTP/1.1 200 OK\r\ndocker-content-digest: $d\r\nratelimit-limit: 100;w=21600\r\nratelimit-remaining: 0;w=21600\r\n")"
check_eq "reg_head_limit gives the digest and a remaining count of 0" "0 200 $d 0" "$got" "$rlrepro"
got="$(rl 200 "HTTP/1.1 200 OK\r\nDocker-Content-Digest: $d\r\nRateLimit-Remaining: 76;w=21600\r\n")"
check_eq "reg_head_limit reads the headers in any case" "0 200 $d 76" "$got" "$rlrepro"
got="$(rl 200 "HTTP/1.1 200 OK\r\ndocker-content-digest: $d\r\n")"
check_eq "reg_head_limit gives - for an answer with no ratelimit-remaining" "0 200 $d -" "$got" "$rlrepro"
got="$(rl 404 "HTTP/1.1 404 Not Found\r\n")"
check_eq "reg_head_limit gives - for the digest of an answer that is not 200" "0 404 - -" "$got" "$rlrepro"
rc="$(base none "")"
if [ "$rc" -ne 0 ] && [ ! -s "$work/base/none" ]; then
  ok "when no registry serves the digest, nothing is printed and the leg stops"
else
  fail "when no registry serves the digest, nothing is printed and the leg stops" "exit $rc" "reproduce: $repro"
fi

# --image: an image that is not a Docker official image, as the buildkit
# image of the builder. ECR Public mirrors the official images only.
IMG_D="sha256:$(printf '%064d' 7)"
IMG="docker.io/example/tool:stable@$IMG_D"
# image NAME HEADS -> exit code; stdout in $work/base/NAME
image() {
  local rc=0
  printf '%b' "$2" > "$work/base/heads.tsv"
  "$BASE" --fixtures "$work/base" --image "$IMG" > "$work/base/$1" 2> "$work/base/$1.err" || rc=$?
  printf '%s\n' "$rc"
}
rc="$(image img-hub "docker.io\texample/tool\t$IMG_D\t200\t$IMG_D\n")"
if [ "$rc" -eq 0 ] && [ "$(cat "$work/base/img-hub")" = "$IMG" ]; then
  ok "--image: when docker.io serves the digest, the value is the image as given"
else
  fail "--image: when docker.io serves the digest, the value is the image as given" \
    "exit $rc: $(cat "$work/base/img-hub")" "reproduce: $repro"
fi
rc="$(image img-gcr "docker.io\texample/tool\t$IMG_D\t503\t\nmirror.gcr.io\texample/tool\t$IMG_D\t200\t$IMG_D\n")"
if [ "$rc" -eq 0 ] && [ "$(cat "$work/base/img-gcr")" = "mirror.gcr.io/example/tool@$IMG_D" ]; then
  ok "--image: when docker.io does not answer, the value is the same digest on mirror.gcr.io"
else
  fail "--image: when docker.io does not answer, the value is the same digest on mirror.gcr.io" \
    "exit $rc: $(cat "$work/base/img-gcr")" "reproduce: $repro"
fi
rc="$(image img-ecr "public.ecr.aws\tdocker/example/tool\t$IMG_D\t200\t$IMG_D\n")"
if [ "$rc" -eq 1 ] && [ ! -s "$work/base/img-ecr" ]; then
  ok "--image: ECR Public is not asked for an image that is not a Docker official image"
else
  fail "--image: ECR Public is not asked for an image that is not a Docker official image" \
    "exit $rc: $(cat "$work/base/img-ecr")" "reproduce: $repro"
fi
rc=0
"$BASE" --fixtures "$work/base" --image "docker.io/example/tool:stable" > "$work/base/img-bad" 2>&1 || rc=$?
if [ "$rc" -eq 1 ]; then
  ok "--image: an image with no digest is refused"
else
  fail "--image: an image with no digest is refused" "exit $rc" "reproduce: scripts/pick-base-image --image docker.io/example/tool:stable"
fi

# --after VALUE: only the registries after the one of VALUE. scripts/build-port
# asks for it when a pull meets a used-up pull limit.
hub_v="$(awk -F= '/^ARG BASE_IMAGE=/ { print $2 }' "$DF")"
gcr_v="mirror.gcr.io/library/archlinux@$d"
ecr_v="public.ecr.aws/docker/library/archlinux@$d"
printf 'docker.io\tlibrary/archlinux\t%s\t200\t%s\nmirror.gcr.io\tlibrary/archlinux\t%s\t200\t%s\npublic.ecr.aws\tdocker/library/archlinux\t%s\t200\t%s\n' \
  "$d" "$d" "$d" "$d" "$d" "$d" > "$work/base/heads.tsv"
# after VALUE -> "<exit code> <printed value>"
after() {
  local rc=0 v
  v="$("$BASE" --fixtures "$work/base" --after "$1" "$DF" 2> "$work/base/after.err")" || rc=$?
  printf '%s %s\n' "$rc" "$v"
}
check_eq "--after the docker.io value: the same digest on mirror.gcr.io, though docker.io serves it" \
  "0 $gcr_v" "$(after "$hub_v")" "reproduce: $repro"
check_eq "--after the mirror.gcr.io value: the same digest on ECR Public" "0 $ecr_v" "$(after "$gcr_v")" "reproduce: $repro"
check_eq "--after the last registry: nothing is printed and the exit status is 1" "1 " "$(after "$ecr_v")" "reproduce: $repro"
check_eq "--after a value that is not a value of the image is refused" \
  "2 " "$(after "mirror.gcr.io/library/other@$d")" "reproduce: $repro"

# The Dockerfile of the tree: pick-base-image reads its one BASE_IMAGE pin,
# and the fallback names the same digest on the second registry.
REAL_DF="$REPO_ROOT/Dockerfile"
real_d="$(awk '/^[[:space:]]*ARG[[:space:]]+BASE_IMAGE=/ { n = split($0, p, "@"); print p[n] }' "$REAL_DF")"
real_repo="$(awk '/^[[:space:]]*ARG[[:space:]]+BASE_IMAGE=docker\.io\// {
    sub(/^[^=]*=docker\.io\//, ""); sub(/[:@].*$/, ""); print }' "$REAL_DF")"
mkdir -p "$work/real"
printf 'mirror.gcr.io\t%s\t%s\t200\t%s\n' "$real_repo" "$real_d" "$real_d" > "$work/real/heads.tsv"
rc=0
"$BASE" --fixtures "$work/real" "$REAL_DF" > "$work/real/out" 2> "$work/real/err" || rc=$?
if [ "$rc" -eq 0 ] && [ -n "$real_repo" ] && [ "$(cat "$work/real/out")" = "mirror.gcr.io/$real_repo@$real_d" ]; then
  ok "the Dockerfile has one BASE_IMAGE pin that pick-base-image can move to another registry"
else
  fail "the Dockerfile has one BASE_IMAGE pin that pick-base-image can move to another registry" \
    "exit $rc; printed '$(cat "$work/real/out")'; $(tr '\n' '|' < "$work/real/err")" \
    "the build arg must be docker.io/<repo>[:<tag>]@sha256:<64 hex>" \
    "reproduce: grep -n 'ARG BASE_IMAGE' Dockerfile; scripts/pick-base-image"
fi

summary
