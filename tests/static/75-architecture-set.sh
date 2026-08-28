#!/usr/bin/env bash
#
# One architecture set, named the same way everywhere.
#
# Adding an architecture means editing every place that names the set. Most of
# them fail silently, and most of those are a `for` loop over the same names
# inside a YAML `run:` block. Miss one and the architecture is not
# built, or has no anchor, or gets no tags, or is never looked for in the
# published index. The run stays green and publishes a release that looks
# complete and is not.
#
# So the set is established once, from the build matrix, and every other place
# is measured against it.
#
# ⛔ The sites are discovered, not listed by line number. A test that hardcodes
# the places to check becomes one more place to edit, and the next architecture
# would have to remember it too. Discovery also means a site added later is
# covered without anybody choosing to cover it.
#
# Four spellings name the same architecture and they are not interchangeable:
#
#   docker_arch   amd64         the matrix column, and the canonical name here
#   platform      linux/amd64   what buildx is handed
#   uname -m      x86_64        the tag family the organisation uses
#   OCI index     arm/v7        what imagetools prints back, where armv7 is the
#                               only one that renders with a slash
#
# The map between them is derived from `scripts/tag-names aliases` and the
# matrix platform column rather than written out again here. A third copy of
# that table would be a third thing to keep in step.
#
# ⚠ A loop over a deliberate subset carries `arch-subset:` in the comment block
# above it. That is the only escape, it shows up in the diff, and a new subset
# has to be written down rather than assumed. A marker above a loop that turns
# out to name the whole set is reported too, because an escape hatch that
# exempts nothing is one somebody will trust next time.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

WF="$REPO_ROOT/.github/workflows/build-deploy.yml"
TAGS="$REPO_ROOT/scripts/tag-names"

if [ ! -f "$WF" ]; then
  fail "the build workflow exists" "expected: $WF" \
    "every assertion in this file is measured against its matrix" \
    "reproduce: ls .github/workflows/build-deploy.yml"
  summary
  exit 1
fi

#---------------------------------------------------------------------------#
# 1. the canonical set, read from the build matrix
#
# The matrix is the authority because it is the only place that decides what is
# actually built. Everything else describes it.
#
# Read as a sequence of lines rather than parsed as YAML. This repository ships
# no YAML parser, and the image the suite also runs in has no python.
#---------------------------------------------------------------------------#
matrix_pairs() { # -> "<docker_arch>=<platform>" per entry, - when there is none
  awk '
    function val(s) {
      sub(/^[^:]*:[[:space:]]*/, "", s)
      sub(/[[:space:]]*$/, "", s)
      return s
    }
    /^[[:space:]]*-[[:space:]]+docker_arch:/ {
      if (arch != "") print arch "=" (plat == "" ? "-" : plat)
      arch = val($0); plat = ""; next
    }
    arch != "" && /^[[:space:]]*platform:/ { if (plat == "") plat = val($0) }
    END { if (arch != "") print arch "=" (plat == "" ? "-" : plat) }
  ' "$1"
}

pairs="$(matrix_pairs "$WF" | tr -d '\r')"

if [ -z "$pairs" ]; then
  fail "the build matrix names its architectures" \
    "no '- docker_arch:' entry in .github/workflows/build-deploy.yml" \
    "without it this file has nothing to measure anything against" \
    "reproduce: grep -n 'docker_arch:' .github/workflows/build-deploy.yml"
  summary
  exit 1
fi

ARCHES="$(awk -F= 'NF { print $1 }' <<< "$pairs" | LC_ALL=C sort)"
n_arch="$(awk 'NF' <<< "$ARCHES" | wc -l | tr -d '[:space:]')"

dupes="$(printf '%s\n' "$ARCHES" | uniq -d | tr '\n' ' ')"
no_platform="$(awk -F= '$2 == "-" { print $1 }' <<< "$pairs" | tr '\n' ' ')"

if [ -n "$(printf '%s' "$dupes" | tr -d '[:space:]')" ]; then
  fail "each architecture appears once in the build matrix" \
    "named more than once: $dupes" \
    "two entries for one architecture build it twice and race for its tags" \
    "reproduce: grep -n 'docker_arch:' .github/workflows/build-deploy.yml"
