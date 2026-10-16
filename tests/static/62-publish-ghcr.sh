#!/usr/bin/env bash
#
# scripts/publish-ghcr plans the right writes, and refuses the wrong ones.
#
# Each case runs `scripts/publish-ghcr --fixtures DIR`: every registry fact
# comes from files, no registry is called and nothing is written. The ports
# come from scripts/ports, so the cases follow the port table.
#
# scripts/report-build --dry-plan is checked at the end: which issue each
# outcome raises or clears.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

PUB="$REPO_ROOT/scripts/publish-ghcr"
REPORT="$REPO_ROOT/scripts/report-build"
PORTS="$REPO_ROOT/scripts/ports"

for f in "$PUB" "$REPORT" "$PORTS"; do
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

TARGET="ghcr.io/example/archlinux"
CARRY="ghcr.io/example/archlinux"
HUB="docker.io/example/archlinux"
VERSION="2030.01.02"

mapfile -t ARCHES < <("$PORTS" list)
n_ports="${#ARCHES[@]}"
if [ "$n_ports" -lt 4 ]; then
  fail "the port table has at least 4 ports for these cases" "it has $n_ports" "reproduce: scripts/ports list"
  summary
  exit 1
fi
P1="${ARCHES[0]}"
P2="${ARCHES[1]}"
LAST="${ARCHES[$((n_ports - 1))]}"

first_alias() { "$PORTS" aliases "$1" | awk 'NR == 1'; }
platform_of() { "$PORTS" get "$1" platform; }
# digest N -> a sha256 digest made of the number N
digest() { printf 'sha256:%064d' "$1"; }

# index_json ARCH... -> an index whose platforms are those of ARCH...
index_json() {
  local a p os rest arch variant i=100 out='{"schemaVersion":2,"manifests":['
  local sep=""
  for a in "$@"; do
    p="$(platform_of "$a")"
    os="${p%%/*}"
    rest="${p#*/}"
    arch="${rest%%/*}"
    variant=""
    [ "$arch" = "$rest" ] || variant="${rest#*/}"
    i=$((i + 1))
    out="$out$sep{\"digest\":\"$(digest "$i")\",\"platform\":{\"os\":\"$os\",\"architecture\":\"$arch\"$([ -n "$variant" ] && printf ',"variant":"%s"' "$variant")}}"
    sep=","
  done
  printf '%s]}\n' "$out"
}

# setup NAME -> a fresh fixture directory and digest directory for one case
setup() {
  FX="$work/$1/fx"
  DG="$work/$1/digests"
  mkdir -p "$FX" "$DG"
  : > "$FX/tags.tsv"
  : > "$FX/heads.tsv"
  : > "$FX/manifests.tsv"
}
tag_of() { printf 'ghcr.io\texample/archlinux\t%s\n' "$1" >> "$FX/tags.tsv"; }
head_of() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$FX/heads.tsv"; }
fresh_of() { # ARCH N ANCHOR [PLATFORM]
  jq -n --arg a "$1" --arg p "${4:-$(platform_of "$1")}" --arg d "$(digest "$2")" --arg an "$3" \
    '{arch: $a, platform: $p, digest: $d, anchor: $an, transport: "worker", skip_servers: "",
      base_image: "x", mirrorlist: "generated", built_at: "2030-01-02T05:30:00Z"}' > "$DG/digest-$1.json"
}

# run_pub NAME -> exit code; stdout in $work/NAME/out, stderr in $work/NAME/err
run_pub() {
  local rc=0
  env -u GITHUB_OUTPUT TARGET_IMAGE="$TARGET" CARRY_IMAGE="$CARRY" HUB_IMAGE="$HUB" VERSION="$VERSION" \
    RETRY_PAUSE=0 "$PUB" --fixtures "$FX" "$DG" > "$work/$1/out" 2> "$work/$1/err" || rc=$?
  printf '%s\n' "$rc"
}

# line NAME PREFIX -> the lines of stdout that start with PREFIX
lines() { awk -v p="$2" 'index($0, p) == 1' "$work/$1/out"; }

repro="bash tests/static/62-publish-ghcr.sh; the fixtures are made in the test"

