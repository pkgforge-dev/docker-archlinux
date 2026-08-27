#!/usr/bin/env bash
#
# A shipped pacman hook runs inside every consumer's transaction, so a broken
# one breaks them and not us.
#
# alpm reads every file in /etc/pacman.d/hooks/ before it does anything. A hook
# missing a required directive aborts the transaction with
#   error: Missing trigger operation in hook
# and a hook whose Exec is not there aborts it with
#   error: command failed to execute correctly
# Either way the consumer's pacman -Syu stops, on a file this repository put in
# their image. Nothing about that is visible from a build that succeeded.
#
# So each shipped hook is checked for the directives alpm requires, and every
# Exec under /usr/local is checked to be a file this repository actually ships.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

HOOKDIR="$REPO_ROOT/rootfs/any/etc/pacman.d/hooks"
SHIPPED="$REPO_ROOT/rootfs/any"

if [ ! -d "$HOOKDIR" ]; then
  fail "the shipped hook directory exists" \
    "looked for: rootfs/any/etc/pacman.d/hooks" \
    "reproduce: ls rootfs/any/etc/pacman.d/hooks"
  summary
  exit 1
fi

hooks="$(find "$HOOKDIR" -maxdepth 1 -type f -name '*.hook' | sort)"
if [ -z "$hooks" ]; then
  fail "at least one hook ships" \
    "the directory is there and holds no .hook file" \
    "⚠ alpm only reads files whose name ends .hook, so one named otherwise never runs" \
    "reproduce: ls rootfs/any/etc/pacman.d/hooks"
  summary
  exit 1
fi

# directive FILE KEY -> every value of KEY, one per line, comments stripped
directive() {
  awk -v k="$2" -F= '
    { sub(/^[[:space:]]*#.*$/, "") }
    $0 ~ "^[[:space:]]*" k "[[:space:]]*=" {
      sub(/^[^=]*=[[:space:]]*/, "")
      sub(/[[:space:]]+$/, "")
      if ($0 != "") print
    }
  ' "$1" | tr -d '\r'
}

count=0
while IFS= read -r hook; do
  [ -n "$hook" ] || continue
  count=$((count + 1))
  rel="${hook#"$REPO_ROOT/"}"

  #-------------------------------------------------------------------------#
  # 1. The directives alpm refuses to start without.
  #
  # Operation, Type and Target belong to [Trigger]. When and Exec belong to
  # [Action]. alpm rejects the hook when any of the five is absent.
  #-------------------------------------------------------------------------#
  missing=""
  for key in Operation Type Target When Exec; do
    if [ -z "$(directive "$hook" "$key")" ]; then
      missing="$missing $key"
    fi
  done
  if [ -z "$missing" ]; then
    ok "$rel declares Operation, Type, Target, When and Exec"
  else
    fail "$rel declares Operation, Type, Target, When and Exec" \
      "missing:$missing" \
      "alpm refuses the whole transaction over one incomplete hook, in the consumer's image" \
      "reproduce: cat $rel"
  fi

  #-------------------------------------------------------------------------#
  # 2. Both section headers, since a directive outside its section is ignored.
  #-------------------------------------------------------------------------#
  sections="$(grep_matches '^[[:space:]]*\[(Trigger|Action)\][[:space:]]*$' "$hook")"
  found="$(printf '%s\n' "$sections" | awk 'NF' | wc -l | tr -d '[:space:]')"
  if [ "$found" -eq 2 ]; then
    ok "$rel carries one [Trigger] and one [Action]"
  else
    fail "$rel carries one [Trigger] and one [Action]" \
      "matched $found section header(s)" \
      "a directive in no section, or in the wrong one, is read as part of the previous section" \
      "reproduce: grep -nE '^\[(Trigger|Action)\]' $rel"
  fi

  #-------------------------------------------------------------------------#
  # 3. When is a value alpm knows.
  #-------------------------------------------------------------------------#
  when="$(directive "$hook" When)"
  case "$when" in
    PreTransaction | PostTransaction)
      ok "$rel runs $when"
      ;;
    *)
      fail "$rel runs PreTransaction or PostTransaction" \
        "found: ${when:-nothing}" \
        "any other value is rejected when alpm parses the hook" \
        "reproduce: grep -n When $rel"
      ;;
  esac

  #-------------------------------------------------------------------------#
  # 4. Exec names something. Anything under /usr/local is this repository's,
  #    so it has to be a file that ships. Anything else comes from a package
  #    and Depends is what makes that a requirement rather than a hope.
  #-------------------------------------------------------------------------#
  exec_line="$(directive "$hook" Exec)"
  # The interpreter may come first, so every absolute path on the line is
  # checked rather than only the first word.
  local_paths="$(printf '%s\n' "$exec_line" | tr ' ' '\n' | awk '/^\/usr\/local\//')"
  if [ -z "$local_paths" ]; then
    ok "$rel runs only paths that come from packages"
  else
    absent=""
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      [ -f "$SHIPPED$p" ] || absent="$absent $p"
    done <<< "$local_paths"
    if [ -z "$absent" ]; then
      ok "$rel runs $(printf '%s' "$local_paths" | tr '\n' ' '), which ships in rootfs/any"
    else
      fail "every /usr/local path $rel runs ships in rootfs/any" \
        "not shipped:$absent" \
        "the hook is in the image and the program it runs is not, so every consumer transaction fails" \
        "reproduce: ls rootfs/any$(printf '%s' "$absent" | awk '{ print $1 }')"
    fi
  fi

  #-------------------------------------------------------------------------#
  # 5. Depends, so alpm reports a missing tool by name instead of the hook
  #    failing partway through.
  #-------------------------------------------------------------------------#
  deps="$(directive "$hook" Depends)"
  if [ -n "$deps" ]; then
    ok "$rel declares Depends: $(printf '%s' "$deps" | tr '\n' ' ')"
  else
    fail "$rel declares Depends" \
      "no Depends line" \
      "without it a hook whose tool was removed fails mid transaction rather than being skipped" \
      "reproduce: grep -n Depends $rel"
  fi
done <<< "$hooks"

printf '# checked %d shipped hook(s)\n' "$count"

summary