elif [ -n "$(printf '%s' "$no_platform" | tr -d '[:space:]')" ]; then
  fail "every matrix entry carries a platform" \
    "no platform: line for: $no_platform" \
    "buildx is handed the platform, so an entry without one builds the runner's own architecture" \
    "reproduce: grep -n -A2 'docker_arch:' .github/workflows/build-deploy.yml"
else
  ok "the build matrix names $n_arch architectures: $(printf '%s' "$ARCHES" | tr '\n' ' ')"
fi

#---------------------------------------------------------------------------#
# 2. the spellings, derived from the two places that already hold them
#---------------------------------------------------------------------------#
TOKENS=""

add_token() {
  TOKENS="$TOKENS$1=$2
"
}

token_arch() { # <token> -> docker arch, empty when the token is not one
  awk -F= -v t="$1" 'NF && $1 == t { print $2; exit }' <<< "$TOKENS"
}

tagnames_broken=""
while IFS= read -r arch; do
  [ -n "$arch" ] || continue
  add_token "$arch" "$arch"
  [ -x "$TAGS" ] || continue
  # A die here is the loud failure section 4 reports. It must not stop this
  # file, or one unknown architecture would take every later assertion with it
  # and the log would name the wrong problem.
  if alias_out="$("$TAGS" aliases "$arch" 2>&1)"; then
    alias_list="$(printf '%s\n' "$alias_out" | tr ' ' '\n' | tr -d '\r' | awk 'NF')"
    while IFS= read -r a; do
      [ -n "$a" ] || continue
      add_token "$a" "$arch"
    done <<< "$alias_list"
  else
    tagnames_broken="$tagnames_broken $arch"
  fi
done <<< "$ARCHES"

# The OCI spelling, which is the platform with linux/ taken off. armv7 is the
# only one where that leaves a slash behind.
while IFS='=' read -r a p; do
  [ -n "$a" ] || continue
  [ "$p" != "-" ] || continue
  add_token "$p" "$a"
  add_token "${p#linux/}" "$a"
done <<< "$pairs"

n_tokens="$(awk 'NF' <<< "$TOKENS" | LC_ALL=C sort -u | wc -l | tr -d '[:space:]')"
diag "$n_tokens spellings map onto $n_arch architectures"

#---------------------------------------------------------------------------#
# 3. every architecture loop names the whole set
#
# A loop counts as an architecture loop when at least one word in its list is a
# known spelling. Every other word then has to be one too: a list mixing an
# architecture with something else is reported rather than guessed at, because
# guessing is how a silent hole gets made.
#---------------------------------------------------------------------------#
scan_files() {
  local d
  for d in scripts tests .github bootstrap examples; do
    if [ -d "$REPO_ROOT/$d" ]; then
      find "$REPO_ROOT/$d" -type f
    fi
  done
  if [ -f "$REPO_ROOT/Dockerfile" ]; then
    printf '%s\n' "$REPO_ROOT/Dockerfile"
  fi
}

