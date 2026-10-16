#!/usr/bin/env bash
#
# The image has a shell.
#
# When the bootstrap installs nothing, the image stage gets empty directories,
# and each later instruction fails with
#   runc run failed: exec: "/bin/sh": stat /bin/sh: no such file or directory
# So the test creates a container and does not start it: an image in that
# state can run nothing.
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
      ok "$path is in $IMAGE on $PLATFORM and resolves ($size bytes)"
    else
      fail "$path is not empty in $IMAGE on $PLATFORM" "size: $size bytes" \
        "reproduce: $RUNTIME create --platform $PLATFORM $IMAGE true, then $RUNTIME cp CID:$path ."
    fi
  else
    fail "$path is in $IMAGE on $PLATFORM and resolves" \
      "the path is not there, or it is a link with no target" \
      "runtime said: $(tr -d '\r' < "$work/err" | awk 'NF { last = $0 } END { print last }')" \
      "reproduce: $RUNTIME create --platform $PLATFORM $IMAGE true, then $RUNTIME cp CID:$path ."
  fi
done

summary