#---------------------------------------------------------------------------#
# Case "day": P1 and P2 built, the others carried, LAST never published.
#---------------------------------------------------------------------------#
setup day
fresh_of "$P1" 1 7.1.0-1
fresh_of "$P2" 2 7.1.0-2
tag_of latest
tag_of v2030.01.01
tag_of "$(first_alias "$P1")-7.1.0-1"
carried_list=()
i=10
for a in "${ARCHES[@]}"; do
  [ "$a" = "$P1" ] || [ "$a" = "$P2" ] || [ "$a" = "$LAST" ] || {
    i=$((i + 1))
    head_of ghcr.io example/archlinux "$(first_alias "$a")" 200 "$(digest "$i")"
    carried_list+=("$a")
  }
done
mapfile -t prev < <(printf '%s\n' "${ARCHES[@]}" | awk -v l="$LAST" '$0 != l')
printf 'ghcr.io\texample/archlinux\tlatest\t%s\n' "$(index_json "${prev[@]}")" >> "$FX/manifests.tsv"

rc="$(run_pub day)"
if [ "$rc" -eq 0 ]; then
  ok "day: the dry plan exits 0"
else
  fail "day: the dry plan exits 0" "exit $rc: $(tr '\n' '|' < "$work/day/err")" "reproduce: $repro"
fi

want_sources="source $P1 fresh $TARGET@$(digest 1)
source $P2 fresh $TARGET@$(digest 2)"
got_sources="$(lines day "source $P1 ")
$(lines day "source $P2 ")"
if [ "$got_sources" = "$want_sources" ]; then
  ok "day: the built ports take their digest from digest-<arch>.json"
else
  fail "day: the built ports take their digest from digest-<arch>.json" "got: $got_sources" "reproduce: $repro"
fi

n_carried="$(lines day "source " | awk '$3 == "carried"' | awk 'END { print NR + 0 }')"
if [ "$n_carried" -eq "${#carried_list[@]}" ] && [ "$(lines day "absent $LAST")" = "absent $LAST" ]; then
  ok "day: ${#carried_list[@]} port(s) carried from <first alias>, and the port with no image is absent"
else
  fail "day: ${#carried_list[@]} port(s) carried from <first alias>, and the port with no image is absent" \
    "carried: $n_carried; stdout: $(tr '\n' '|' < "$work/day/out")" "reproduce: $repro"
fi

p1_tags="$(lines day "tag $TARGET@$(digest 1) ")"
anchor_tag="$TARGET:$(first_alias "$P1")-7.1.0-1"
dated_tag="$TARGET:$(first_alias "$P1")-v$VERSION"
if [ -n "$p1_tags" ] && ! grep -qF -- "$anchor_tag" <<< "$p1_tags" && grep -qF -- "$dated_tag" <<< "$p1_tags"; then
  ok "day: a pinned tag that exists is left out, a new pinned tag is made"
else
  fail "day: a pinned tag that exists is left out, a new pinned tag is made" \
    "the tag line of $P1: ${p1_tags:-none}" "reproduce: $repro"
fi

n_tag_lines="$(lines day "tag " | awk 'END { print NR + 0 }')"
if [ "$n_tag_lines" -eq 2 ]; then
  ok "day: only the built ports get port tags"
else
  fail "day: only the built ports get port tags" "tag lines: $n_tag_lines, want 2" "reproduce: $repro"
fi

index_line="$(lines day "index ")"
n_from="$(awk '{ for (i = 1; i <= NF; i++) if ($i == "from") { print NF - i; exit } }' <<< "$index_line")"
if grep -qF -- "$TARGET:latest $TARGET:v$VERSION from" <<< "$index_line" && [ "$n_from" -eq $((n_ports - 1)) ]; then
  ok "day: latest and v$VERSION are made from the $((n_ports - 1)) fresh and carried sources"
else
  fail "day: latest and v$VERSION are made from the fresh and carried sources" \
    "index line: ${index_line:-none}" "reproduce: $repro"
fi

