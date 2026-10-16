#!/usr/bin/env bash
#
# scripts/vercmp gives the result of pacman's vercmp, and
# scripts/check-anchor-floor uses it to refuse an anchor below the floor.
#
# The vectors are in tests/fixtures/61-vercmp/vectors.tsv: the list of
# pacman's test/util/vercmptest.sh and more. Each vector runs both ways.
#
# The floor checks use a tag list fixture and a stand-in for
# scripts/resolve-anchor, so no registry and no mirror is read.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

VERCMP="$REPO_ROOT/scripts/vercmp"
FLOOR="$REPO_ROOT/scripts/check-anchor-floor"
PORTS="$REPO_ROOT/scripts/ports"
FX="$(fixture_dir)"
work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

for f in "$VERCMP" "$FLOOR" "$FX/vectors.tsv"; do
  if [ ! -f "$f" ]; then
    fail "${f#"$REPO_ROOT/"} exists" "reproduce: ls ${f#"$REPO_ROOT/"}"
    summary
    exit 1
  fi
done

#---------------------------------------------------------------------------#
# 1. Every vector, both ways.
#---------------------------------------------------------------------------#
n=0
bad=""
while IFS=$'\t' read -r a b want; do
  case "$a" in '#'* | '') continue ;; esac
  n=$((n + 1))
  rc=0
  got="$("$VERCMP" "$a" "$b")" || rc=$?
  rrc=0
  rev="$("$VERCMP" "$b" "$a")" || rrc=$?
  if [ "$rc" -ne 0 ] || [ "$got" != "$want" ]; then
    bad="$bad [vercmp '$a' '$b' gave '$got' (exit $rc), want $want]"
  fi
  if [ "$rrc" -ne 0 ] || [ "$rev" != "$((-want))" ]; then
    bad="$bad [vercmp '$b' '$a' gave '$rev' (exit $rrc), want $((-want))]"
  fi
done < "$FX/vectors.tsv"

if [ "$n" -lt 40 ]; then
  fail "the vector fixture has at least 40 vectors" "it has $n" \
    "reproduce: grep -v '^#' tests/fixtures/61-vercmp/vectors.tsv"
elif [ -z "$bad" ]; then
  ok "vercmp gives the expected result for all $n vectors, both ways"
else
  fail "vercmp gives the expected result for all $n vectors, both ways" \
    "wrong:$bad" \
    "reproduce: scripts/vercmp A B, for each line of tests/fixtures/61-vercmp/vectors.tsv"
fi

rc=0
"$VERCMP" 1.0 > "$work/usage" 2>&1 || rc=$?
if [ "$rc" -eq 2 ]; then
  ok "vercmp with one argument exits 2"
else
  fail "vercmp with one argument exits 2" "exit $rc" "reproduce: scripts/vercmp 1.0; echo \$?"
fi

#---------------------------------------------------------------------------#
# 2. The anchor floor.
#
# The fixture tags name the first port of scripts/ports, through each of its
# aliases, so the test follows the port table.
#---------------------------------------------------------------------------#
arch="$("$PORTS" list | awk 'NR == 1')"
mapfile -t aliases < <("$PORTS" aliases "$arch")
first="${aliases[0]}"
last="${aliases[${#aliases[@]} - 1]}"
other="$("$PORTS" list | awk 'NR == 2')"

# Anchors 7.1.0-1 and 7.2.0-2; a dated tag that must not count as an anchor;
# a higher anchor of another port that must not count either.
{
  printf '%s\n' latest v2030.01.01
  printf '%s-7.1.0-1\n' "$first"
  printf '%s-7.2.0-2\n' "$last"
  printf '%s-v2030.01.01\n' "$first"
  printf '%s-9.9.9-9\n' "$("$PORTS" aliases "$other" | awk 'NR == 1')"
} > "$work/tags"

