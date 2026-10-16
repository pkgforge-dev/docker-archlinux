#!/usr/bin/env bash
#
# Check the base images of the Dockerfile.
#
#   - no FROM names an image this repository publishes. A build that starts
#     from its own last output keeps every defect of that output, and nobody
#     can rebuild it without trusting this project first.
#   - each FROM that is not scratch and not an earlier stage is pinned by
#     digest (@sha256:<64 hex>).
#
# A FROM may name an ARG, as in FROM ${BASE_IMAGE}. The value is the default
# of an ARG line before the first FROM. A FROM whose ARG has no default
# fails, because its image is then not known from the Dockerfile.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

cd "$REPO_ROOT"
if [ ! -f Dockerfile ]; then
  fail "the Dockerfile exists" "reproduce: ls Dockerfile"
  summary
  exit 1
fi

# The images this repository publishes: ghcr.io/<owner>/archlinux and
# docker.io/pkgforge/archlinux, under either owner name.
OWN_IMAGES='(^|/)pkgforge(-dev)?/archlinux(:|@|$)'

# Each FROM as "LINE<TAB>IMAGE<TAB>RAW". IMAGE has each ${NAME} and $NAME of
# a global ARG replaced by its default; RAW is the token as written. A
# FROM that names an earlier stage prints "stage" as IMAGE.
froms="$(awk '
  function resolve(s,   name, out, m) {
    out = ""
    while (match(s, /[$][{][A-Za-z_][A-Za-z0-9_]*[}]|[$][A-Za-z_][A-Za-z0-9_]*/)) {
      name = substr(s, RSTART, RLENGTH)
      gsub(/[${}]/, "", name)
      out = out substr(s, 1, RSTART - 1) ((name in arg) ? arg[name] : "${" name "}")
      s = substr(s, RSTART + RLENGTH)
    }
    return out s
  }
  /^[[:space:]]*#/ { next }
  toupper($1) == "ARG" && !seen_from {
    v = $2
    eq = index(v, "=")
    if (eq > 0) {
      name = substr(v, 1, eq - 1)
      val = substr(v, eq + 1)
      gsub(/^"|"$/, "", val)
      arg[name] = val
    }
    next
  }
  toupper($1) == "FROM" {
    seen_from = 1
    img = ""
    for (i = 2; i <= NF; i++) if (substr($i, 1, 2) != "--") { img = $i; break }
    for (i = 2; i < NF; i++) if (toupper($i) == "AS") alias = $(i + 1)
    if (img in stage) print NR "\tstage\t" img
    else print NR "\t" resolve(img) "\t" img
    if (alias != "") stage[alias] = 1
    alias = ""
  }' Dockerfile)"

if [ -z "$froms" ]; then
  fail "the Dockerfile has a FROM" "reproduce: grep -n '^FROM' Dockerfile"
  summary
  exit 1
fi

circular=""
unpinned=""
n=0
while IFS=$'\t' read -r line image raw; do
  [ -n "$line" ] || continue
  n=$((n + 1))
  case "$image" in
    stage | scratch) continue ;;
  esac
  if [[ $image =~ $OWN_IMAGES ]]; then
    circular="$circular Dockerfile:$line:$image"
  fi
  if ! [[ $image =~ @sha256:[0-9a-f]{64}$ ]]; then
    unpinned="$unpinned Dockerfile:$line:$raw=$image"
  fi
done <<< "$froms"

check_eq "no FROM of $n names an image this repository publishes" "" "$circular" \
  "grep -nE '^(FROM|ARG)' Dockerfile"
check_eq "each FROM of $n that is not scratch or a stage is pinned by digest" "" "$unpinned" \
  "grep -nE '^(FROM|ARG)' Dockerfile; scripts/check-image-pins --apply writes the digest under its # tag: line"

summary
