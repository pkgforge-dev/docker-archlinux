#!/usr/bin/env bash
#
# Every command in the documentation must at least parse, and the claims the
# documentation makes about this repository must match the repository.
#
# A documented command that does not work is what generates issues. Nobody
# reports it as a documentation bug; they report the image as broken.
#
# This parses rather than executes. Most of these commands pull images, install
# packages or need a container, and a test that did all that would be a build,
# not a check. What it does catch is the class the old README shipped: a usage
# block using !# as a comment marker, where ! is bash's negation operator and
# the block cannot run at all.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

EXAMPLES="$REPO_ROOT/examples"

#---------------------------------------------------------------------------#
# 1. every shell example parses
#---------------------------------------------------------------------------#
if [ ! -d "$EXAMPLES" ]; then
  fail "examples/ exists" \
    "expected: $EXAMPLES" \
    "the examples are what stop the same question being asked repeatedly" \
    "reproduce: ls examples"
  summary
  exit 1
fi

shell_examples="$(find "$EXAMPLES" -maxdepth 1 -type f -name '*.sh' | sort)"
if [ -z "$shell_examples" ]; then
  fail "examples/ holds at least one shell example" "searched: $EXAMPLES/*.sh" \
    "reproduce: ls examples/*.sh"
else
  bad=0
  n=0
  while IFS= read -r ex; do
    [ -n "$ex" ] || continue
    n=$((n + 1))
    rel="${ex#"$REPO_ROOT/"}"
    if ! err="$(bash -n "$ex" 2>&1)"; then
      fail "$rel parses as bash" \
        "bash -n said: $(printf '%s\n' "$err" | awk 'NR == 1')" \
        "reproduce: bash -n $rel"
      bad=1
    fi
  done <<< "$shell_examples"
  if [ "$bad" -eq 0 ]; then
    ok "all $n shell examples parse as bash"
  fi
fi

#---------------------------------------------------------------------------#
# 1b. no example combines pipefail with a pipeline whose consumer exits early
#
# `cmd | head -1` under `set -o pipefail` makes head close the pipe, cmd take
# SIGPIPE, and the pipeline report 141. Under set -e the script then dies
# having done everything correctly. An example that exits non-zero teaches the
# reader that the documented commands do not work.
#---------------------------------------------------------------------------#
if [ -n "$shell_examples" ]; then
  trapped=""
  while IFS= read -r ex; do
    [ -n "$ex" ] || continue
    rel="${ex#"$REPO_ROOT/"}"
    # A `set` command enabling it, not the word appearing in a comment that
    # explains why it is not enabled.
    grep -qE '^[[:space:]]*set[[:space:]][^#]*pipefail' "$ex" || continue
    # Likewise, only real commands: a commented example of the trap is fine.
    hits="$(grep_matches '^[[:space:]]*[^#[:space:]][^#]*\|[[:space:]]*(head|tail[[:space:]]+-[0-9n]|grep[[:space:]]+-[a-zA-Z]*q)' "$ex")"
    if [ -n "$hits" ]; then
      trapped="$trapped $rel:$(printf '%s\n' "$hits" | awk -F: 'NR == 1 { print $1 }')"
    fi
  done <<< "$shell_examples"
  if [ -z "$trapped" ]; then
    ok "no example sets pipefail alongside a pipeline that exits early"
  else
    fail "no example sets pipefail alongside a pipeline that exits early" \
      "found at:$trapped" \
      "head closing the pipe makes the producer take SIGPIPE, and pipefail turns that into 141" \
      "drop pipefail in an example, or do not pipe into head" \
      "reproduce: grep -nE 'set .*pipefail' examples/*.sh"
  fi
fi

#---------------------------------------------------------------------------#
# 2. every fenced bash block in the documentation parses
#
# The block is extracted and fed to bash -n. A block that is a fragment rather
# than a script, such as a bare FROM line, is skipped by the fence language.
#---------------------------------------------------------------------------#
# ⛔ Discovered, not listed. A hardcoded list is one more place to edit when a
# document is added, and the one that gets forgotten is the new one, which is
# also the one most likely to carry a command nobody has run.
#
# HISTORY/ is excluded on purpose: it records what was measured and when, not
# what a reader is meant to run, and its blocks name paths that were scratch.
docs="$(
  printf '%s
