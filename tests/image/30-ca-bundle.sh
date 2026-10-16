#!/usr/bin/env bash
#
# The CA bundle resolves and holds certificates.
#
# /etc/ssl/certs/ca-certificates.crt is a link into
# /etc/ca-certificates/extracted/. When that directory has no bundle, the
# link has no target, TLS fails, and pacman cannot read an https mirror.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"
image_require

BUNDLE="/etc/ssl/certs/ca-certificates.crt"
MIN_CERTS="${CA_BUNDLE_MIN_CERTS:-1}"

work="$(work_dir)"
cid="$(img_open "$IMAGE" "$PLATFORM")"
# shellcheck disable=SC2064
trap "img_close '$cid'; rm -rf '$work'" EXIT

if ! img_extract "$cid" "$BUNDLE" "$work/ca.pem" >/dev/null 2>>"$work/err"; then
  fail "$BUNDLE resolves in $IMAGE on $PLATFORM" \
    "the path is not there, or the link has no target" \
    "runtime said: $(tr -d '\r' < "$work/err" | tail -1)" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE sh -c 'ls -la $BUNDLE; ls -la /etc/ca-certificates/extracted/'"
  summary
  exit 1
fi
ok "$BUNDLE resolves in $IMAGE on $PLATFORM"

certs="$(awk '/BEGIN CERTIFICATE/ { n++ } END { print n+0 }' "$work/ca.pem")"
if [ "$certs" -ge "$MIN_CERTS" ]; then
  ok "$BUNDLE holds $certs certificates, minimum $MIN_CERTS"
else
  fail "$BUNDLE holds at least $MIN_CERTS certificates" \
    "counted: $certs" \
    "a bundle with no certificate fails TLS as a missing bundle does" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE sh -c 'grep BEGIN $BUNDLE | wc -l'"
fi

summary
