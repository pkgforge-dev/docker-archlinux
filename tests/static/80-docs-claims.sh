#!/usr/bin/env bash
#
# The documents parse, and agree with the tree.
#
#   1. Each examples/*.sh parses with bash -n. No example sets pipefail and
#      pipes into a reader that stops early.
#   2. Each fenced bash block of each Markdown file of the tree parses with
#      bash -n. A fence may be indented, as in a list item.
#   3. The architecture table of README.md has one row for each port of
#      scripts/ports, in the order of scripts/ports list: the port, its
#      platform, its aliases in order, and its distribution as a link to
#      its homepage.
#   4. README.md shows the status badge of each port.
#   5. README.md names both images of build-deploy.yml (the env GHCR_IMAGE
#      and HUB_IMAGE), and no link to github.com/pkgforge/docker-archlinux.
#   6. No shipped pacman.conf has a NoExtract rule.
#   7. The history directory is not in the tree, and no document names it.
#   8. Each localhost/ image that a document names is made by a bash block
#      of a document. Each file that such a block builds from is in the tree.
#      A build file outside examples/ pins each FROM by digest, with its
#      "# tag:" marker at most 3 lines above.
#   9. No example and no bash block installs a package with pacman -Sy and
#      no -u: that is a partial upgrade. A keyring package alone is allowed.
#  10. The keyring block of docs/bootstrap-with-pacman-static.md stops on a
#      sha256 mismatch, and keyring then has no value. A stand-in pac and
#      sha256sum run it.
#  11. examples/06 gives the SBOM package count of each platform, with a
#      stand-in docker.
#  12. The column needs of examples/README.md names each tool (docker with
#      buildx, podman, jq, curl, gh) that an example runs.
#  13. Each script and build file that a source cell of docs/measurements.md
#      runs is in the tree.
#  14. No sentence of a Markdown file has more than 25 words. Inline code is
#      one word. A sentence ends at . ! ? : or ;. A table cell, a list item
#      and a heading end one too. Fenced blocks are not read.
#
# The test reads structure: fences, table cells, workflow keys, config
# directives and commands. It runs blocks and examples with stand-ins. It
# matches no sentence.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

EXAMPLES="$REPO_ROOT/examples"
README="$REPO_ROOT/README.md"
PORTS="$REPO_ROOT/scripts/ports"
WORKFLOW="$REPO_ROOT/.github/workflows/build-deploy.yml"

work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

#---------------------------------------------------------------------------#
# The files: tracked and new files from git, or every file when there is no
# git. tests/fixtures holds data, not documents.
#---------------------------------------------------------------------------#
rc=0
if git -C "$REPO_ROOT" rev-parse --git-dir > "$work/gitdir" 2> "$work/git.err"; then
  git -C "$REPO_ROOT" ls-files -z -co --exclude-standard > "$work/files0" || rc=$?
else
  (cd "$REPO_ROOT" && find . -path ./.git -prune -o -type f -print0) > "$work/files0" || rc=$?
fi
if [ "$rc" -ne 0 ]; then
  fail "the files of the tree can be listed" "exit $rc" \
    "reproduce: git ls-files -co --exclude-standard"
  summary
  exit 1
