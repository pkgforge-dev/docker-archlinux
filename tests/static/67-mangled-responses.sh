#!/usr/bin/env bash
#
# A mirror that answers with the wrong thing must be reported and stepped over,
# never consumed.
#
# ⛔ Every fetch has to assume the response is wrong, not just absent. Absent is
# the easy case. These are the shapes this project has actually been served:
#
#   a .sig that was 404 and became a zero byte file
#   a base.db that was Zstandard where every sibling is gzip
#   a mirror answering 403 for one path, so the body is an error page
#   a mirror answering 200 from one network and 403 from another
#   a 301 that -L followed to a 29 second dead end
#
# All five arrive at scripts/resolve-anchor as one of two things: the fetch
# failed, or the body is not the archive it claims to be. Both are fed here.
# ⚠ The 301 to a dead end is the third, a fetch that never ends, and it is not
# reproducible from a local file. What bounds it is the transfer policy, which
# tests/static/65-fetch-policy.sh asserts separately.
#
# The mirrors are local files. A test that needs a server would need one inside
# the image too, where the static suite also runs, and the image ships no
# python, no nc and no busybox.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

ANCHOR_VERSION="9.9.9.r1.gfeedface-7"

if ! command -v tar >/dev/null; then
  fail "tar is available" \
    "the fixtures are gzip archives, the shape a repository database has" \
    "reproduce: command -v tar"
  summary
  exit 1
fi

work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

# file_url PATH -> a file:// URL curl can open on this platform
#
# ⚠ curl on Windows is a native binary and does not read an MSYS path, so the
# path is converted. cygpath -m rather than -w: a URL wants forward slashes.
file_url() {
  case "$(uname -o 2>/dev/null)" in
    Msys | Cygwin) printf 'file:///%s\n' "$(cygpath -m "$1")" ;;
    *) printf 'file://%s\n' "$1" ;;
  esac
}

#---------------------------------------------------------------------------#
# One directory per mirror, each serving core.db as a different kind of wrong.
#---------------------------------------------------------------------------#
mkdir -p "$work/srv"/{empty,zstd,errorpage,truncated,missing,good}

# 404 that became a zero byte file
: > "$work/srv/empty/core.db"

# Zstandard where every sibling is gzip. The magic number is what matters.
printf '\050\265\057\375\000\130\041\000\000not-gzip\n' > "$work/srv/zstd/core.db"

# 403, or a 200 from one network and a 403 from another. Either way the body is
# an error page and the status is not what the caller believed.
printf '<html><head><title>403 Forbidden</title></head><body>Forbidden</body></html>\n' \
  > "$work/srv/errorpage/core.db"

# A gzip header that stops partway, which is what an interrupted transfer that
# still exits 0 leaves behind.
mkdir -p "$work/whole/pacman-1.0-1"
tar -czf "$work/whole.db" -C "$work/whole" pacman-1.0-1
head -c 20 "$work/whole.db" > "$work/srv/truncated/core.db"

# The one that works, last, so reaching it proves the four above were stepped
# over rather than fatal.
mkdir -p "$work/good/pacman-$ANCHOR_VERSION" "$work/good/bash-5.3.15-1"
tar -czf "$work/srv/good/core.db" -C "$work/good" "pacman-$ANCHOR_VERSION" bash-5.3.15-1

#---------------------------------------------------------------------------#
# A scratch tree holding one fake architecture, and the real script.
#---------------------------------------------------------------------------#
mkdir -p "$work/repo/rootfs/fake/etc/pacman.d" "$work/repo/scripts"
cp "$REPO_ROOT/scripts/resolve-anchor" "$work/repo/scripts/resolve-anchor"
printf '[options]\nArchitecture = x86_64\n\n[core]\nInclude = /etc/pacman.d/mirrorlist\n' \
  > "$work/repo/rootfs/fake/etc/pacman.conf"