if [ "$(awk '/^(tag|index) /' "$work/day/out" | awk 'END { print NR }')" -gt 0 ] &&
  [ "$(awk '/^index /{ i = NR } /^tag /{ t = NR } END { print (i > t) ? "last" : "early" }' "$work/day/out")" = last ]; then
  ok "day: the index is made after every port tag"
else
  fail "day: the index is made after every port tag" "stdout: $(tr '\n' '|' < "$work/day/out")" "reproduce: $repro"
fi

if [ "$(lines day "output fresh=")" = "output fresh=$P1 $P2" ] && [ "$(lines day "output absent=")" = "output absent=$LAST" ]; then
  ok "day: the outputs name the fresh and the absent ports"
else
  fail "day: the outputs name the fresh and the absent ports" "$(lines day output | tr '\n' '|')" "reproduce: $repro"
fi

#---------------------------------------------------------------------------#
# Case "again": a second run of the day. v<VERSION> exists and stays.
#---------------------------------------------------------------------------#
setup again
cp "$work/day/fx/heads.tsv" "$work/day/fx/manifests.tsv" "$FX/"
fresh_of "$P1" 1 7.1.0-1
printf 'ghcr.io\texample/archlinux\t%s\n' latest "v$VERSION" "$(first_alias "$P2")" > "$FX/tags.tsv"
head_of ghcr.io example/archlinux "$(first_alias "$P2")" 200 "$(digest 2)"
rc="$(run_pub again)"
index_line="$(lines again "index ")"
if [ "$rc" -eq 0 ] && grep -qF -- "index $TARGET:latest from" <<< "$index_line"; then
  ok "again: latest moves and the existing v$VERSION stays"
else
  fail "again: latest moves and the existing v$VERSION stays" "exit $rc, index line: ${index_line:-none}" "reproduce: $repro"
fi

#---------------------------------------------------------------------------#
# Case "lose": the present latest has the platform of LAST, and no source
# gives it. Nothing is written.
#---------------------------------------------------------------------------#
setup lose
cp "$work/day/fx/heads.tsv" "$work/day/fx/tags.tsv" "$FX/"
cp "$work/day/digests/"* "$DG/"
printf 'ghcr.io\texample/archlinux\tlatest\t%s\n' "$(index_json "${ARCHES[@]}")" > "$FX/manifests.tsv"
rc="$(run_pub lose)"
if [ "$rc" -ne 0 ] && [ -z "$(lines lose "tag ")" ] && [ -z "$(lines lose "index ")" ]; then
  ok "lose: a latest that would lose a platform stops the publish before any write"
else
  fail "lose: a latest that would lose a platform stops the publish before any write" \
    "exit $rc; stdout: $(tr '\n' '|' < "$work/lose/out")" "reproduce: $repro"
fi

#---------------------------------------------------------------------------#
# Case "flaky": GHCR does not answer for a carried port; Docker Hub does.
# Case "dark": neither answers. The publish stops.
#---------------------------------------------------------------------------#
setup flaky
fresh_of "$P1" 1 7.1.0-1
tag_of latest
head_of ghcr.io example/archlinux "$(first_alias "$P2")" 503 ""
head_of docker.io example/archlinux "$(first_alias "$P2")" 200 "$(digest 22)"
rc="$(run_pub flaky)"
if [ "$rc" -eq 0 ] && [ "$(lines flaky "source $P2 ")" = "source $P2 carried $CARRY@$(digest 22)" ]; then
  ok "flaky: a carried digest comes from Docker Hub when GHCR does not answer"
else
  fail "flaky: a carried digest comes from Docker Hub when GHCR does not answer" \
    "exit $rc; stdout: $(tr '\n' '|' < "$work/flaky/out")" "reproduce: $repro"
fi
setup dark
fresh_of "$P1" 1 7.1.0-1
tag_of latest
head_of ghcr.io example/archlinux "$(first_alias "$P2")" 503 ""
head_of docker.io example/archlinux "$(first_alias "$P2")" 500 ""
rc="$(run_pub dark)"
if [ "$rc" -ne 0 ] && [ -z "$(lines dark "index ")" ]; then
  ok "dark: a carried digest that no registry gives stops the publish"
