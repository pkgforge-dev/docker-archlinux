#!/usr/bin/env bash
#
# The image must record what it is and which version it is.
#
# No package owns /etc/os-release. The filesystem package ships
# /usr/lib/os-release, and Arch's release tooling writes /etc/os-release with a
# release id injected. A pure pacstrap bootstrap never creates it, so this
# repository generates it. No Arch port ships a VERSION_ID of its own, so the
# value has to come from the build.
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
  fail "/etc/os-release exists in $IMAGE on $PLATFORM" \
    "runtime said: $(tr -d '\r' < "$work/err" | tail -1)" \
    "no package owns this path, so the build must generate it" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE sh -c 'cat /etc/os-release'"
  summary
  exit 1
fi
ok "/etc/os-release exists in $IMAGE on $PLATFORM"

value() { # KEY -> the unquoted value, empty when absent
  awk -F= -v k="$1" '$1 == k { sub(/^[^=]*=/, ""); gsub(/^"|"$/, ""); print; exit }' "$work/os-release"
}

for key in ID VERSION_ID; do
  v="$(value "$key")"
  if [ -n "$v" ]; then
    ok "/etc/os-release carries $key=$v"
  else
    fail "/etc/os-release carries $key" \
      "the key is absent or empty" \
      "found keys: $(awk -F= '/^[A-Z_]+=/ { printf "%s ", $1 }' "$work/os-release")"
  fi
done

# The OCI labels must agree with the file, or the two records disagree about
# what was built.
label="$("$RUNTIME" image inspect "$IMAGE" --format '{{ index .Config.Labels "org.opencontainers.image.version" }}')"
version_id="$(value VERSION_ID)"
if [ -z "$label" ] || [ "$label" = "<no value>" ]; then
  fail "the image carries org.opencontainers.image.version" \
    "label is absent" \
    "reproduce: $RUNTIME image inspect $IMAGE --format '{{ .Config.Labels }}'"
elif [ "$label" = "$version_id" ]; then
  ok "org.opencontainers.image.version matches VERSION_ID ($label)"
else
  fail "org.opencontainers.image.version matches VERSION_ID" \
    "label: $label" \
    "VERSION_ID: $version_id"
fi

summary