fi
: > "$work/markdown"
: > "$work/documents"
while IFS= read -r -d '' f; do
  f="${f#./}"
  case "$f" in tests/fixtures/*) continue ;; esac
  [ -f "$REPO_ROOT/$f" ] || continue
  case "$f" in
    *.md)
      printf '%s\n' "$f" >> "$work/markdown"
      printf '%s\n' "$f" >> "$work/documents"
      ;;
    examples/*) printf '%s\n' "$f" >> "$work/documents" ;;
  esac
done < "$work/files0"

#---------------------------------------------------------------------------#
# 1. Each shell example parses, and none combines pipefail with a reader
#    that stops early.
#
# `cmd | head -1` under pipefail: head closes the pipe, cmd gets SIGPIPE, and
# the pipeline gives 141. Under set -e the example then stops, after it did
# its work, with a status that says it failed.
#---------------------------------------------------------------------------#
if [ ! -d "$EXAMPLES" ]; then
  fail "examples/ is in the tree" \
    "expected: $EXAMPLES" \
    "reproduce: ls examples"
  summary
  exit 1
fi

shell_examples="$(find "$EXAMPLES" -maxdepth 1 -type f -name '*.sh' | LC_ALL=C sort)"
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
    ok "each of the $n shell examples parses as bash"
  fi

  trapped=""
  while IFS= read -r ex; do
    [ -n "$ex" ] || continue
    rel="${ex#"$REPO_ROOT/"}"
    # A set command that turns pipefail on, not the word in a comment.
    grep -qE '^[[:space:]]*set[[:space:]][^#]*pipefail' "$ex" || continue
    # A command, not a commented example of the shape.
    hits="$(grep_matches '^[[:space:]]*[^#[:space:]][^#]*\|[[:space:]]*(head|tail[[:space:]]+-[0-9n]|grep[[:space:]]+-[a-zA-Z]*q)' "$ex")"
    if [ -n "$hits" ]; then
      trapped="$trapped $rel:$(printf '%s\n' "$hits" | awk -F: 'NR == 1 { print $1 }')"
    fi
  done <<< "$shell_examples"
  if [ -z "$trapped" ]; then
    ok "no example sets pipefail and pipes into a reader that stops early"
  else
    fail "no example sets pipefail and pipes into a reader that stops early" \
      "found at:$trapped" \
      "the reader closes the pipe, the producer gets SIGPIPE, and pipefail makes that status 141" \
      "reproduce: grep -nE 'set .*pipefail' examples/*.sh, then read each pipeline of those files"
  fi
fi

#---------------------------------------------------------------------------#
# 2. Each fenced bash block of each Markdown file parses.
#
# The block goes to a file of its own, so a syntax error names its block.
# The indent of the fence is removed from each line of the block.
#---------------------------------------------------------------------------#
mkdir -p "$work/blocks"
: > "$work/index"
n_docs=0
while IFS= read -r doc; do
  [ -n "$doc" ] || continue
  n_docs=$((n_docs + 1))
  tag="$(printf '%s' "$doc" | tr '/.' '__')"
  awk -v out="$work/blocks" -v doc="$doc" -v tag="$tag" -v idx="$work/index" '
    !inb && /^[ \t]*```bash[ \t]*$/ {
      inb = 1; n++; ind = index($0, "`") - 1
      file = out "/" tag "." n
      printf "" > file
      next
    }
    inb && /^[ \t]*```/ {
      close(file); print file "\t" doc "\t" n >> idx; inb = 0; next
    }
    inb {
      line = $0
      if (ind > 0 && substr(line, 1, ind) ~ /^[ \t]*$/) line = substr(line, ind + 1)
      print line >> file
    }
    END { if (inb) { close(file); print file "\t" doc "\t" n " (no closing fence)" >> idx } }
  ' "$REPO_ROOT/$doc"
done < "$work/markdown"

total_blocks=0
bad_blocks=()
while IFS=$'\t' read -r file doc num; do
  [ -n "$file" ] || continue
  total_blocks=$((total_blocks + 1))
  if ! err="$(bash -n "$file" 2>&1)"; then
    bad_blocks+=("$doc, bash block $num: $(printf '%s\n' "$err" | awk 'NR == 1')")
  fi
done < "$work/index"

if [ "$total_blocks" -eq 0 ]; then
  fail "the documents have at least one fenced bash block" \
    "no fence of the shape \`\`\`bash in $n_docs Markdown files" \
    "reproduce: git grep -n '^ *\`\`\`bash' -- '*.md'"
elif [ "${#bad_blocks[@]}" -eq 0 ]; then
  ok "each of the $total_blocks fenced bash blocks of $n_docs Markdown files parses"
else
  fail "each fenced bash block of the Markdown files parses" \
    "${bad_blocks[@]}" \
    "reproduce: copy the block into a file, then bash -n FILE"
fi

#---------------------------------------------------------------------------#
# 3. The architecture table of README.md is the port table.
#
# A row of the table: | `PORT` | `PLATFORM` | `ALIAS`, `ALIAS` | [DISTRIBUTION](HOMEPAGE) |
# The row of a port is read from scripts/ports, so the failure gives the row
# to write.
#---------------------------------------------------------------------------#
if [ ! -f "$README" ]; then
  fail "README.md is in the tree" "reproduce: ls README.md"
  summary
  exit 1
fi
if [ ! -x "$PORTS" ]; then
  fail "scripts/ports is executable" "reproduce: ls -l scripts/ports"
  summary
  exit 1
fi

mapfile -t ARCHES < <("$PORTS" list)

awk '
  /^\|[ \t]*`[^`]+`[ \t]*\|[ \t]*`linux\// {
    split($0, c, "|")
    for (i = 2; i <= 5; i++) gsub(/^[ \t]+|[ \t]+$/, "", c[i])
    port = c[2]; gsub(/`/, "", port)
    plat = c[3]; gsub(/`/, "", plat)
    tags = c[4]; gsub(/`/, "", tags); gsub(/[ \t]*,[ \t]*/, " ", tags)
    print port "|" plat "|" tags "|" c[5]
  }' "$README" > "$work/rows"
mapfile -t ROWS < "$work/rows"

# row_of ARCH -> the row that README.md must have for ARCH
row_of() {
  local a="$1" aliases
  aliases="$("$PORTS" aliases "$a" | awk 'NF { printf "%s%s", sep, $0; sep = " " }')"
  printf '%s|%s|%s|[%s](%s)\n' "$a" "$("$PORTS" get "$a" platform)" "$aliases" \
    "$("$PORTS" get "$a" distribution)" "$("$PORTS" get "$a" homepage)"
}

if [ "${#ROWS[@]}" -eq 0 ]; then
  fail "README.md has an architecture table" \
    "no row of the shape | \`PORT\` | \`linux/...\` | ... |" \
    "the first row to write: $(row_of "${ARCHES[0]}" | awk -F'|' '{ printf "| `%s` | `%s` | `%s` | %s |", $1, $2, $3, $4 }')" \
    "reproduce: scripts/ports json"
else
  check_eq "README.md has one architecture row for each port of scripts/ports" \
    "${#ARCHES[@]}" "${#ROWS[@]}" "scripts/ports list; grep -n '^| \`' README.md"
  i=0
  for a in "${ARCHES[@]}"; do
    want="$(row_of "$a")"
    got="${ROWS[$i]:-none}"
    check_eq "README.md architecture row $((i + 1)) is $a: port, platform, aliases and distribution" \
      "$want" "$got" "scripts/ports json $a"
    i=$((i + 1))
  done
fi