else
  fail "dark: a carried digest that no registry gives stops the publish" \
    "exit $rc; stdout: $(tr '\n' '|' < "$work/dark/out")" \
    "read as absent, latest would lose the port" "reproduce: $repro"
fi

#---------------------------------------------------------------------------#
# Bad inputs.
#---------------------------------------------------------------------------#
setup unreadable
fresh_of "$P1" 1 7.1.0-1
printf 'ghcr.io\texample/archlinux\n' > "$FX/unreadable"
rc="$(run_pub unreadable)"
if [ "$rc" -ne 0 ] && [ -z "$(lines unreadable "tag ")" ]; then
  ok "a tag list that cannot be read stops the publish"
else
  fail "a tag list that cannot be read stops the publish" "exit $rc" \
    "read as empty, it would move every pinned tag" "reproduce: $repro"
fi

setup none
tag_of latest
rc="$(run_pub none)"
if [ "$rc" -eq 0 ] && [ -z "$(lines none "tag ")" ] && [ -z "$(lines none "index ")" ]; then
  ok "a run with no fresh port moves no tag"
else
  fail "a run with no fresh port moves no tag" "exit $rc; stdout: $(tr '\n' '|' < "$work/none/out")" "reproduce: $repro"
fi

setup badplatform
fresh_of "$P1" 1 7.1.0-1 "$(platform_of "$P2")"
tag_of latest
rc="$(run_pub badplatform)"
if [ "$rc" -ne 0 ]; then
  ok "a digest file whose platform is not the platform of its port is refused"
else
  fail "a digest file whose platform is not the platform of its port is refused" "exit 0" "reproduce: $repro"
fi

setup notaport
fresh_of "$P1" 1 7.1.0-1
cp "$DG/digest-$P1.json" "$DG/digest-notaport.json"
tag_of latest
rc="$(run_pub notaport)"
if [ "$rc" -ne 0 ]; then
  ok "a digest file for a name that is not a port is refused"
else
  fail "a digest file for a name that is not a port is refused" "exit 0" "reproduce: $repro"
fi

#---------------------------------------------------------------------------#
# Case "write": --write runs the writes with a stand-in docker, and reads the
# state after the write back from the fixtures. P1 is fresh; the others are
# carried. Each source is an index of its image and its attestation.
#---------------------------------------------------------------------------#
# source_json N ARCH -> the index of a source: its image and an attestation
source_json() {
  local p os rest arch variant
  p="$(platform_of "$2")"
  os="${p%%/*}"
  rest="${p#*/}"
  arch="${rest%%/*}"
  variant=""
  [ "$arch" = "$rest" ] || variant="${rest#*/}"
  jq -cn --arg d1 "$(digest $((1000 + $1)))" --arg d2 "$(digest $((2000 + $1)))" \
    --arg os "$os" --arg ar "$arch" --arg v "$variant" \
    '{schemaVersion: 2, manifests: [
       {digest: $d1, platform: ({os: $os, architecture: $ar} + (if $v == "" then {} else {variant: $v} end))},
       {digest: $d2, platform: {os: "unknown", architecture: "unknown"}}]}'
}

