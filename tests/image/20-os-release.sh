#!/usr/bin/env bash
#
# The image records what it is and its version.
#
# No package owns /etc/os-release. The filesystem package has
# /usr/lib/os-release, and a pacstrap bootstrap makes no /etc/os-release.
# No port publishes a VERSION_ID. So the build writes the file
# (write-os-release), with VERSION_ID from the build.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"
image_require

work="$(work_dir)"
cid="$(img_open "$IMAGE" "$PLATFORM")"
# shellcheck disable=SC2064
trap "img_close '$cid'; rm -rf '$work'" EXIT

if ! img_extract "$cid" /etc/os-release "$work/os-release" >/dev/null 2>>"$work/err"; then
  fail "/etc/os-release is in $IMAGE on $PLATFORM" \
    "runtime said: $(tr -d '\r' < "$work/err" | tail -1)" \
    "no package owns this path, so the build must write it" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE sh -c 'cat /etc/os-release'"
  summary
  exit 1
fi
ok "/etc/os-release is in $IMAGE on $PLATFORM"

value() { # KEY -> the value with no quotes; empty when the key is not there
  awk -F= -v k="$1" '$1 == k { sub(/^[^=]*=/, ""); gsub(/^"|"$/, ""); print; exit }' "$work/os-release"
}

for key in ID VERSION_ID; do
  v="$(value "$key")"
  if [ -n "$v" ]; then
    ok "/etc/os-release has $key=$v"
  else
    fail "/etc/os-release has $key" \
      "the key is not there, or it is empty" \
      "keys found: $(awk -F= '/^[A-Z_]+=/ { printf "%s ", $1 }' "$work/os-release")" \
      "reproduce: $RUNTIME create --platform $PLATFORM $IMAGE true, then $RUNTIME cp CID:/etc/os-release ."
  fi
done

# The OCI label and the file must give the same version.
label="$("$RUNTIME" image inspect "$IMAGE" --format '{{ index .Config.Labels "org.opencontainers.image.version" }}')"
version_id="$(value VERSION_ID)"
if [ -z "$label" ] || [ "$label" = "<no value>" ]; then
  fail "the image has the label org.opencontainers.image.version" \
    "the label is not there" \
    "reproduce: $RUNTIME image inspect $IMAGE --format '{{ .Config.Labels }}'"
elif [ "$label" = "$version_id" ]; then
  ok "org.opencontainers.image.version is VERSION_ID ($label)"
else
  fail "org.opencontainers.image.version is VERSION_ID" \
    "label: $label" \
    "VERSION_ID: $version_id" \
    "reproduce: $RUNTIME image inspect $IMAGE, and compare the label org.opencontainers.image.version with VERSION_ID in /etc/os-release"
fi

summary