# loops FILE -> "<line>|<subset|code>|<closed|open>|<word list>" per for loop
#
# The list ends at the first ; or at the do that follows it. A list that runs
# onto the next line is reported open, and the words read so far are passed on
# anyway: they are what says whether this loop is about architectures at all.
# Sending a placeholder instead would make the loop look like no architecture
# was named, and the caller would skip the very line it needs to complain about.
#
# The marker counts anywhere in the unbroken run of comment lines above the
# loop, or on the loop's own line. Requiring it on one exact line would mean a
# reason long enough to need two lines had to end on the keyword.
loops() {
  awk '
    {
      code = $0
      is_comment = ($0 ~ /^[[:space:]]*#/)
      sub(/^[[:space:]]*#.*$/, "", code)
      if (match(code, /(^|[^[:alnum:]_])for[[:space:]]+[A-Za-z_][A-Za-z_0-9]*[[:space:]]+in[[:space:]]+/)) {
        rest = substr(code, RSTART + RLENGTH)
        ends = 0
        if (match(rest, /;/)) { rest = substr(rest, 1, RSTART - 1); ends = 1 }
        if (match(rest, /(^|[[:space:]])do([[:space:]]|$)/)) { rest = substr(rest, 1, RSTART - 1); ends = 1 }
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", rest)
        marked = (block || $0 ~ /arch-subset:/)
        if (rest != "") printf "%d|%s|%s|%s\n", NR, (marked ? "subset" : "code"), (ends ? "closed" : "open"), rest
      }
      # A blank line or any code ends the comment block, so a marker cannot
      # reach past the thing it was written above.
      if (is_comment) { if ($0 ~ /arch-subset:/) block = 1 } else { block = 0 }
    }
  ' "$1"
}

want="$(printf '%s\n' "$ARCHES" | awk 'NF' | LC_ALL=C sort -u)"
n_loops=0

while IFS= read -r file; do
  [ -n "$file" ] || continue
  rel="${file#"$REPO_ROOT/"}"
  found="$(loops "$file" | tr -d '\r')"
  [ -n "$found" ] || continue

  while IFS='|' read -r lineno mark closure words; do
    [ -n "$lineno" ] || continue

    words_nl="$(printf '%s' "$words" | tr '[:space:]' '\n' | awk 'NF')"
    got=""
    unknown=""
    n_known=0
    while IFS= read -r w; do
      [ -n "$w" ] || continue
      a="$(token_arch "$w")"
      if [ -n "$a" ]; then
        n_known=$((n_known + 1))
        got="$got$a
"
      else
        unknown="$unknown $w"
      fi
    done <<< "$words_nl"

    # Not an architecture loop at all. Every other for loop in the tree is none
    # of this file's business.
    [ "$n_known" -gt 0 ] || continue
    n_loops=$((n_loops + 1))

    got_set="$(printf '%s\n' "$got" | awk 'NF' | LC_ALL=C sort -u)"

    if [ "$closure" = "open" ]; then
      # Checked before the unknown words, because a continuation character is
      # itself one and saying so would name the wrong problem.
      fail "$rel:$lineno keeps its architecture list on one line" \
        "the list is not closed by ; or do on this line, so only part of it can be read here" \
        "read so far: $(printf '%s' "$got_set" | tr '\n' ' ')" \
        "a list this scan can only half read is one it would pass without checking" \
        "reproduce: sed -n '${lineno},$((lineno + 3))p' $rel"
    elif [ -n "$(printf '%s' "$unknown" | tr -d '[:space:]')" ]; then
      fail "$rel:$lineno names architectures and nothing else" \
        "not a spelling of any architecture in the matrix:$unknown" \
        "either that is an architecture the matrix dropped, or this loop is not about architectures" \
        "reproduce: sed -n '${lineno}p' $rel"
    elif [ "$got_set" = "$want" ]; then
      if [ "$mark" = "subset" ]; then
        fail "$rel:$lineno is marked a subset and is one" \
          "it carries the marker above it and names the whole set: $(printf '%s' "$got_set" | tr '\n' ' ')" \
          "an exemption that exempts nothing is one somebody will trust next time" \
          "reproduce: sed -n '$(( lineno > 6 ? lineno - 6 : 1 )),${lineno}p' $rel"
      else
        ok "$rel:$lineno names the whole architecture set"
      fi
    elif [ "$mark" = "subset" ]; then
      ok "$rel:$lineno is a marked subset: $(printf '%s' "$got_set" | tr '\n' ' ')"
    else
      missing="$(LC_ALL=C comm -23 <(printf '%s\n' "$want") <(printf '%s\n' "$got_set") | tr '\n' ' ')"
      extra="$(LC_ALL=C comm -13 <(printf '%s\n' "$want") <(printf '%s\n' "$got_set") | tr '\n' ' ')"
      fail "$rel:$lineno names the whole architecture set" \
        "missing: ${missing:-none}" \
        "not in the build matrix: ${extra:-none}" \
        "the matrix names: $(printf '%s' "$want" | tr '\n' ' ')" \
        "if it is meant to cover fewer, write the reason in a comment above it and mark that comment" \
        "reproduce: sed -n '${lineno}p' $rel"
    fi
  done <<< "$found"
done <<< "$(scan_files | LC_ALL=C sort)"

# A scanner that matches nothing passes every assertion it never made.
if [ "$n_loops" -eq 0 ]; then
  fail "the scan found the architecture loops" \
    "no for loop over architecture names was found anywhere in the tree" \
    "there are known to be several, so finding none means this scan stopped working" \
    "reproduce: grep -rnE 'for[[:space:]]+[A-Za-z_]+[[:space:]]+in[[:space:]]+[^;]*amd64' scripts tests .github"
else
  diag "checked $n_loops architecture loop(s)"
fi

#---------------------------------------------------------------------------#
# 4. scripts/tag-names knows exactly this set
#
# An unknown architecture is a die there, which is loud. The reverse is not: an
# alias table still carrying an architecture the matrix dropped would keep
# minting tags for something nothing builds.
#---------------------------------------------------------------------------#
if [ ! -x "$TAGS" ]; then
  fail "scripts/tag-names is executable" "expected: $TAGS" \
    "reproduce: git update-index --chmod=+x scripts/tag-names"
elif [ -n "$(printf '%s' "$tagnames_broken" | tr -d '[:space:]')" ]; then
  fail "scripts/tag-names has an alias set for every matrix architecture" \
    "it exits non-zero for:$tagnames_broken" \
    "the publish job asks it for the tags of every architecture it built" \
    "reproduce: scripts/tag-names aliases${tagnames_broken}"
else
  labels="$(awk '
    /aliases_for\(\)/ { in_fn = 1; next }
    in_fn && /^}/ { in_fn = 0 }
    in_fn && match($0, /^[[:space:]]*[A-Za-z0-9_-]+\)/) {
      lbl = substr($0, RSTART, RLENGTH - 1)
      gsub(/[[:space:]]/, "", lbl)
      print lbl
    }
  ' "$TAGS" | tr -d '\r' | LC_ALL=C sort -u)"

  if [ -z "$labels" ]; then
    fail "the alias table in scripts/tag-names can be read" \
      "no case label found inside aliases_for" \
      "reproduce: sed -n '/aliases_for()/,/^}/p' scripts/tag-names"
  elif [ "$labels" = "$want" ]; then
    ok "scripts/tag-names has an alias set for exactly the $n_arch matrix architectures"
  else
    only_matrix="$(LC_ALL=C comm -23 <(printf '%s\n' "$want") <(printf '%s\n' "$labels") | tr '\n' ' ')"
    only_table="$(LC_ALL=C comm -13 <(printf '%s\n' "$want") <(printf '%s\n' "$labels") | tr '\n' ' ')"
    fail "scripts/tag-names has an alias set for exactly the $n_arch matrix architectures" \
      "built and has no alias set: ${only_matrix:-none}" \
      "has an alias set and is not built: ${only_table:-none}" \
      "reproduce: sed -n '/aliases_for()/,/^}/p' scripts/tag-names"
  fi
