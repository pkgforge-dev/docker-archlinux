#!/usr/bin/env bash
#
# The records that the workflows keep on GitHub.
#
# Part 1: scripts/track-issue finds its issue by the body marker over every
# open issue, with or without the label, and puts the label back on raise.
# Only an issue of the bot whose body starts with the marker counts.
#
# Part 2: scripts/propose-change finds its own pull request: the one that the
# bot opened from the branch of this repository, not a pull request from a
# fork with the same branch name.
#
# A stand-in for gh (tests/fixtures/issues/fake-gh) answers the list of open
# issues and pull requests. It records each issue or pull request that it
# would open, update, label, comment on or close. A bare repository in the work
# directory is the origin of Part 2. No network.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

if ! need_tool jq; then
  summary
  exit $?
fi

work="$(work_dir)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
cp "$REPO_ROOT/tests/fixtures/issues/fake-gh" "$work/bin/gh"
chmod +x "$work/bin/gh"
printf 'body text\n' > "$work/body.md"
n_dirs=0

# expect DESC WANT GOT REPRODUCE
expect() {
  if [ "$2" = "$3" ]; then
    ok "$1"
  else
    fail "$1" "expected: $2" "got:      $3" "reproduce: $4"
  fi
}

# issues SPEC ...: the open issues. SPEC is NUMBER:KEY:LABEL[:AUTHOR].
# LABEL is automation, other or -. KEY "-" is no marker, and KEY "+K" has the
# marker of K after a first line of other text. AUTHOR defaults to
# github-actions[bot]. A NUMBER with a p before it is a pull request.
issues() {
  local spec n k l a
  n_dirs=$((n_dirs + 1))
  gh="$work/gh-$n_dirs"
  mkdir -p "$gh"
  : > "$gh/calls.log"
  for spec in "$@"; do
    IFS=: read -r n k l a <<< "$spec"
    jq -n --arg n "$n" --arg k "$k" --arg l "$l" --arg a "${a:-github-actions[bot]}" '
      {number: ($n | ltrimstr("p") | tonumber),
       user: {login: $a},
       body: (if $k == "-" then "no marker"
              elif ($k | startswith("+")) then "a first line\n<!-- track: \($k | ltrimstr("+")) -->\nold body"
              else "<!-- track: \($k) -->\nold body" end),
       labels: (if $l == "-" then [] else [{name: $l}] end)}
      + (if ($n | startswith("p")) then {pull_request: {url: "x"}} else {} end)'
  done | jq -s . > "$gh/open.json"
}

# track ARGS...: run scripts/track-issue; prints "<exit> <events>"
track() {
  local rc=0
  PATH="$work/bin:$PATH" FAKE_GH_DIR="$gh" GH_TOKEN=stub GITHUB_REPOSITORY=test/repo \
    "$REPO_ROOT/scripts/track-issue" "$@" > "$work/out" 2>&1 || rc=$?
  printf '%s %s\n' "$rc" "$(tr '\n' ';' < "$gh/calls.log" | sed 's/;$//')"
}

T="FAKE_GH_DIR=DIR scripts/track-issue"

issues 7:build-ppc:-
expect "raise finds an issue with the marker and no label, updates it, and puts the label back" \
  "0 update 7 build-ppc;label 7" "$(track raise build-ppc "title" "$work/body.md")" "$T raise build-ppc T BODY"

issues 7:build-ppc:other
expect "raise finds an issue with the marker and another label" \
  "0 update 7 build-ppc;label 7" "$(track raise build-ppc "title" "$work/body.md")" "$T raise build-ppc T BODY"

issues 7:build-ppc:- 9:build-ppc:automation
expect "two issues with the marker: the one with the label wins" \
  "0 update 9 build-ppc" "$(track raise build-ppc "title" "$work/body.md")" "$T raise build-ppc T BODY"

issues 12:build-ppc:- 9:build-ppc:-
expect "two issues with the marker and no label: the lowest number wins" \
  "0 update 9 build-ppc;label 9" "$(track raise build-ppc "title" "$work/body.md")" "$T raise build-ppc T BODY"

issues 13:build-ppc64:automation 14:-:automation
expect "a marker of another key (build-ppc64 for build-ppc) is not a match: a new issue opens" \
  "0 open build-ppc" "$(track raise build-ppc "title" "$work/body.md")" "$T raise build-ppc T BODY"
if [ "$(awk 'NR == 1' "$gh/body-build-ppc.md")" = "<!-- track: build-ppc -->" ]; then
  ok "the body of a new issue starts with the marker"
else
  fail "the body of a new issue starts with the marker" "first line: $(awk 'NR == 1' "$gh/body-build-ppc.md")" "reproduce: $T raise build-ppc T BODY"
fi

issues p20:build-ppc:automation
expect "a pull request with the marker is not the issue" \
  "0 open build-ppc" "$(track raise build-ppc "title" "$work/body.md")" "$T raise build-ppc T BODY"

issues 7:build-ppc:automation:mallory
expect "an issue with the marker that another user opened is not the issue: a new issue opens" \
  "0 open build-ppc" "$(track raise build-ppc "title" "$work/body.md")" "$T raise build-ppc T BODY"

issues 7:+build-ppc:automation
expect "an issue whose body has the marker after other text is not the issue: a new issue opens" \
  "0 open build-ppc" "$(track raise build-ppc "title" "$work/body.md")" "$T raise build-ppc T BODY"