base="$(file_url "$work/srv")"
{
  for shape in empty zstd errorpage truncated missing; do
    printf 'Server = %s/%s\n' "$base" "$shape"
  done
  printf 'Server = %s/good\n' "$base"
} > "$work/repo/rootfs/fake/etc/pacman.d/mirrorlist"

#---------------------------------------------------------------------------#
# Run it once and judge the whole result.
#---------------------------------------------------------------------------#
rc=0
( cd "$work/repo" && bash scripts/resolve-anchor fake ) \
  > "$work/out" 2> "$work/err" || rc=$?

if [ "$rc" -eq 0 ]; then
  ok "resolve-anchor survives five mangled mirrors and exits 0"
else
  fail "resolve-anchor survives five mangled mirrors and exits 0" \
    "it exited $rc" \
    "one bad mirror must not decide the version for a whole release" \
    "it said: $(tr -d '\r' < "$work/err" | awk 'NF { last = $0 } END { print last }')" \
    "reproduce: bash tests/static/67-mangled-responses.sh, which keeps its fixtures under a temp dir"
fi

got="$(tr -d '\r' < "$work/out" | awk 'NF { print; exit }')"
if [ "$got" = "$ANCHOR_VERSION" ]; then
  ok "it falls through to the one good mirror and prints $ANCHOR_VERSION"
else
  fail "it falls through to the one good mirror and prints $ANCHOR_VERSION" \
    "it printed: ${got:-nothing}" \
    "⛔ a value read out of a mangled database would be worse than no value" \
    "reproduce: bash tests/static/67-mangled-responses.sh"
fi

#---------------------------------------------------------------------------#
# Every bad mirror is named, and every complaint says what was wrong with it.
#
# ⛔ The reason is the point. This diagnostic used to print the first line of
# tar's output, and tar puts a blank line ahead of what gzip said, so the
# message was empty in every case it exists for.
#---------------------------------------------------------------------------#
for shape in empty zstd errorpage truncated missing; do
  hits="$(awk -v s="/$shape/core.db" 'index($0, s) { n++ } END { print n + 0 }' "$work/err")"
  if [ "$hits" -ge 1 ]; then
    ok "the $shape mirror is named in the diagnostics"
  else
    fail "the $shape mirror is named in the diagnostics" \
      "no line mentions it, so a reader cannot tell which server to stop trusting" \
      "reproduce: bash tests/static/67-mangled-responses.sh, and read the captured stderr"
  fi
done

# A complaint with nothing after the colon is the defect this guards.
empty_reason="$(awk '
  /resolve-anchor: / {
    line = $0
    sub(/[[:space:]]+$/, "", line)
    if (line ~ /:[[:space:]]*$/) { print line; n++ }
  }
  END { exit 0 }' "$work/err")"
if [ -z "$empty_reason" ]; then
  ok "every complaint names a reason"
else
  fail "every complaint names a reason" \
    "these end at the colon: $(printf '%s' "$empty_reason" | tr '\n' '|')" \
    "a diagnostic that is empty in the only cases it runs in is worse than none" \
    "reproduce: bash tests/static/67-mangled-responses.sh, and read the captured stderr"
fi

#---------------------------------------------------------------------------#
# The bad mirrors must not be the ones that answered.
#
# A run that took the error page and somehow produced a version would satisfy
# every assertion above. This is the one that says where the answer came from.
#---------------------------------------------------------------------------#
complaints="$(awk '/resolve-anchor: / { n++ } END { print n + 0 }' "$work/err")"
if [ "$complaints" -eq 5 ]; then
  ok "all five bad mirrors were refused, and exactly five"
else
  fail "all five bad mirrors were refused, and exactly five" \
    "counted $complaints complaints, expected 5" \
    "fewer means the search stopped early or one was consumed, more means the good mirror was refused too" \
    "reproduce: bash tests/static/67-mangled-responses.sh, and read the captured stderr"
fi

summary