#---------------------------------------------------------------------------#
# 4. README.md shows the status badge of each port.
#---------------------------------------------------------------------------#
no_badge=""
for a in "${ARCHES[@]}"; do
  grep -qF "badges/$a.svg" "$README" || no_badge="$no_badge $a"
done
if [ -z "$no_badge" ]; then
  ok "README.md shows the badge of each of the ${#ARCHES[@]} ports"
else
  fail "README.md shows the badge of each port" \
    "no badges/<arch>.svg for:$no_badge" \
    "scripts/status-render writes badges/<arch>.svg for each port of scripts/ports" \
    "reproduce: grep -n 'badges/' README.md"
fi

#---------------------------------------------------------------------------#
# 5. README.md names both images that build-deploy.yml publishes.
#---------------------------------------------------------------------------#
wrong="$(grep_matches 'github\.com/pkgforge/docker-archlinux' "$README")"
if [ -z "$wrong" ]; then
  ok "README.md has no link to github.com/pkgforge/docker-archlinux"
else
  fail "README.md has no link to github.com/pkgforge/docker-archlinux" \
    "found: $(printf '%s\n' "$wrong" | awk 'NR == 1')" \
    "the repository is pkgforge-dev/docker-archlinux" \
    "reproduce: grep -n 'github.com/pkgforge/docker-archlinux' README.md"
fi

if need_tool yq jq; then
  rc=0
  yaml_json "$WORKFLOW" > "$work/build.json" 2> "$work/build.err" || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "build-deploy.yml reads as YAML" "$(tr '\n' ' ' < "$work/build.err")" \
      "reproduce: yq . .github/workflows/build-deploy.yml"
  else
    ghcr="$(jq -r '.env.GHCR_IMAGE // ""' "$work/build.json")"
    hub="$(jq -r '.env.HUB_IMAGE // ""' "$work/build.json")"
    if [ -z "$ghcr" ] || [ -z "$hub" ]; then
      fail "build-deploy.yml sets the env GHCR_IMAGE and HUB_IMAGE" \
        "GHCR_IMAGE: '$ghcr', HUB_IMAGE: '$hub'" \
        "reproduce: yq .env .github/workflows/build-deploy.yml"
    else
      # The owner of GHCR_IMAGE is an expression; the README names the owner.
      ghcr_re="$(printf '%s' "$ghcr" | sed -e 's/[.]/[.]/g' -e 's/[$][{][{][^}]*[}][}]/[a-z0-9-]+/g')"
      if [ -n "$(grep_matches "$ghcr_re" "$README")" ]; then
        ok "README.md names the GHCR image ($ghcr)"
      else
        fail "README.md names the GHCR image" \
          "build-deploy.yml: $ghcr; pattern: $ghcr_re" \
          "reproduce: grep -nE '$ghcr_re' README.md"
      fi
      if grep -qF "$hub" "$README"; then
        ok "README.md names the Docker Hub image ($hub)"
      else
        fail "README.md names the Docker Hub image" \
          "build-deploy.yml: $hub" \
          "reproduce: grep -nF '$hub' README.md"
      fi
    fi
  fi
fi

#---------------------------------------------------------------------------#
# 6. No shipped pacman.conf withholds a path.
#
# ⛔ NoExtract changes what is written to disk, not what the package database
# records. With a rule, pacman -Ql lists paths that are not on disk, and a
# consumer that checks each path of a file list fails.
#---------------------------------------------------------------------------#
confs="$(find "$REPO_ROOT/rootfs" -type f -name pacman.conf | LC_ALL=C sort)"
if [ -z "$confs" ]; then
  fail "the tree has a shipped pacman.conf" \
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
      rules="$rules ${c#"$REPO_ROOT/"}:$(printf '%s\n' "$hits" | awk -F: 'NR == 1 { print $1 }')"
    fi
  done <<< "$confs"
  if [ -z "$rules" ]; then
    ok "none of the $n shipped pacman.conf files has a NoExtract rule"
  else
    fail "none of the $n shipped pacman.conf files has a NoExtract rule" \
      "found:$rules" \
      "a NoExtract rule makes pacman -Ql list paths that are not on disk" \
      "reproduce: grep -n '^NoExtract' rootfs/*/etc/pacman.conf"
  fi
fi

#---------------------------------------------------------------------------#
# 7. The history directory is gone, and no document names it. The pattern is
#    a bracket expression, so this file does not name it.
#---------------------------------------------------------------------------#
hist_dir="$REPO_ROOT/HISTORY"
if [ -e "$hist_dir" ]; then
  fail "the history directory is not in the tree" \
    "found: $hist_dir" \
    "its facts are in docs/; the branch history-archive keeps the old history" \
    "reproduce: ls -d HISTORY"
else
  ok "the history directory is not in the tree"
fi

named=""
while IFS= read -r doc; do
  [ -n "$doc" ] || continue
  hits="$(grep_matches 'HISTORY[/]' "$REPO_ROOT/$doc")"
  if [ -n "$hits" ]; then
    named="$named $doc:$(printf '%s\n' "$hits" | awk -F: 'NR == 1 { print $1 }')"
  fi
done < "$work/documents"
if [ -z "$named" ]; then
  ok "no document names the history directory ($(awk 'END { print NR + 0 }' "$work/documents") files)"
else
  fail "no document names the history directory" \
    "found at:$named" \
    "state the fact in docs/, and remove the reference" \
    "reproduce: git grep -nE 'HISTORY[/]' -- '*.md' examples"
