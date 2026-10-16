# shellcheck shell=bash
#
# Shared functions for the test suites. Sourced, never executed.
#
# Output is TAP. Each test file is one plan. A failing assertion prints what
# was measured and a line that starts with "reproduce:".
#
# Needs REPO_ROOT (tests/run.sh sets it). Without it, sourcing exits 2.

if [ -z "${REPO_ROOT:-}" ]; then
  echo "harness: REPO_ROOT is not set" >&2
  exit 2
fi

TESTS_RUN=0
TESTS_FAILED=0

# ok DESC: one passing assertion.
ok() {
  TESTS_RUN=$((TESTS_RUN + 1))
  printf 'ok %d - %s\n' "$TESTS_RUN" "$1"
}

# not_ok DESC: one failing assertion.
not_ok() {
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf 'not ok %d - %s\n' "$TESTS_RUN" "$1"
}

# diag TEXT: one TAP comment line.
diag() {
  printf '#   %s\n' "$1"
}

# fail DESC [DIAG ...]: one failing assertion and a comment line per DIAG.
fail() {
  local desc="$1"
  shift
  not_ok "$desc"
  while [ "$#" -gt 0 ]; do
    diag "$1"
    shift
  done
}

# check_eq DESC WANT GOT REPRODUCE: ok when GOT equals WANT, else a failure
# that prints both and "reproduce: REPRODUCE".
check_eq() {
  if [ "$2" = "$3" ]; then
    ok "$1"
  else
    fail "$1" "want: $2" "got:  $3" "reproduce: $4"
  fi
}

# summary: print the plan line. Returns 1 when an assertion failed or when no
# assertion ran.
summary() {
  printf '1..%d\n' "$TESTS_RUN"
  if [ "$TESTS_RUN" -eq 0 ]; then
    printf '# no assertions ran, which is itself a failure\n'
    return 1
  fi
  if [ "$TESTS_FAILED" -gt 0 ]; then
    printf '# failed %d of %d\n' "$TESTS_FAILED" "$TESTS_RUN"
    return 1
  fi
  printf '# passed %d of %d\n' "$TESTS_RUN" "$TESTS_RUN"
  return 0
}

#---------------------------------------------------------------------------#
# Paths
#---------------------------------------------------------------------------#

# host_path PATH: the path in the form the container runtime reads. podman
# and docker on Windows are native programs and do not read MSYS paths.
host_path() {
  case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*) cygpath -w "$1" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# work_dir: make a temporary directory and print its path. The caller
# removes it, for example with trap 'rm -rf "$work"' EXIT.
work_dir() {
  local d
  d="$(mktemp -d)"
  printf '%s\n' "$d"
}

#---------------------------------------------------------------------------#
# Container runtime
#---------------------------------------------------------------------------#
RUNTIME=""
RUNTIME_KIND=""

# runtime_detect: set RUNTIME and RUNTIME_KIND. CONTAINER_RUNTIME wins, then
# podman, then docker. Returns 1 when none is found.
runtime_detect() {
  if [ -n "${CONTAINER_RUNTIME:-}" ]; then
    RUNTIME="$CONTAINER_RUNTIME"
  elif command -v podman > /dev/null; then
    RUNTIME="podman"
  elif command -v docker > /dev/null; then
    RUNTIME="docker"
  else
    echo "harness: no container runtime found, set CONTAINER_RUNTIME" >&2
    return 1
  fi
  case "$(basename "$RUNTIME")" in
    *podman*) RUNTIME_KIND="podman" ;;
    *) RUNTIME_KIND="docker" ;;
  esac
  export MSYS_NO_PATHCONV=1
  export MSYS2_ARG_CONV_EXCL='*'
}

# img_open IMAGE PLATFORM: create a container and print its id. The
# container does not start, so an image with no working /bin/sh can still be
# read.
img_open() {
  "$RUNTIME" create --platform "$2" "$1" true
}

# img_close CID: remove the container.
img_close() {
  "$RUNTIME" rm -f "$1" > /dev/null
}