# write_case NAME DROP -> the fixtures of a write; DROP > 0 leaves one child
# out of latest, as a broken write would.
write_case() {
  setup "$1"
  local i=0 a latest='{"schemaVersion":2,"manifests":[]}' s
  fresh_of "$P1" 1 7.1.0-1
  tag_of v2030.01.01
  for a in "${ARCHES[@]}"; do
    i=$((i + 1))
    s="$(source_json "$i" "$a")"
    if [ "$a" = "$P1" ]; then
      printf 'ghcr.io\texample/archlinux\t%s\t%s\n' "$(digest 1)" "$s" >> "$FX/manifests.tsv"
      for t in $("$PORTS" aliases "$a"); do
        for shape in "$t" "$t-v$VERSION" "$t-7.1.0-1"; do
          head_of ghcr.io example/archlinux "$shape" 200 "$(digest 1)"
        done
      done
    else
      head_of ghcr.io example/archlinux "$(first_alias "$a")" 200 "$(digest $((10 + i)))"
      printf 'ghcr.io\texample/archlinux\t%s\t%s\n' "$(digest $((10 + i)))" "$s" >> "$FX/manifests.tsv"
    fi
    latest="$(jq -c --argjson s "$s" '.manifests += $s.manifests' <<< "$latest")"
  done
  if [ "$2" -gt 0 ]; then
    latest="$(jq -c 'del(.manifests[1])' <<< "$latest")"
  fi
  printf 'ghcr.io\texample/archlinux\tlatest\t%s\n' "$latest" >> "$FX/manifests.tsv"
  ld="sha256:$(printf '%s\n' "$latest" | sha256sum | awk '{ print $1 }')"
  head_of ghcr.io example/archlinux latest 200 "$ld"
  head_of ghcr.io example/archlinux "v$VERSION" 200 "$ld"
  mkdir -p "$work/$1/bin"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$work/$1/docker.log" > "$work/$1/bin/docker"
  chmod +x "$work/$1/bin/docker"
  : > "$work/$1/docker.log"
}
# run_write NAME -> exit code
run_write() {
  local rc=0
  env -u GITHUB_OUTPUT PATH="$work/$1/bin:$PATH" TARGET_IMAGE="$TARGET" CARRY_IMAGE="$CARRY" VERSION="$VERSION" \
    RETRY_PAUSE=0 PUBLISH_TRIES=2 "$PUB" --fixtures "$FX" --write "$DG" > "$work/$1/out" 2> "$work/$1/err" || rc=$?
  printf '%s\n' "$rc"
}

write_case write 0
rc="$(run_write write)"
n_calls="$(awk 'END { print NR + 0 }' "$work/write/docker.log")"
last_call="$(awk 'END { print }' "$work/write/docker.log")"
if [ "$rc" -eq 0 ] && [ "$n_calls" -eq 2 ] && grep -qF -- "-t $TARGET:latest -t $TARGET:v$VERSION " <<< "$last_call" &&
  [ "$(awk '{ print NF }' <<< "$last_call")" -gt $((5 + n_ports)) ]; then
  ok "write: one imagetools create for the fresh port, then one for the index, and each tag reads back"
else
  fail "write: one imagetools create for the fresh port, then one for the index, and each tag reads back" \
    "exit $rc; calls: $(tr '\n' '|' < "$work/write/docker.log"); stderr: $(tail -n 3 "$work/write/err" | tr '\n' '|')" \
    "reproduce: $repro"
fi

write_case broken 1
rc="$(run_write broken)"
if [ "$rc" -ne 0 ] && [ "$(awk 'END { print NR + 0 }' "$work/broken/docker.log")" -eq 2 ]; then
  ok "write: a latest that does not hold every child of the sources fails the publish"
else
  fail "write: a latest that does not hold every child of the sources fails the publish" \
    "exit $rc; stderr: $(tail -n 3 "$work/broken/err" | tr '\n' '|')" "reproduce: $repro"
fi

# The output published= comes only after the read back passes: report-build
# clears build-<arch> from it.
# run_write_out NAME -> exit code; GITHUB_OUTPUT in $work/NAME/gh-output
run_write_out() {
  local rc=0
  : > "$work/$1/gh-output"
  env GITHUB_OUTPUT="$work/$1/gh-output" PATH="$work/$1/bin:$PATH" TARGET_IMAGE="$TARGET" CARRY_IMAGE="$CARRY" \
    VERSION="$VERSION" RETRY_PAUSE=0 PUBLISH_TRIES=2 "$PUB" --fixtures "$FX" --write "$DG" \
    > "$work/$1/out" 2> "$work/$1/err" || rc=$?
  printf '%s\n' "$rc"
}
write_case outok 0
rc_ok="$(run_write_out outok)"
write_case outbad 1
rc_bad="$(run_write_out outbad)"
pub_ok="$(awk -F= '$1 == "published" { print $2 }' "$work/outok/gh-output")"
pub_bad="$(awk -F= '$1 == "published" { n++ } END { print n + 0 }' "$work/outbad/gh-output")"
fresh_bad="$(awk -F= '$1 == "fresh" { print $2 }' "$work/outbad/gh-output")"
if [ "$rc_ok" -eq 0 ] && [ "$pub_ok" = "$P1" ] && [ "$rc_bad" -ne 0 ] && [ "$pub_bad" -eq 0 ] && [ "$fresh_bad" = "$P1" ]; then
  ok "⛔ write: published= names the fresh ports after the read back, and a failed read back writes no published="