# A stand-in for scripts/resolve-anchor --each: it prints $EACH_FILE.
cat > "$work/resolve-anchor" <<'SH'
#!/usr/bin/env bash
[ "$1" = --each ] || exit 9
cat "$EACH_FILE"
SH
chmod +x "$work/resolve-anchor"

# floor ANCHOR [ENV=VALUE...] -> "<exit> <first word of stdout>"
floor() {
  local anchor="$1" rc=0 word
  shift
  env -u GITHUB_OUTPUT FLOOR_TAGS_FILE="$work/tags" RESOLVE_ANCHOR="$work/resolve-anchor" \
    EACH_FILE="$work/each" "$@" "$FLOOR" "$arch" "$anchor" > "$work/out" 2> "$work/err" || rc=$?
  word="$(awk 'NR == 1 { print $1 }' "$work/out")"
  printf '%s %s\n' "$rc" "${word:-none}"
}

: > "$work/each"
check() { # DESC WANT GOT
  if [ "$3" = "$2" ]; then
    ok "$1"
  else
    fail "$1" "got: $3, want: $2" \
      "stderr: $(tr '\n' '|' < "$work/err")" \
      "reproduce: FLOOR_TAGS_FILE=<tags> scripts/check-anchor-floor $arch <anchor>"
  fi
}

check "an anchor above the floor passes" "0 ok" "$(floor 7.3.0-1)"
check "an anchor equal to the floor passes" "0 ok" "$(floor 7.2.0-2)"
check "the floor is the highest anchor over all aliases: 7.1.0-1 < 7.2.0-2 is refused" "3 behind" "$(floor 7.1.0-1)"
check "a pkgrel revert below the floor is refused" "3 behind" "$(floor 7.2.0-1)"

printf 'https://a.example 7.2.0-1\nhttps://b.example 7.2.0-1\nhttp://c.example 7.3.0-1\nhttps://d.example -\n' > "$work/each"
check "a revert passes when 2 reachable https servers serve the lower version" "0 revert" "$(floor 7.2.0-1)"

printf 'https://a.example 7.2.0-1\nhttps://b.example -\n' > "$work/each"
check "a revert with 1 reachable https server is refused" "3 behind" "$(floor 7.2.0-1)"

printf 'https://a.example 7.2.0-1\nhttps://b.example 7.2.0-2\n' > "$work/each"
check "a revert is refused when one https server serves another version" "3 behind" "$(floor 7.2.0-1)"

: > "$work/each"
check "ALLOW_ANCHOR_DOWNGRADE=all takes the downgrade" "0 allowed" "$(floor 7.2.0-1 ALLOW_ANCHOR_DOWNGRADE=all)"
check "ALLOW_ANCHOR_DOWNGRADE that names the port takes the downgrade" "0 allowed" "$(floor 7.2.0-1 ALLOW_ANCHOR_DOWNGRADE="$other $arch")"
check "ALLOW_ANCHOR_DOWNGRADE that names another port refuses it" "3 behind" "$(floor 7.2.0-1 ALLOW_ANCHOR_DOWNGRADE="$other")"
check "ALLOW_ANCHOR_DOWNGRADE=none refuses it" "3 behind" "$(floor 7.2.0-1 ALLOW_ANCHOR_DOWNGRADE=none)"
check "ALLOW_ANCHOR_DOWNGRADE with a word that is not a port stops the check" "1 none" "$(floor 7.2.0-1 ALLOW_ANCHOR_DOWNGRADE=notaport)"

# ⛔ pacman takes a + in a version, and no tag can carry it. The leg of the
# port stops here, so the publish does not stop at that port.
check "an anchor with a + stops the check" "1 none" "$(floor 7.2.0+r3-1)"
check "an anchor that makes a tag of more than 128 characters stops the check" "1 none" \
  "$(floor "7.$(printf '%0130d' 1)-1")"

printf '%s\n' latest "$first-v2030.01.01" > "$work/tags"
check "a port with no anchor tag has no floor" "0 nofloor" "$(floor 1.0-1)"

summary