' "$REPO_ROOT/README.md" "$REPO_ROOT/examples/README.md" "$REPO_ROOT/tests/README.md"
  if [ -d "$REPO_ROOT/docs" ]; then
    find "$REPO_ROOT/docs" -type f -name '*.md' | LC_ALL=C sort
  fi
)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

total_blocks=0
bad_blocks=0
while IFS= read -r doc; do
  [ -n "$doc" ] || continue
  [ -f "$doc" ] || continue
  rel="${doc#"$REPO_ROOT/"}"

  # Split on the fences, writing each bash block to its own file so a syntax
  # error names the block it came from. The index is appended to, and the block
  # files are namespaced by document, because this runs once per document and a
  # truncating redirect would leave only the last one.
  tag="$(printf '%s' "$rel" | tr '/.' '__')"
  awk -v out="$work" -v doc="$rel" -v tag="$tag" '
    /^```bash$/ { inblock = 1; n++; file = out "/block." tag "." n; next }
    /^```/      { if (inblock) { print file "\t" doc "\t" n >> (out "/index") }
                  inblock = 0; next }
    inblock     { print >> file }
  ' "$doc"
done <<< "$docs"

if [ -f "$work/index" ]; then
  while IFS=$'\t' read -r file doc num; do
    [ -n "$file" ] || continue
    total_blocks=$((total_blocks + 1))
    if ! err="$(bash -n "$file" 2>&1)"; then
      fail "$doc bash block $num parses" \
        "bash -n said: $(printf '%s\n' "$err" | awk 'NR == 1')" \
        "first line of the block: $(head -1 "$file")" \
        "reproduce: bash -n $file, where the block is $doc block $num"
      bad_blocks=$((bad_blocks + 1))
    fi
  done < "$work/index"
fi

if [ "$total_blocks" -eq 0 ]; then
  fail "the documentation carries at least one bash block" \
    "no \`\`\`bash fence found in README.md, examples/README.md or tests/README.md" \
    "reproduce: grep -n '\`\`\`bash' README.md examples/README.md tests/README.md"
elif [ "$bad_blocks" -eq 0 ]; then
  ok "all $total_blocks documented bash blocks parse"
fi

#---------------------------------------------------------------------------#
# 3. the README does not point at a repository that does not exist
#
# The badge pointed at github.com/pkgforge/docker-archlinux, which is a 404.
# This is checked without network by comparing against the owner the workflow
# derives GHCR from.
#---------------------------------------------------------------------------#
readme="$REPO_ROOT/README.md"
if [ -f "$readme" ]; then
  wrong="$(grep_matches 'github\.com/pkgforge/docker-archlinux' "$readme")"
  if [ -n "$wrong" ]; then
    fail "README does not link to github.com/pkgforge/docker-archlinux" \
      "found: $(printf '%s\n' "$wrong" | awk 'NR == 1')" \
      "that path is a 404, the repository is pkgforge-dev/docker-archlinux" \
      "reproduce: grep -n 'pkgforge/docker-archlinux' README.md"
  else
    ok "README links to the repository that exists"
  fi

  # Both publish targets are documented. One of them being invisible is how a
  # consumer ends up not knowing it exists.
  for needle in 'ghcr.io/pkgforge-dev/archlinux' 'pkgforge/archlinux'; do
    if grep -qF "$needle" "$readme"; then
      ok "README names the publish target $needle"
    else
      fail "README names the publish target $needle" \
        "it is a live registry and nothing in the documentation mentions it" \
        "reproduce: grep -F '$needle' README.md"
    fi
  done
fi