else
  fail "⛔ write: published= names the fresh ports after the read back, and a failed read back writes no published=" \
    "read back passed: exit $rc_ok, published '$pub_ok'; failed: exit $rc_bad, published lines $pub_bad, fresh '$fresh_bad'" \
    "reproduce: $repro"
fi

# ⛔ Every tag is checked before the first write. A port whose tags
# scripts/tag-names refuses (here a tag of 129 or more characters) stops the
# publish before any port is tagged.
# tag_case NAME ANCHOR -> P1 and P2 fresh, P2 with ANCHOR
tag_case() {
  write_case "$1" 0
  fresh_of "$P2" 2 "$2"
  printf 'ghcr.io\texample/archlinux\t%s\t%s\n' "$(digest 2)" "$(source_json 2 "$P2")" >> "$FX/manifests.tsv"
}
# The control: with a good anchor the same fixtures reach the writes.
tag_case tagok 7.2.0-1
rc="$(run_write tagok)"
n_ok="$(awk 'END { print NR + 0 }' "$work/tagok/docker.log")"
tag_case longtag "7.$(printf '%0130d' 1)-1"
rc="$(run_write longtag)"
n_calls="$(awk 'END { print NR + 0 }' "$work/longtag/docker.log")"
if [ "$n_ok" -ge 2 ] && [ "$rc" -ne 0 ] && [ "$n_calls" -eq 0 ]; then
  ok "a tag that scripts/tag-names refuses stops the publish before the first write"
else
  fail "a tag that scripts/tag-names refuses stops the publish before the first write" \
    "control: $n_ok docker calls; exit $rc; docker calls: $n_calls ($(tr '\n' '|' < "$work/longtag/docker.log"))" \
    "a stop half way leaves the ports before it tagged and latest not made" "reproduce: $repro"
fi

# ⛔ An anchor with a + is valid in pacman, and no tag can carry it.
setup plus
fresh_of "$P1" 1 7.1.0-1
fresh_of "$P2" 2 7.2.0+r3-1
tag_of latest
rc="$(run_pub plus)"
if [ "$rc" -ne 0 ] && [ -z "$(lines plus "tag ")" ] && [ -z "$(lines plus "index ")" ]; then
  ok "a digest file with an anchor that no tag can carry stops the publish before any write"
else
  fail "a digest file with an anchor that no tag can carry stops the publish before any write" \
    "exit $rc; stdout: $(tr '\n' '|' < "$work/plus/out")" "reproduce: $repro"
fi

#---------------------------------------------------------------------------#
# No fresh port: latest moves only when it does not hold the image of each
# first alias, as after an index write that failed.
#---------------------------------------------------------------------------#
# carry_case NAME STATE -> the fixtures of a run with no fresh port. Each port
# is carried. STATE: steady (latest holds each first alias), stale (latest
# holds older images), dated (stale, and the first alias of P1 has its
# <first alias>-v<VERSION> tag).
carry_case() {
  setup "$1"
  local i=0 a s old='{"schemaVersion":2,"manifests":[]}' now='{"schemaVersion":2,"manifests":[]}'
  tag_of latest
  tag_of v2030.01.01
  for a in "${ARCHES[@]}"; do
    i=$((i + 1))
    s="$(source_json "$i" "$a")"
    head_of ghcr.io example/archlinux "$(first_alias "$a")" 200 "$(digest $((10 + i)))"
    printf 'ghcr.io\texample/archlinux\t%s\t%s\n' "$(digest $((10 + i)))" "$s" >> "$FX/manifests.tsv"
    now="$(jq -c --argjson s "$s" '.manifests += $s.manifests' <<< "$now")"
    old="$(jq -c --argjson s "$(source_json $((50 + i)) "$a")" '.manifests += $s.manifests' <<< "$old")"
  done
  if [ "$2" = steady ]; then
    printf 'ghcr.io\texample/archlinux\tlatest\t%s\n' "$now" >> "$FX/manifests.tsv"
  else
    printf 'ghcr.io\texample/archlinux\tlatest\t%s\n' "$old" >> "$FX/manifests.tsv"
  fi
  if [ "$2" = dated ]; then
    tag_of "$(first_alias "$P1")-v$VERSION"
    head_of ghcr.io example/archlinux "$(first_alias "$P1")-v$VERSION" 200 "$(digest 11)"
  fi
}

