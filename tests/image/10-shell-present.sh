#!/usr/bin/env bash
#
# The final image must have a working shell.
#
# When the bootstrap installs nothing, the scratch stage receives only empty
# directories and every later instruction fails with
#   runc run failed: exec: "/bin/sh": stat /bin/sh: no such file or directory
# The image is inspected without being started, because an image in that state
# cannot run anything at all.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"
image_require

work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

cid="$(img_open "$IMAGE" "$PLATFORM")"
# shellcheck disable=SC2064
trap "img_close '$cid'; rm -rf '$work'" EXIT

for path in /bin/sh /usr/bin/bash; do
  name="$(printf '%s\n' "$path" | tr '/' '_')"
  if img_extract "$cid" "$path" "$work/x$name" >/dev/null 2>>"$work/err"; then
    size="$(wc -c < "$work/x$name" | tr -d '[:space:]')"
    if [ "$size" -gt 0 ]; then
      ok "$path exists and resolves in $IMAGE on $PLATFORM ($size bytes)"
    else
      fail "$path is not empty in $IMAGE on $PLATFORM" "size: $size bytes" \
        "reproduce: $RUNTIME create --platform $PLATFORM $IMAGE true, then $RUNTIME cp CID:$path ."
    fi
  else
    fail "$path exists and resolves in $IMAGE on $PLATFORM" \
      "the path is missing, or it is a symlink with no target" \
      "reproduce: $RUNTIME create --platform $PLATFORM $IMAGE true, then $RUNTIME cp CID:$path ."
  fi
done

summary
