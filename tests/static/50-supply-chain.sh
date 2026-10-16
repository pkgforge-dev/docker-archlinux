#!/usr/bin/env bash
#
# Check what the build and the workflows fetch.
#
#   - no remote script is piped into a shell (curl ... | sh, sh <(curl ...))
#   - no download is made executable on the same line it is fetched, with no
#     hash check between
#   - no workflow uses a deprecated workflow command (::set-output and the
#     others); the GITHUB_OUTPUT, GITHUB_STATE, GITHUB_ENV and GITHUB_PATH
#     files replace them
#   - each image pinned by digest has a "# tag: <tag>" line at most 3 lines
#     above it, with the tag of the reference. Renovate and
#     scripts/check-image-pins read that line.
#
# Read: the workflows, the Dockerfile, scripts/ and bootstrap/any/usr/local/bin.
# Action pins are checked in tests/static/51-workflow-policy.sh.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

cd "$REPO_ROOT"

mapfile -t wfs < <(find .github/workflows -type f \( -name '*.yml' -o -name '*.yaml' \) | LC_ALL=C sort)
mapfile -t code < <({
  printf '%s\n' "${wfs[@]}"
  [ ! -f Dockerfile ] || printf '%s\n' Dockerfile
  for d in scripts bootstrap/any/usr/local/bin; do
    [ ! -d "$d" ] || find "$d" -type f
  done
} | LC_ALL=C sort)
if [ "${#wfs[@]}" -eq 0 ] || [ "${#code[@]}" -eq 0 ]; then
  fail "there are workflows and scripts to read" "workflows ${#wfs[@]}, files ${#code[@]}" \
    "reproduce: ls .github/workflows scripts"
  summary
  exit 1
fi

# lines PATTERN FILE...: "FILE:LINE: TEXT" for each line, comments removed,
# that matches the extended regex PATTERN.
lines() {
  local pat="$1"
  shift
  awk -v pat="$pat" '
    /^[[:space:]]*#/ { next }
    {
      line = $0
      sub(/[[:space:]]#.*$/, "", line)
      if (line ~ pat) { t = line; sub(/^[[:space:]]+/, "", t); print FILENAME ":" FNR ": " t }
    }' "$@"
}

PIPE_TO_SHELL='(curl|wget)[^|]*[|][[:space:]]*(sudo[[:space:]]+)?(ba|da|z)?sh([[:space:]]|$)|(ba|da|z)?sh[[:space:]]+<[(][[:space:]]*(curl|wget)'
FETCH_EXEC='(curl|wget)[^;&]*(-O|--output|-o)[^;&]*[;&]+[[:space:]]*(&&)?[[:space:]]*chmod[[:space:]]+([+]x|[0-7]*[1357][0-7]*)'
DEPRECATED='::(set-output|save-state|set-env|add-path)'

check_eq "no remote script is piped into a shell" "" "$(lines "$PIPE_TO_SHELL" "${code[@]}")" \
  "grep -nE 'curl|wget' FILE; vendor the script, or pin the file by sha256"
check_eq "no download is made executable with no hash check" "" "$(lines "$FETCH_EXEC" "${code[@]}")" \
  "grep -n chmod FILE; check the sha256 first, as scripts/install-tools does"
check_eq "no workflow uses a deprecated workflow command" "" "$(lines "$DEPRECATED" "${wfs[@]}")" \
  "grep -n '::set-' .github/workflows/*.yml; write to the GITHUB_OUTPUT file"

# Each name[:tag]@sha256:<64 hex> and the "# tag:" lines above it.
unmarked="$(awk '
  FNR == 1 { b1 = b2 = b3 = "" }
  {
    if ($0 !~ /^[[:space:]]*#/ && match($0, /[A-Za-z0-9.-]+\/[A-Za-z0-9._\/-]+(:[A-Za-z0-9._-]+)?@sha256:[0-9a-f]{64}/)) {
      ref = substr($0, RSTART, RLENGTH)
      name = ref
      sub(/@sha256:.*/, "", name)
      want = ""
      if (match(name, /:[A-Za-z0-9._-]+$/)) want = substr(name, RSTART + 1)
      got = ""
      m = b1 "\n" b2 "\n" b3
      n = split(m, l, "\n")
      for (i = 1; i <= n; i++) if (match(l[i], /#[[:space:]]*tag:[[:space:]]*[^[:space:]]+/)) {
        got = substr(l[i], RSTART, RLENGTH)
        sub(/#[[:space:]]*tag:[[:space:]]*/, "", got)
      }
      if (got == "") print FILENAME ":" FNR ": no # tag: line above " ref
      else if (want != "" && got != want) print FILENAME ":" FNR ": # tag: " got " above " ref
    }
    b1 = b2; b2 = b3; b3 = $0
  }' "${code[@]}")"
check_eq "each image pinned by digest has its # tag: line at most 3 lines above" "" "$unmarked" \
  "grep -nB3 '@sha256:' FILE"

summary