#---------------------------------------------------------------------------#
# 4. every tag name the README documents is one tag-names actually emits
#
# A documented tag that is never created is the same defect as a command that
# does not run.
#---------------------------------------------------------------------------#
TAGS="$REPO_ROOT/scripts/tag-names"
if [ -x "$TAGS" ] && [ -f "$readme" ]; then
  emitted="$(for a in amd64 arm64 armv7 loong64 riscv64 ppc ppc64 ppc64le; do
               "$TAGS" aliases "$a" | tr ' ' '\n'
             done | awk 'NF' | sort -u)"

  # The alias names the README lists in its tag table, taken from the backticked
  # cells rather than from prose.
  documented="$(awk '/^\| `linux\// {
                        gsub(/`/, "")
                        split($0, cells, "\\|")
                        n = split(cells[3], names, ",")
                        for (i = 1; i <= n; i++) {
                          gsub(/^[ \t]+|[ \t]+$/, "", names[i])
                          if (names[i] != "") print names[i]
                        }
                      }' "$readme" | sort -u)"

  if [ -z "$documented" ]; then
    fail "the README documents the tag names" \
      "no tag table rows matched" \
      "expected rows shaped: | \`linux/amd64\` | \`x86_64\`, \`amd64\` |" \
      "reproduce: grep -n 'linux/amd64' README.md"
  else
    missing=""
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      if ! grep -qxF "$d" <<< "$emitted"; then
        missing="$missing $d"
      fi
    done <<< "$documented"
    if [ -z "$missing" ]; then
      ok "every tag name the README documents is emitted by scripts/tag-names ($(awk 'NF' <<< "$documented" | wc -l | tr -d '[:space:]') names)"
    else
      fail "every tag name the README documents is emitted by scripts/tag-names" \
        "documented but never created:$missing" \
        "reproduce: scripts/tag-names aliases amd64"
    fi

    undocumented=""
    while IFS= read -r e; do
      [ -n "$e" ] || continue
      if ! grep -qxF "$e" <<< "$documented"; then
        undocumented="$undocumented $e"
      fi
    done <<< "$emitted"
    if [ -z "$undocumented" ]; then
      ok "every tag name scripts/tag-names emits is documented in the README"
    else
      fail "every tag name scripts/tag-names emits is documented in the README" \
        "created but undocumented:$undocumented" \
        "a published tag nobody documents is a tag nobody can rely on" \
        "reproduce: scripts/tag-names arch amd64 2026.01.01 1.0.0, and document each name in the README tag table"
    fi
  fi
fi

#---------------------------------------------------------------------------#
# 5. nothing is withheld from the image
#
# ⛔ NoExtract governs what is written to disk and not what the package database
# records, so any rule leaves pacman -Ql listing paths that are not there. A
# downstream consumer that walks a package's file list and checks each path
# broke on the first one it met. See HISTORY/noextract-reverted.md.
#---------------------------------------------------------------------------#
confs="$(find "$REPO_ROOT/rootfs" -type f -name pacman.conf | sort)"
if [ -z "$confs" ]; then
  fail "there is a shipped pacman.conf to check" \
    "searched: $REPO_ROOT/rootfs" \
    "reproduce: ls rootfs/*/etc/pacman.conf"
else
  n=0
  rules=""
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    n=$((n + 1))
    hits="$(grep_matches '^[[:space:]]*NoExtract[[:space:]]*=' "$c")"
    if [ -n "$hits" ]; then
      rules="$rules ${c#"$REPO_ROOT/"}:$(printf '%s' "$hits" | awk -F: 'NR == 1 { print $1 }')"
    fi
  done <<< "$confs"
  if [ -z "$rules" ]; then
    ok "none of the $n shipped pacman.conf files withholds any path"
  else
    fail "none of the $n shipped pacman.conf files withholds any path" \
      "found:$rules" \
      "a NoExtract rule makes pacman -Ql list paths that are not on disk" \
      "that is what broke a downstream consumer, see HISTORY/noextract-reverted.md" \
      "reproduce: grep -n '^NoExtract' rootfs/*/etc/pacman.conf"
  fi
fi

if [ -f "$readme" ]; then
  # shellcheck disable=SC2016
  # The backticks are markdown in the README, not a command substitution.
  if grep -qF 'There is no `NoExtract` rule' "$readme"; then
    ok "the README says the image withholds nothing"
  else
    fail "the README says the image withholds nothing" \
      "the sentence naming NoExtract is not there" \
      "reproduce: grep -n NoExtract README.md"
  fi
fi

summary