carry_case steady steady
rc="$(run_pub steady)"
if [ "$rc" -eq 0 ] && [ -z "$(lines steady "tag ")" ] && [ -z "$(lines steady "index ")" ]; then
  ok "no fresh port, and latest holds the image of each first alias: no tag moves"
else
  fail "no fresh port, and latest holds the image of each first alias: no tag moves" \
    "exit $rc; stdout: $(tr '\n' '|' < "$work/steady/out")" "reproduce: $repro"
fi

carry_case stale stale
rc="$(run_pub stale)"
index_line="$(lines stale "index ")"
n_from="$(awk '{ for (i = 1; i <= NF; i++) if ($i == "from") { print NF - i; exit } }' <<< "$index_line")"
if [ "$rc" -eq 0 ] && [ -z "$(lines stale "tag ")" ] && grep -qF -- "index $TARGET:latest from" <<< "$index_line" &&
  [ "${n_from:-0}" -eq "$n_ports" ]; then
  ok "⭐ no fresh port, and latest holds older images: latest is made again from each first alias, with no v$VERSION"
else
  fail "⭐ no fresh port, and latest holds older images: latest is made again from each first alias, with no v$VERSION" \
    "exit $rc; index line: ${index_line:-none}; stderr: $(tail -n 3 "$work/stale/err" | tr '\n' '|')" \
    "a failed index write would leave latest behind until the next build" "reproduce: $repro"
fi

carry_case dated dated
rc="$(run_pub dated)"
index_line="$(lines dated "index ")"
if [ "$rc" -eq 0 ] && grep -qF -- "index $TARGET:latest $TARGET:v$VERSION from" <<< "$index_line"; then
  ok "no fresh port, and a first alias was built on $VERSION: latest and v$VERSION are made"
else
  fail "no fresh port, and a first alias was built on $VERSION: latest and v$VERSION are made" \
    "exit $rc; index line: ${index_line:-none}" "reproduce: $repro"
fi

carry_case unread stale
awk -F'\t' -v d="$(digest 11)" '$3 != d' "$FX/manifests.tsv" > "$FX/m" && mv "$FX/m" "$FX/manifests.tsv"
rc="$(run_pub unread)"
if [ "$rc" -ne 0 ] && [ -z "$(lines unread "index ")" ]; then
  ok "no fresh port, and a carried source cannot be read: the publish fails, so publish-ghcr is not cleared"
else
  fail "no fresh port, and a carried source cannot be read: the publish fails, so publish-ghcr is not cleared" \
    "exit $rc; stdout: $(tr '\n' '|' < "$work/unread/out")" "reproduce: $repro"
fi

#---------------------------------------------------------------------------#
# scripts/report-build --dry-plan: the issue of each outcome.
#---------------------------------------------------------------------------#
mkdir -p "$work/report"
printf '%s\tsuccess\t\n%s\tfailure\tResolve the anchor\n' "$P1" "$P2" > "$work/report/legs"
# report CASE ENV... -> stdout in $work/report/CASE
report() {
  local name="$1" rc=0
  shift
  env -u GITHUB_STEP_SUMMARY RUN_URL=https://example.invalid/run "$@" \
    "$REPORT" --dry-plan --legs "$work/report/legs" > "$work/report/$name" 2> "$work/report/$name.err" || rc=$?
  printf '%s\n' "$rc"
}
has() { grep -qxF -- "$2" "$work/report/$1"; }

rc="$(report pass ARCHES="$P1 $P2" PLAN_RESULT=success GATE_RESULT=success PUBLISH_RESULT=success \
  HUB_RESULT=failure PUBLISHED="$P1" CARRIED="$P2")"
