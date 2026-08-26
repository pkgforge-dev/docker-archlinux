# Shared harness for the test suites. Sourced, never executed.
#
# Output is TAP. Each test file is one plan. A failing assertion prints the
# measurement and the command that reproduces it, so a CI log is enough to act
# on without re-deriving anything.

if [ -z "${REPO_ROOT:-}" ]; then
  echo "harness: REPO_ROOT is not set" >&2
  exit 2
fi

TESTS_RUN=0
TESTS_FAILED=0

ok() {
  TESTS_RUN=$((TESTS_RUN + 1))
  printf 'ok %d - %s\n' "$TESTS_RUN" "$1"
}

not_ok() {
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf 'not ok %d - %s\n' "$TESTS_RUN" "$1"
}

diag() {
  printf '#   %s\n' "$1"
}

# fail DESC [DIAG ...]
fail() {
  local desc="$1"
  shift
  not_ok "$desc"
  while [ "$#" -gt 0 ]; do
    diag "$1"
    shift
  done
}

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
#
# podman and docker on Windows are native binaries and do not read MSYS paths.
# Every host path handed to a runtime goes through this.
#---------------------------------------------------------------------------#
host_path() {
  case "$(uname -o 2>/dev/null)" in
    Msys | Cygwin) cygpath -w "$1" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

#---------------------------------------------------------------------------#
# Container runtime
#---------------------------------------------------------------------------#
RUNTIME=""
RUNTIME_KIND=""

runtime_detect() {
  if [ -n "${CONTAINER_RUNTIME:-}" ]; then
    RUNTIME="$CONTAINER_RUNTIME"
  elif command -v podman >/dev/null 2>&1; then
    RUNTIME="podman"
  elif command -v docker >/dev/null 2>&1; then
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

# img_open IMAGE PLATFORM -> prints container id
#
# Creates without starting, so an image whose /bin/sh is missing can still be
# inspected. That is the state the riscv64 image was published in.
img_open() {
  "$RUNTIME" create --platform "$2" "$1" true
}

img_close() {
  "$RUNTIME" rm -f "$1" >/dev/null
}

# img_extract CID SRC DEST -> exit 0 when SRC exists and resolves
#
# Both runtimes resolve the final symlink, podman by default and docker with
# -L. A dangling link therefore fails here, which is the CA bundle defect.
img_extract() {
  local cid="$1" src="$2" dest="$3"
  case "$RUNTIME_KIND" in
    docker) "$RUNTIME" cp -L "$cid:$src" "$(host_path "$dest")" ;;
    *) "$RUNTIME" cp "$cid:$src" "$(host_path "$dest")" ;;
  esac
}

# work_dir -> a scratch directory removed when the test exits
work_dir() {
  local d
  d="$(mktemp -d)"
  printf '%s\n' "$d"
}

# image_digest IMAGE -> the image's own digest, or empty
#
# The two runtimes disagree about where this lives. podman exposes .Digest;
# docker's inspect type has no such field and a Go template naming it exits 125
# rather than printing <no value>, which would kill a caller running under
# set -e before it could report anything. A reference that already carries
# @sha256: is authoritative and needs no runtime at all, which is the shape CI
# uses.
image_digest() {
  local ref="$1" out
  case "$ref" in
    *@sha256:*)
      printf 'sha256:%s\n' "${ref##*@sha256:}"
      return 0
      ;;
  esac
  # stderr is captured rather than discarded, so a probe that fails leaves the
  # runtime's own words in $out for the next branch to ignore deliberately.
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

#---------------------------------------------------------------------------#
# grep_matches PATTERN FILE
#
# Prints matching lines with line numbers. No match is a normal result and
# exits 0 with no output. A real grep failure exits 2 and is not swallowed,
# which is the difference between "nothing matched" and "the check did not run".
#---------------------------------------------------------------------------#
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

#---------------------------------------------------------------------------#
# image_require
#
# Every test in the image suite needs the same three things. IMAGE names the
# image, PLATFORM names the platform inside it, and a runtime must exist.
#---------------------------------------------------------------------------#
image_require() {
  : "${IMAGE:?the image suite needs IMAGE set}"
  : "${PLATFORM:?the image suite needs PLATFORM set, for example linux/riscv64}"
  runtime_detect
}