# img_extract CID SRC DEST: copy SRC out of the container. Both runtimes
# follow a final symlink (docker with -L), so a dangling link fails here.
img_extract() {
  local cid="$1" src="$2" dest="$3"
  case "$RUNTIME_KIND" in
    docker) "$RUNTIME" cp -L "$cid:$src" "$(host_path "$dest")" ;;
    *) "$RUNTIME" cp "$cid:$src" "$(host_path "$dest")" ;;
  esac
}

# image_digest IMAGE: print the digest of the image, or nothing.
#
# A reference with @sha256: gives the digest with no runtime call. Else
# podman gives .Digest, and docker gives the first RepoDigests entry. docker
# has no .Digest field and exits 125 on it. So the output of each probe is
# kept in a variable, and an empty or failed probe goes to the next one.
image_digest() {
  local ref="$1" out
  case "$ref" in
    *@sha256:*)
      printf 'sha256:%s\n' "${ref##*@sha256:}"
      return 0
      ;;
  esac
  if out="$("$RUNTIME" image inspect "$ref" --format '{{ .Digest }}' 2>&1)"; then
    if [ -n "$out" ] && [ "$out" != "<no value>" ]; then
      printf '%s\n' "$out"
      return 0
    fi
  fi
  if out="$("$RUNTIME" image inspect "$ref" --format '{{ index .RepoDigests 0 }}' 2>&1)"; then
    case "$out" in
      *@sha256:*)
        printf 'sha256:%s\n' "${out##*@sha256:}"
        return 0
        ;;
    esac
  fi
  return 0
}

# image_require: the image suite needs IMAGE, PLATFORM and a runtime.
image_require() {
  : "${IMAGE:?the image suite needs IMAGE set}"
  : "${PLATFORM:?the image suite needs PLATFORM set, for example linux/riscv64}"
  runtime_detect
}

#---------------------------------------------------------------------------#
# Reading files
#---------------------------------------------------------------------------#

# grep_matches PATTERN FILE: print the matching lines with line numbers.
# No match returns 0 with no output. A grep error returns 2, so "nothing
# matched" and "the check did not run" stay different results.
grep_matches() {
  local out rc=0
  out="$(grep -nE "$1" "$2")" || rc=$?
  case "$rc" in
    0)
      printf '%s\n' "$out"
      return 0
      ;;
    1) return 0 ;;
    *)
      echo "harness: grep exited $rc on $2 for pattern: $1" >&2
      return 2
      ;;
  esac
}

# yaml_json FILE: print the YAML document in FILE as JSON. Reads with yq:
# mikefarah yq (scripts/install-tools) or the jq wrapper yq. Call
# need_tool yq first. Returns the status of yq.
yaml_json() {
  local v rc=0
  v="$(yq --version 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "harness: yq --version exited $rc: $v" >&2
    return "$rc"
  fi
  case "$v" in
    *mikefarah*) yq -o=json '.' "$1" ;;
    *) yq '.' "$1" ;;
  esac
}

#---------------------------------------------------------------------------#
# Tools and fixtures
#---------------------------------------------------------------------------#

# need_tool NAME...: return 0 when every NAME is on PATH. When one is
# missing, record a skip, or a failure when TESTS_REQUIRE_TOOLS=1 (CI sets
# it), and return 1. The caller leaves its assertions out:
#
#   if need_tool zstd; then ...; fi
need_tool() {
  local t missing=""
  for t in "$@"; do
    command -v "$t" > /dev/null || missing="$missing $t"
  done
  [ -z "$missing" ] && return 0
  if [ "${TESTS_REQUIRE_TOOLS:-0}" = 1 ]; then
    fail "tools are on PATH:$missing" \
      "TESTS_REQUIRE_TOOLS=1 makes a missing tool a failure" \
      "reproduce: command -v$missing"
  else
    TESTS_RUN=$((TESTS_RUN + 1))
    printf 'ok %d - # SKIP missing:%s\n' "$TESTS_RUN" "$missing"
  fi
  return 1
}

# fixture_dir: print tests/fixtures/<name of the running test file, no .sh>.
fixture_dir() {
  local name
  name="$(basename "$0" .sh)"
  printf '%s\n' "$REPO_ROOT/tests/fixtures/$name"
}