issues 7:build-ppc:automation:mallory 9:build-ppc:-
expect "the issue of the bot wins over an issue of another user with a lower number" \
  "0 update 9 build-ppc;label 9" "$(track raise build-ppc "title" "$work/body.md")" "$T raise build-ppc T BODY"

issues 7:build-ppc:automation:mallory
expect "clear does not close an issue of another user with the marker" \
  "0 " "$(track clear build-ppc "note")" "$T clear build-ppc NOTE"

issues 7:build-ppc:automation:other-bot
expect "TRACK_ISSUE_AUTHOR names the author of the issues" \
  "0 update 7 build-ppc" "$(TRACK_ISSUE_AUTHOR=other-bot track raise build-ppc "title" "$work/body.md")" \
  "TRACK_ISSUE_AUTHOR=other-bot $T raise build-ppc T BODY"

issues 7:build-ppc:-
expect "clear finds the issue with no label, comments and closes it" \
  "0 comment 7;close 7" "$(track clear build-ppc "note")" "$T clear build-ppc NOTE"

issues 14:-:automation
expect "clear with no open issue does nothing" "0 " "$(track clear build-ppc "note")" "$T clear build-ppc NOTE"

issues 7:build-ppc:automation
rc=0
: > "$gh/calls.log"
PATH="$work/bin:$PATH" FAKE_GH_DIR="$gh" GH_TOKEN=stub GITHUB_REPOSITORY=test/repo FAKE_GH_FAIL='repos/*/issues\?*' \
  "$REPO_ROOT/scripts/track-issue" raise build-ppc "title" "$work/body.md" > "$work/out" 2>&1 || rc=$?
expect "an issue list that cannot be read: exit 1, and no second issue opens" \
  "1 " "$rc $(tr '\n' ';' < "$gh/calls.log")" "FAKE_GH_FAIL='repos/*/issues?*' $T raise build-ppc T BODY"

issues
expect "a key with a capital letter is refused" "1 " "$(track raise Build-ppc "title" "$work/body.md")" "$T raise Build-ppc T BODY"

#---------------------------------------------------------------------------#
# Part 2: scripts/propose-change edits or closes only its own pull request.
#---------------------------------------------------------------------------#
if need_tool git; then
  export GIT_CONFIG_NOSYSTEM=1
  origin="$work/origin.git"
  clone="$work/clone"
  g() { HOME="$work" git -C "$clone" -c user.name=t -c user.email=t@t.invalid -c commit.gpgsign=false "$@"; }
  git init -q --bare "$origin"
  git init -q "$clone"
  mkdir -p "$clone/bootstrap/keyrings"
  printf 'package = x-1\n' > "$clone/bootstrap/keyrings/x.pin"
  g add -A
  g commit -q -m base
  g remote add origin "file://$origin"
  g push -q origin HEAD:refs/heads/main
  start="$(g rev-parse HEAD)"
  B=freshness/keyring-x
  n_change=0

  # prs JSON: a fresh FAKE_GH_DIR whose open pull requests are JSON. Sets gh.
  prs() {
    n_dirs=$((n_dirs + 1))
    gh="$work/gh-$n_dirs"
    mkdir -p "$gh"
    : > "$gh/calls.log"
    printf '%s\n' "$1" > "$gh/prs.json"
  }
  # propose ARGS...: run scripts/propose-change in the clone, on a new change
  # of the pin; prints "<exit> <events>"
  propose() {
    local rc=0
    n_change=$((n_change + 1))
    g reset -q --hard "$start"
    printf 'package = x-new-%s\n' "$n_change" > "$clone/bootstrap/keyrings/x.pin"
    (cd "$clone" && HOME="$work" PATH="$work/bin:$PATH" FAKE_GH_DIR="$gh" GH_TOKEN=stub \
      GITHUB_REPOSITORY=test/repo DEFAULT_BRANCH=main "$REPO_ROOT/scripts/propose-change" "$@") \
      > "$work/out" 2>&1 || rc=$?
    printf '%s %s\n' "$rc" "$(tr '\n' ';' < "$gh/calls.log" | sed 's/;$//')"
  }
  fork='{"number": 9, "headRefName": "freshness/keyring-x", "isCrossRepository": true, "author": {"login": "mallory"}}'
  own='{"number": 4, "headRefName": "freshness/keyring-x", "isCrossRepository": false, "author": {"login": "app/github-actions", "is_bot": true}}'
  P="FAKE_GH_DIR=DIR scripts/propose-change"

  prs "[$fork]"
  expect "propose-change: a fork pull request with the same branch name is not edited; a new pull request opens" \
    "0 pr-create $B;dispatch ci.yml $B" \
    "$(propose "$B" "keyring: x" "$work/body.md" bootstrap/keyrings/x.pin)" "$P $B T BODY bootstrap/keyrings/x.pin"

  prs "[$fork, $own]"
  expect "propose-change: with a fork pull request listed first, the pull request of the bot is edited" \
    "0 pr-edit 4;dispatch ci.yml $B" \
    "$(propose "$B" "keyring: x" "$work/body.md" bootstrap/keyrings/x.pin)" "$P $B T BODY bootstrap/keyrings/x.pin"

  prs "[$fork]"
  expect "propose-change --withdraw leaves a fork pull request with the same branch name open" \
    "0 " "$(propose --withdraw "$B" "note")" "$P --withdraw $B NOTE"

  prs "[$fork, $own]"
  expect "propose-change --withdraw closes the pull request of the bot" \
    "0 pr-close 4" "$(propose --withdraw "$B" "note")" "$P --withdraw $B NOTE"
fi

summary