fi

#---------------------------------------------------------------------------#
# 5. the gen-mirrorlist usage string
#
# An architecture missing from the usage string still works when it is named
# directly, so nothing fails: it is undiscoverable, and `gen-mirrorlist all`
# skips it. The freshness workflow runs exactly that command.
#---------------------------------------------------------------------------#
GM="$REPO_ROOT/scripts/gen-mirrorlist"
if [ ! -f "$GM" ]; then
  fail "scripts/gen-mirrorlist exists" "expected: $GM" \
    "reproduce: ls scripts/gen-mirrorlist"
else
  usage="$(awk 'match($0, /gen-mirrorlist <[^>]*>/) {
                  s = substr($0, RSTART, RLENGTH)
                  sub(/^[^<]*</, "", s); sub(/>$/, "", s)
                  print s; exit
                }' "$GM" | tr -d '\r')"
  if [ -z "$usage" ]; then
    fail "the gen-mirrorlist usage string names the architectures it takes" \
      "no 'gen-mirrorlist <...>' usage string found" \
      "reproduce: grep -n 'usage:' scripts/gen-mirrorlist"
  else
    named="$(printf '%s' "$usage" | tr '|' '\n' | awk 'NF && $0 != "all"' | LC_ALL=C sort -u)"
    if [ "$named" = "$want" ]; then
      ok "the gen-mirrorlist usage string names exactly the $n_arch matrix architectures"
    else
      fail "the gen-mirrorlist usage string names exactly the $n_arch matrix architectures" \
        "it says: <$usage>" \
        "the matrix names: $(printf '%s' "$want" | tr '\n' ' ')" \
        "reproduce: grep -n 'usage: scripts/gen-mirrorlist' scripts/gen-mirrorlist"
    fi
  fi
fi