if [ "$rc" -eq 0 ] && has pass "clear build-$P1" && has pass "raise build-$P2 build: $P2 is not publishing" &&
  has pass "clear publish-ghcr" && grep -q '^raise publish-hub ' "$work/report/pass"; then
  ok "report: a published port clears build-<arch>, a failed leg raises it, a failed copy raises publish-hub"
else
  fail "report: a published port clears build-<arch>, a failed leg raises it, a failed copy raises publish-hub" \
    "exit $rc; stdout: $(tr '\n' '|' < "$work/report/pass")" "reproduce: $repro"
fi

rc="$(report gate ARCHES="$P1 $P2" PLAN_RESULT=success GATE_RESULT=failure PUBLISH_RESULT=skipped HUB_RESULT=skipped)"
if [ "$rc" -eq 0 ] && grep -q '^raise publish-ghcr ' "$work/report/gate" && ! has gate "clear build-$P1" &&
  ! grep -q 'publish-hub' "$work/report/gate"; then
  ok "report: a failed gate raises publish-ghcr and clears no port"
else
  fail "report: a failed gate raises publish-ghcr and clears no port" \
    "exit $rc; stdout: $(tr '\n' '|' < "$work/report/gate")" "reproduce: $repro"
fi

rc="$(report standdown ARCHES="" PLAN_RESULT=success GATE_RESULT=success PUBLISH_RESULT=skipped HUB_RESULT=skipped)"
if [ "$rc" -eq 0 ] && ! grep -qE '^(raise|clear) ' "$work/report/standdown"; then
  ok "report: a run that stands down and does not publish raises and clears nothing"
else
  fail "report: a run that stands down and does not publish raises and clears nothing" \
    "exit $rc; stdout: $(tr '\n' '|' < "$work/report/standdown")" "reproduce: $repro"
fi

# ⛔ GitHub gives the outputs of a job that failed. A publish that wrote its
# outputs and then failed must not clear build-<arch>.
rc="$(report pubfail ARCHES="$P1 $P2" PLAN_RESULT=success GATE_RESULT=success PUBLISH_RESULT=failure \
  HUB_RESULT=skipped PUBLISHED="$P1" CARRIED="$P2")"
if [ "$rc" -eq 0 ] && ! grep -q '^clear build-' "$work/report/pubfail" && grep -q '^raise publish-ghcr ' "$work/report/pubfail"; then
  ok "report: a failed publish clears no build-<arch>, even when its output names the port, and raises publish-ghcr"
else
  fail "report: a failed publish clears no build-<arch>, even when its output names the port, and raises publish-ghcr" \
    "exit $rc; stdout: $(tr '\n' '|' < "$work/report/pubfail")" \
    "a false clear closes the issue of the port with 'published again'" "reproduce: $repro"
fi

rc="$(report notpub ARCHES="$P1" PLAN_RESULT=success GATE_RESULT=success PUBLISH_RESULT=success \
  HUB_RESULT=success PUBLISHED="")"
if [ "$rc" -eq 0 ] && ! grep -q '^clear build-' "$work/report/notpub" && has notpub "clear publish-ghcr"; then
  ok "report: a passed leg that the publish did not read back clears no build-<arch>"
else
  fail "report: a passed leg that the publish did not read back clears no build-<arch>" \
    "exit $rc; stdout: $(tr '\n' '|' < "$work/report/notpub")" "reproduce: $repro"
fi

rc="$(report repair ARCHES="" PLAN_RESULT=success GATE_RESULT=success PUBLISH_RESULT=success HUB_RESULT=success)"
if [ "$rc" -eq 0 ] && has repair "clear publish-ghcr" && ! grep -q 'build-' "$work/report/repair"; then
  ok "report: a stand-down whose publish passed clears publish-ghcr and no build-<arch>"
else
  fail "report: a stand-down whose publish passed clears publish-ghcr and no build-<arch>" \
    "exit $rc; stdout: $(tr '\n' '|' < "$work/report/repair")" "reproduce: $repro"
fi

summary
