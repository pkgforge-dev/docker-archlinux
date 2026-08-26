#!/usr/bin/env bash
#
# The CA bundle must resolve and hold certificates.
#
# On riscv64 /etc/ssl/certs/ca-certificates.crt is a symlink into
# /etc/ca-certificates/extracted/, and that directory holds only README. The
# link dangles, TLS fails, and the mirror cannot be reached. This one check
# would have caught the whole outage on the build that introduced it.
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
    "the path is missing, or the symlink has no target" \
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
    "a bundle that resolves but is empty fails TLS the same way a missing one does" \
    "reproduce: $RUNTIME run --rm --platform $PLATFORM $IMAGE sh -c 'grep BEGIN $BUNDLE | wc -l'"
fi

summary