#---------------------------------------------------------------------------#
# 6. the per architecture files
#
# 40-mirrors-reachable.sh and 45-pacman-conf-shape.sh both discover their work
# by walking rootfs/. That makes them loud about a file that is wrong and
# silent about one that is not there at all: a new architecture with no rootfs
# directory leaves them checking one file fewer than it should, and passing.
#---------------------------------------------------------------------------#
required_paths() { # arch -> the files that architecture must have
  printf 'rootfs/%s/etc/pacman.conf\n' "$1"
  printf 'rootfs/%s/etc/pacman.d/mirrorlist\n' "$1"
  printf 'bootstrap/%s/etc/bootstrap-packages.txt\n' "$1"
  printf 'mirrors/%s.anchors\n' "$1"
}

while IFS= read -r arch; do
  [ -n "$arch" ] || continue
  absent=""
  n_paths=0
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    n_paths=$((n_paths + 1))
    [ -f "$REPO_ROOT/$p" ] || absent="$absent $p"
  done <<< "$(required_paths "$arch")"

  if [ -z "$(printf '%s' "$absent" | tr -d '[:space:]')" ]; then
    ok "$arch has all $n_paths of its per architecture files"
  else
    fail "$arch has all $n_paths of its per architecture files" \
      "not in the tree:$absent" \
      "the build matrix names $arch, so the build will go looking for these" \
      "reproduce: ls$absent"
  fi
done <<< "$ARCHES"

# The other direction. A directory for an architecture the matrix does not name
# is either one that was removed and left files behind, or one somebody started
# adding and did not finish.
#
# any and keyrings are shared by every architecture and are not one.
SHARED="any
keyrings"

orphans=""
for d in rootfs bootstrap; do
  [ -d "$REPO_ROOT/$d" ] || continue
  while IFS= read -r sub; do
    [ -n "$sub" ] || continue
    name="$(basename "$sub")"
    if grep -qxF "$name" <<< "$SHARED"; then
      continue
    fi
    if grep -qxF "$name" <<< "$ARCHES"; then
      continue
    fi
    orphans="$orphans $d/$name"
  done <<< "$(find "$REPO_ROOT/$d" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort)"
done

if [ -z "$(printf '%s' "$orphans" | tr -d '[:space:]')" ]; then
  ok "no rootfs or bootstrap directory belongs to an architecture the matrix does not build"
else
  fail "no rootfs or bootstrap directory belongs to an architecture the matrix does not build" \
    "not in the matrix:$orphans" \
    "either the matrix lost an architecture or these files outlived one" \
    "reproduce: ls -d$orphans"
fi

#---------------------------------------------------------------------------#
# 7. the tag family assertions cover every architecture
#
# 60-tag-families.sh checks one alias count per architecture, by name. Adding
# an architecture without adding its line there leaves that file passing while
# saying nothing at all about the new one.
#---------------------------------------------------------------------------#
TF="$REPO_ROOT/tests/static/60-tag-families.sh"
if [ ! -f "$TF" ]; then
  fail "tests/static/60-tag-families.sh exists" "expected: $TF" \
    "reproduce: ls tests/static/60-tag-families.sh"
else
  covered="$(awk '/^expect_alias_count[[:space:]]/ { print $2 }' "$TF" | tr -d '\r' | awk 'NF' | LC_ALL=C sort -u)"
  if [ -z "$covered" ]; then
    fail "60-tag-families.sh checks an alias count per architecture" \
      "no expect_alias_count call found" \
      "reproduce: grep -n expect_alias_count tests/static/60-tag-families.sh"
  elif [ "$covered" = "$want" ]; then
    ok "60-tag-families.sh checks an alias count for all $n_arch architectures"
  else
    uncovered="$(LC_ALL=C comm -23 <(printf '%s\n' "$want") <(printf '%s\n' "$covered") | tr '\n' ' ')"
    stale="$(LC_ALL=C comm -13 <(printf '%s\n' "$want") <(printf '%s\n' "$covered") | tr '\n' ' ')"
    fail "60-tag-families.sh checks an alias count for all $n_arch architectures" \
      "built and unchecked there: ${uncovered:-none}" \
      "checked there and not built: ${stale:-none}" \
      "reproduce: grep -n expect_alias_count tests/static/60-tag-families.sh"
  fi
fi

summary