fi

#---------------------------------------------------------------------------#
# Helpers of sections 8 to 10, as awk programs.
#
# join.awk: one logical line per output line, as N<TAB>TEXT. A line that
# ends in a backslash goes on in the next line. N is its first line.
#---------------------------------------------------------------------------#
cat > "$work/join.awk" <<'EOF'
{
  line = $0
  if (open) text = text " " line
  else { text = line; start = FNR }
  if (line ~ /\\[ \t]*$/) { sub(/\\[ \t]*$/, "", text); open = 1; next }
  open = 0
  print start "\t" text
}
END { if (open) print start "\t" text }
EOF

# made.awk reads the logical lines of a bash block. It prints:
#   made REF   for each image that a docker or podman command makes
#              (build -t, import, tag)
#   file PATH  for each build file (build -f)
# A REF with no tag gets :latest.
cat > "$work/made.awk" <<'EOF'
function norm(r) { if (r !~ /:[^\/]*$/) r = r ":latest"; return r }
{
  t = $0
  sub(/^[0-9]+\t/, "", t)
  if (t ~ /^[ \t]*#/) next
  gsub(/["']/, "", t)
  sub(/^[ \t]+/, "", t)
  sub(/[ \t]+$/, "", t)
  n = split(t, w, /[ \t]+/)
  rt = 0; build = 0; made = 0
  for (i = 1; i <= n; i++) {
    if (w[i] ~ /(^|\/)(docker|podman|buildah)$/) rt = 1
    if (!rt) continue
    if (w[i] == "build") build = 1
    if (w[i] == "import" || w[i] == "tag") made = 1
    if (build && (w[i] == "-t" || w[i] == "--tag") && i < n) print "made " norm(w[i + 1])
    if (build && w[i] ~ /^--tag=/) { r = w[i]; sub(/^--tag=/, "", r); print "made " norm(r) }
    if (build && (w[i] == "-f" || w[i] == "--file") && i < n) print "file " w[i + 1]
  }
  if (rt && made && n > 0) print "made " norm(w[n])
}
EOF

# refs.awk: each localhost/NAME[:TAG] of a file, as DOC:LINE<TAB>NAME:TAG.
cat > "$work/refs.awk" <<'EOF'
BEGIN { re = "localhost/[A-Za-z0-9][A-Za-z0-9._/-]*(:[A-Za-z0-9._-]+)?" }
{
  s = $0
  while (match(s, re)) {
    r = substr(s, RSTART, RLENGTH)
    sub(/[.]+$/, "", r)
    if (r !~ /:[^\/]*$/) r = r ":latest"
    print doc ":" FNR "\t" r
    s = substr(s, RSTART + RLENGTH)
  }
}
EOF

# pins.awk: each FROM of a build file that is not scratch, not an earlier
# stage, and not NAME:TAG@sha256:<64 hex> under a "# tag: TAG" line at most
# 3 lines above.
cat > "$work/pins.awk" <<'EOF'
{ line[FNR] = $0 }
toupper($1) == "FROM" {
  img = ""
  for (i = 2; i <= NF; i++) if (substr($i, 1, 2) != "--") { img = $i; break }
  good = (img == "scratch" || (img in stage))
  if (!good && img ~ /^[^@]+:[^:@\/]+@sha256:[0-9a-f]+$/ && length(img) - index(img, "@sha256:") - 7 == 64) {
    tag = img
    sub(/@sha256:.*/, "", tag)
    sub(/.*:/, "", tag)
    for (k = FNR - 1; k >= 1 && k >= FNR - 3; k--) {
      m = line[k]
      if (m !~ /^[ \t]*#[ \t]*tag:/) continue
      sub(/^[ \t]*#[ \t]*tag:[ \t]*/, "", m)
      sub(/[ \t]+$/, "", m)
      if (m == tag) good = 1
    }
  }
  for (i = 2; i < NF; i++) if (toupper($i) == "AS") stage[$(i + 1)] = 1
  if (!good) print FILENAME ":" FNR ": " $0
}
EOF

# sy.awk reads logical lines. It prints the number of each line with a
# pacman call that has S and y and no u in its operation. The call must also
# name a package that is not a keyring.
cat > "$work/sy.awk" <<'EOF'
BEGIN {
  split("config root dbpath cachedir hookdir gpgdir logfile arch print-format overwrite assume-installed ignore ignoregroup sysroot color", v, " ")
  for (i in v) valued["--" v[i]] = 1
}
{
  num = $0
  sub(/\t.*/, "", num)
  t = $0
  sub(/^[^\t]*\t/, "", t)
  if (t ~ /^[ \t]*#/) next
  s = t
  while (match(s, /(^|[ \t(;|&{"'])pacman[ \t]/)) {
    s = substr(s, RSTART + RLENGTH)
    cmd = s
    if (match(cmd, /(&&|[|][|]|[;|)`])/)) cmd = substr(cmd, 1, RSTART - 1)
    gsub(/["']/, "", cmd)
    m = split(cmd, w, /[ \t]+/)
    ops = ""; other = 0; skip = 0
    for (i = 1; i <= m; i++) {
      if (w[i] == "") continue
      if (skip) { skip = 0; continue }
      if (w[i] ~ /^--/) { if ((w[i] in valued) && w[i] !~ /=/) skip = 1; continue }
      if (w[i] ~ /^-/) { ops = ops w[i]; if (w[i] ~ /[rb]$/) skip = 1; continue }
      if (w[i] !~ /-keyring$/) other++
    }
    if (ops ~ /S/ && ops ~ /y/ && ops !~ /u/ && other > 0) print num
  }
}
EOF

#---------------------------------------------------------------------------#
# 8. Each localhost/ image of a document is made from a file of the tree.
#
# A local image exists only on the host that made it. The document that runs
# one gives the build, and the build file is in the tree, pinned, so another
# host makes the same image.
#---------------------------------------------------------------------------#
: > "$work/made"
: > "$work/buildfiles"
while IFS=$'\t' read -r file doc num; do
  [ -n "$file" ] || continue
  while read -r kind val; do
    case "$kind" in
      made) printf '%s\n' "$val" >> "$work/made" ;;
      file) printf '%s\t%s, bash block %s\n' "$val" "$doc" "${num%% *}" >> "$work/buildfiles" ;;
    esac
  done < <(awk -f "$work/join.awk" "$file" | awk -f "$work/made.awk")
done < "$work/index"

: > "$work/refs"
while IFS= read -r doc; do
  [ -n "$doc" ] || continue
  awk -v doc="$doc" -f "$work/refs.awk" "$REPO_ROOT/$doc" >> "$work/refs"
done < "$work/markdown"

n_refs=0
unmade=""
while IFS=$'\t' read -r where ref; do
  [ -n "$ref" ] || continue
  n_refs=$((n_refs + 1))
  grep -qxF "$ref" "$work/made" || unmade="$unmade $where:$ref"
done < "$work/refs"
if [ -z "$unmade" ]; then
  ok "each of the $n_refs localhost/ image names of the documents is made by a bash block of a document"
else
  fail "each localhost/ image that a document names is made by a bash block of a document" \
    "not made:$unmade" \
    "made by the bash blocks: $(tr '\n' ' ' < "$work/made")" \
    "only the host that made a local image has it; give its build, from a file of the tree" \
    "reproduce: git grep -n 'localhost/' -- '*.md'"
fi

n_bf=0
absent=""
unpinned=""
while IFS=$'\t' read -r bf where; do
  [ -n "$bf" ] || continue
  case "$bf" in *'$'* | *'<'*) continue ;; esac
  n_bf=$((n_bf + 1))
  if [ ! -f "$REPO_ROOT/$bf" ]; then
    absent="$absent $bf ($where)"
    continue
  fi
  case "$bf" in examples/*) continue ;; esac
  hits="$(cd "$REPO_ROOT" && awk -f "$work/pins.awk" "$bf")"
  [ -z "$hits" ] || unpinned="$unpinned $(printf '%s\n' "$hits" | tr '\n' ' ')"
done < <(awk -F'\t' '!seen[$1]++' "$work/buildfiles")
if [ -z "$absent" ]; then
  ok "each of the $n_bf files that a bash block of a document builds an image from is in the tree"
else
  fail "each file that a bash block of a document builds an image from is in the tree" \
    "not in the tree:$absent" \
    "reproduce: git grep -nE -- '-f [^ ]+' -- '*.md'"
fi
if [ -z "$unpinned" ]; then
  ok "each FROM of a build file of a document, outside examples/, is pinned by digest under its # tag: marker"
else
  fail "each FROM of a build file of a document, outside examples/, is pinned by digest under its # tag: marker" \
    "not pinned: $unpinned" \
    "write NAME:TAG@sha256:<64 hex>, and '# tag: TAG' at most 3 lines above" \
    "reproduce: grep -n -B3 '^FROM' FILE"
fi

#---------------------------------------------------------------------------#
# 9. No example and no bash block installs with a partial upgrade.
#
# pacman -Sy PACKAGE syncs the databases and installs PACKAGE on the old
# system. A new package can need a newer library than the image has. A
# keyring package alone is the one exception.
#---------------------------------------------------------------------------#
offenders=""
for ex in "$EXAMPLES"/*; do
  [ -f "$ex" ] || continue
  case "$ex" in *.md) continue ;; esac
  rel="${ex#"$REPO_ROOT/"}"
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    offenders="$offenders $rel:$n"
  done < <(awk -f "$work/join.awk" "$ex" | awk -f "$work/sy.awk")
done
while IFS=$'\t' read -r file doc num; do
  [ -n "$file" ] || continue
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    offenders="$offenders $doc(bash block ${num%% *}, line $n)"
  done < <(awk -f "$work/join.awk" "$file" | awk -f "$work/sy.awk")
done < "$work/index"
if [ -z "$offenders" ]; then
  ok "no example and none of the $total_blocks bash blocks installs a package with pacman -Sy and no -u"
else
  fail "no example and no bash block installs a package with pacman -Sy and no -u (a partial upgrade)" \
    "found at:$offenders" \
    "the new package can need a newer library than the image has; write pacman -Syu" \
    "reproduce: git grep -nE 'pacman +-S[a-z]*y' -- examples '*.md'"
fi

#---------------------------------------------------------------------------#
# 10. The keyring block of the bootstrap guide stops on a sha256 mismatch.
#
# The block runs from the root of the tree, for the first port with a
# keyring pin, with a stand-in pac. A stand-in sha256sum gives the wrong
# hash. Under set -e the block must stop before pac -U. Without set -e,
# keyring must have no value, so pass two cannot populate it.
#---------------------------------------------------------------------------#
GUIDE=docs/bootstrap-with-pacman-static.md
kb_block=""
while IFS=$'\t' read -r file doc num; do
  [ "$doc" = "$GUIDE" ] || continue
  if [ -n "$(grep_matches '^[[:space:]]*pac -U' "$file")" ]; then
    kb_block="$file"
    break
  fi
done < "$work/index"

pin_arch=""
pin=""
for a in "${ARCHES[@]}"; do
  k="$("$PORTS" get "$a" keyring)"
  if [ "$k" != none ]; then
    pin_arch="$a"
    pin="$k"
    break
  fi
done

# run_kb strict|loose real|wrong: run the keyring block. The stdout goes to
# kb.out, each pac call to kb.calls. Returns the status of the block.
run_kb() {
  local mode="$1" sha="$2" script="$work/kb.sh" rc=0
  : > "$work/kb.calls"
  {
    [ "$mode" = loose ] || printf 'set -euo pipefail\n'
    printf 'ARCH=%q\n' "$pin_arch"
    printf 'calls=%q\n' "$work/kb.calls"
    cat <<'EOS'
pac() { printf "pac %s\n" "$*" >> "$calls"; }
EOS
    if [ "$sha" = wrong ]; then
      cat <<'EOS'
sha256sum() { printf "%064d  %s\n" 0 "$1"; }
EOS
    fi
    cat "$kb_block"
    cat <<'EOS'
printf "keyring=[%s]\n" "$keyring"
EOS
  } > "$script"
  (cd "$REPO_ROOT" && bash "$script") > "$work/kb.out" 2> "$work/kb.err" || rc=$?
  return "$rc"
}

if [ -z "$kb_block" ]; then
  fail "$GUIDE has a keyring block that runs pac -U" \
    "no bash block of $GUIDE has a line that starts with pac -U" \
    "reproduce: grep -n 'pac -U' $GUIDE"
elif [ -z "$pin_arch" ]; then
  ok "no port has a keyring pin, so the keyring block of $GUIDE has no pin to check"
else
  kb_run="run the bash block of $GUIDE that has 'pac -U', with ARCH=$pin_arch, from the root of the tree"
  rc=0
  run_kb strict real || rc=$?
  if [ "$rc" -eq 0 ] && grep -qxF "keyring=[$pin]" "$work/kb.out" &&
    [ -n "$(grep_matches '^pac -U --noconfirm bootstrap/keyrings/' "$work/kb.calls")" ]; then
    ok "the keyring block of $GUIDE installs the carried package of the pin $pin ($pin_arch) when its sha256 matches"
  else
    fail "the keyring block of $GUIDE installs the carried package of the pin $pin ($pin_arch) when its sha256 matches" \
      "exit $rc; stdout: $(tr '\n' ' ' < "$work/kb.out")" \
      "pac calls: $(tr '\n' ' ' < "$work/kb.calls")" \
      "stderr: $(tr '\n' ' ' < "$work/kb.err")" \
      "reproduce: $kb_run"
  fi

  rc=0
  run_kb strict wrong || rc=$?
  if [ "$rc" -ne 0 ] && [ -z "$(grep_matches '^pac -U' "$work/kb.calls")" ]; then
    ok "the keyring block of $GUIDE stops on a sha256 mismatch under set -e, before pac -U"
  else
    fail "the keyring block of $GUIDE stops on a sha256 mismatch under set -e, before pac -U" \
      "exit $rc; pac calls: $(tr '\n' ' ' < "$work/kb.calls")" \
      "pass two populates the keyring that pass one installed with no check" \
      "reproduce: $kb_run, and a sha256sum that gives another hash"
  fi

  rc=0
  run_kb loose wrong || rc=$?
  if grep -qxF "keyring=[]" "$work/kb.out" && [ -z "$(grep_matches '^pac -U' "$work/kb.calls")" ]; then
    ok "after a sha256 mismatch, keyring has no value, so pass two stops"
  else
    fail "after a sha256 mismatch, keyring has no value, so pass two stops" \
      "exit $rc; stdout: $(tr '\n' ' ' < "$work/kb.out")" \
      "reproduce: $kb_run, with no set -e, and a sha256sum that gives another hash"
  fi
fi

#---------------------------------------------------------------------------#
# 11. examples/06 counts the SBOM packages of each platform.
#
# For an index of more than one platform, buildx gives .SBOM as a map keyed
# by platform. For one platform, it gives the SBOM itself. A stand-in docker
# answers each command of the example.
#---------------------------------------------------------------------------#
EX06="$EXAMPLES/06-verify-provenance.sh"
if [ ! -f "$EX06" ]; then
  fail "examples/06-verify-provenance.sh is in the tree" "reproduce: ls examples"
elif need_tool jq; then
  mkdir -p "$work/bin" "$work/fake06"
  cat > "$work/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *--raw*) cat "$FAKE06/index.json" ;;
  *"json .Provenance"*) echo '{}' ;;
  *"json .SBOM"*) cat "$FAKE06/sbom.json" ;;
  "pull "*) ;;
  *"json .Config.Labels"*) echo '{"org.opencontainers.image.revision": "0"}' ;;
  "image inspect "*) echo 0 ;;
  *) echo "stand-in docker: no answer for: $*" >&2; exit 1 ;;
esac
EOF
  chmod +x "$work/bin/docker"
  printf '%s\n' '{"manifests": [{"platform": {"os": "linux", "architecture": "amd64"}},' \
    '{"platform": {"os": "linux", "architecture": "arm64"}},' \
    '{"platform": {"os": "unknown", "architecture": "unknown"}}]}' > "$work/fake06/index.json"

  # run06 SBOM_JSON: run the example with that SBOM; stdout to ex06.out.
  run06() {
    local rc=0
    printf '%s\n' "$1" > "$work/fake06/sbom.json"
    PATH="$work/bin:$PATH" FAKE06="$work/fake06" IMAGE=registry.invalid/archlinux:latest \
      bash "$EX06" > "$work/ex06.out" 2> "$work/ex06.err" || rc=$?
    return "$rc"
  }

  rc=0
  run06 '{"linux/amd64": {"SPDX": {"packages": [{}, {}, {}]}}, "linux/arm64": {"SPDX": {"packages": [{}]}}}' || rc=$?
  if [ "$rc" -eq 0 ] && grep -qxF "linux/amd64 3" "$work/ex06.out" && grep -qxF "linux/arm64 1" "$work/ex06.out"; then
    ok "examples/06 gives the SBOM package count of each platform of an index"
  else
    fail "examples/06 gives the SBOM package count of each platform of an index" \
      "exit $rc; expected the lines 'linux/amd64 3' and 'linux/arm64 1'" \
      "stdout: $(tr '\n' ' ' < "$work/ex06.out")" \
      "stderr: $(tr '\n' ' ' < "$work/ex06.err")" \
      "reproduce: docker buildx imagetools inspect ghcr.io/pkgforge-dev/archlinux:latest --format '{{ json .SBOM }}' | jq 'keys'"
  fi

  rc=0
  run06 '{"SPDX": {"packages": [{}, {}]}}' || rc=$?
  if [ "$rc" -eq 0 ] && grep -qxF "2" "$work/ex06.out"; then
    ok "examples/06 gives the SBOM package count of an image of one platform"
  else
    fail "examples/06 gives the SBOM package count of an image of one platform" \
      "exit $rc; expected the line '2'" \
      "stdout: $(tr '\n' ' ' < "$work/ex06.out")" \
      "stderr: $(tr '\n' ' ' < "$work/ex06.err")" \
      "reproduce: docker buildx imagetools inspect ghcr.io/pkgforge-dev/archlinux:x86_64 --format '{{ json .SBOM }}' | jq 'keys'"
  fi
fi

#---------------------------------------------------------------------------#
# 12. The column needs of examples/README.md names each tool of an example.
#
# A tool counts when a line that is not a comment runs it as a command.
#---------------------------------------------------------------------------#
EX_README="$EXAMPLES/README.md"
awk -F'|' '
  /^\|/ {
    if (!col) {
      for (i = 2; i < NF; i++) { c = $i; gsub(/^[ \t]+|[ \t]+$/, "", c); if (c == "needs") col = i }
      next
    }
    if ($2 ~ /^[ \t:-]+$/) next
    if (match($2, /\]\([^)]+\)/)) print substr($2, RSTART + 2, RLENGTH - 3) "\t" $col
    next
  }
  { col = 0 }' "$EX_README" > "$work/needs"

missing_row=""
missing_tool=""
for ex in "$EXAMPLES"/*; do
  [ -f "$ex" ] || continue
  name="${ex##*/}"
  case "$name" in README.md) continue ;; esac
  cell="$(awk -F'\t' -v n="$name" '$1 == n { print $2 }' "$work/needs")"
  if [ -z "$cell" ]; then
    missing_row="$missing_row $name"
    continue
  fi
  for tool in docker podman jq curl gh; do
    if [ -n "$(grep_matches "^[^#]*(^|[|;&({]|[\$][(])[[:space:]]*$tool([[:space:]]|\$)" "$ex")" ]; then
      case "$cell" in *"\`$tool\`"*) ;; *) missing_tool="$missing_tool $name:$tool" ;; esac
    fi
  done
  if [ -n "$(grep_matches '^[^#]*docker[[:space:]]+buildx' "$ex")" ]; then
    case "$cell" in *buildx*) ;; *) missing_tool="$missing_tool $name:buildx" ;; esac
  fi
done
if [ -z "$missing_row" ]; then
  ok "examples/README.md has a row with the column needs for each example"
else
  fail "examples/README.md has a row with the column needs for each example" \
    "no row for:$missing_row" \
    "reproduce: grep -n '^| \[' examples/README.md"
fi
if [ -z "$missing_tool" ]; then
  ok "the column needs of examples/README.md names each tool that an example runs"
else
  fail "the column needs of examples/README.md names each tool that an example runs" \
    "not named (example:tool):$missing_tool" \
    "reproduce: grep -nE '(^|[|;&({]|[\$][(])[[:space:]]*(docker|podman|jq|curl|gh)[[:space:]]' examples/*"
fi

#---------------------------------------------------------------------------#
# 13. Each script that a source cell of docs/measurements.md runs is in the
#     tree.
#
# A source is a command that another person runs again. In each code span of
# the last cell of a row, each command is read: the first word, the script
# after ., sh, bash or python3, and the file after -f of a build. A path with
# a / is checked when the command has arguments, ends in .sh, or starts with
# scripts/, tests/, bootstrap/ or examples/. A pattern (<, *, $, {) is not.
#---------------------------------------------------------------------------#
MEAS="$REPO_ROOT/docs/measurements.md"
awk '
  function check(p) {
    if (p ~ /[<*${]/ || p !~ /\// || p ~ /^(\/|~|[.][.]?\/|https?:)/) return
    print FNR "\t" p
  }
  /^\|/ && !/^\|[ \t:|-]+$/ {
    row = $0
    gsub(/\\\|/, "\001", row)
    n = split(row, c, "|")
    src = c[n - 1]
    while (match(src, /`[^`]+`/)) {
      span = substr(src, RSTART + 1, RLENGTH - 2)
      src = substr(src, RSTART + RLENGTH)
      gsub(/\001/, "|", span)
      gsub(/&&|[|][|]|[;|]/, "\n", span)
      k = split(span, cmds, "\n")
      for (j = 1; j <= k; j++) {
        cmd = cmds[j]
        gsub(/["\047]/, "", cmd)
        sub(/^[ \t]+/, "", cmd)
        m = split(cmd, w, /[ \t]+/)
        i = 1
        while (i <= m && (w[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/ || w[i] == "time" || w[i] == "env")) i++
        if (i > m || w[i] ~ /^-/) continue
        first = w[i]
        if (first == "." || first == "sh" || first == "bash" || first == "python3") {
          for (q = i + 1; q <= m; q++) if (w[q] !~ /^-/) { check(w[q]); break }
        } else if (m > i || first ~ /[.]sh$/ || first ~ /^(scripts|tests|bootstrap|examples)\//) {
          check(first)
        }
        build = 0
        for (q = i; q <= m; q++) {
          if (w[q] == "build") build = 1
          if (build && (w[q] == "-f" || w[q] == "--file") && q < m) check(w[q + 1])
        }
      }
    }
  }' "$MEAS" > "$work/meas-paths"

n_meas=0
meas_absent=""
while IFS=$'\t' read -r line p; do
  [ -n "$p" ] || continue
  n_meas=$((n_meas + 1))
  [ -e "$REPO_ROOT/$p" ] || meas_absent="$meas_absent docs/measurements.md:$line:$p"
done < "$work/meas-paths"
if [ -z "$meas_absent" ]; then
  ok "each of the $n_meas scripts and build files that a source of docs/measurements.md runs is in the tree"
else
  fail "each script and build file that a source of docs/measurements.md runs is in the tree" \
    "not in the tree:$meas_absent" \
    "a source is a command that another person can run again; a file outside the tree cannot be run" \
    "reproduce: read the last cell of each row of docs/measurements.md"
fi

#---------------------------------------------------------------------------#
# 14. No sentence of a Markdown file has more than 25 words (ASD-STE100).
#---------------------------------------------------------------------------#
if need_tool python3; then
  mapfile -t MD_FILES < "$work/markdown"
  rc=0
  (cd "$REPO_ROOT" && python3 -I - "${MD_FILES[@]}" <<'PY') > "$work/long" 2> "$work/long.err" || rc=$?
import re
import sys

LIMIT = 25


def units(path):
    """Yield (line, text) for each heading, list item, table cell and
    paragraph of a Markdown file, outside fenced blocks and comments."""
    fence = None
    comment = False
    cur = None
    for n, raw in enumerate(open(path, encoding="utf-8"), 1):
        s = raw.strip()
        m = re.match(r"(`{3,}|~{3,})", s)
        if fence:
            if m and s.startswith(fence):
                fence = None
            continue
        if m:
            fence = m.group(1)
            if cur:
                yield cur
                cur = None
            continue
        if comment:
            comment = "-->" not in s
            continue
        if s.startswith("<!--"):
            comment = "-->" not in s
            continue
        if not s or s.startswith("|"):
            if cur:
                yield cur
                cur = None
            if s.startswith("|") and not re.fullmatch(r"\|[\s:|-]+\|?", s):
                for cell in re.split(r"(?<!\\)\|", s.strip("|")):
                    yield (n, cell)
            continue
        if s.startswith("#") or re.match(r"([-*+]|\d+\.)\s", s):
            if cur:
                yield cur
            cur = (n, re.sub(r"^([-*+]|\d+\.)\s+|^#+\s+", "", s))
            continue
        cur = (cur[0], cur[1] + " " + s) if cur else (n, s)
    if cur:
        yield cur


for path in sys.argv[1:]:
    for n, text in units(path):
        text = re.sub(r"`[^`]*`", "X", text)
        text = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", text)
        text = re.sub(r"<br\s*/?>", ". ", text)
        text = re.sub(r"<[^>]*>", "X", text)
        for sentence in re.split(r"(?<=[.!?:;])\s+", text):
            words = [w for w in sentence.split() if re.search(r"\w", w)]
            if len(words) > LIMIT:
                print(f"{path}:{n}: {len(words)} words: {sentence.strip()[:100]}")
PY
  if [ "$rc" -ne 0 ]; then
    fail "the sentences of the Markdown files can be counted" \
      "python3 exited $rc: $(tr '\n' ' ' < "$work/long.err")" \
      "reproduce: bash tests/static/80-docs-claims.sh"
  elif [ ! -s "$work/long" ]; then
    ok "no sentence of the ${#MD_FILES[@]} Markdown files has more than 25 words"
  else
    mapfile -t LONG < "$work/long"
    fail "no sentence of a Markdown file has more than 25 words" \
      "${LONG[@]}" \
      "ASD-STE100: a descriptive sentence has at most 25 words; split it, or make it a list" \
      "reproduce: bash tests/static/80-docs-claims.sh"
  fi
fi

summary
