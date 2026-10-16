#!/usr/bin/env bash
#
# Each pacman hook that ships is complete, and the program it runs is there.
#
# alpm reads each file in /etc/pacman.d/hooks before a transaction. A hook
# with no trigger operation stops the transaction ("Missing trigger operation
# in hook"). An Exec that is not there stops it too ("command failed to
# execute correctly"). The consumer's pacman -Syu then stops on a file of
# this image.
#
# For each hook in rootfs/any/etc/pacman.d/hooks:
#   1. Operation, Type, Target, When and Exec are there
#   2. one [Trigger] and one [Action]
#   3. When is PreTransaction or PostTransaction
#   4. a path under /usr/local in Exec is a file in rootfs/any
#   5. Depends names the package of each program that Exec runs. The table
#      OWNERS below gives the package of each program; a program that is not
#      in the table fails, so a new hook adds its line.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

HOOKDIR="$REPO_ROOT/rootfs/any/etc/pacman.d/hooks"
SHIPPED="$REPO_ROOT/rootfs/any"

# The package that owns each program a hook runs (pacman -Qo on Arch Linux).
OWNERS="/usr/bin/find findutils
/bin/sh bash
/usr/bin/sh bash
/usr/bin/bash bash"

if [ ! -d "$HOOKDIR" ]; then
  fail "the hook directory exists" \
    "looked for: rootfs/any/etc/pacman.d/hooks" \
    "reproduce: ls rootfs/any/etc/pacman.d/hooks"
  summary
  exit 1
fi

hooks="$(find "$HOOKDIR" -maxdepth 1 -type f -name '*.hook' | sort)"
if [ -z "$hooks" ]; then
  fail "at least one hook ships" \
    "the directory has no .hook file" \
    "⚠ alpm reads only files whose name ends in .hook" \
    "reproduce: ls rootfs/any/etc/pacman.d/hooks"
  summary
  exit 1
fi

# directive FILE KEY -> each value of KEY, one per line, comments removed
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

  # 1. The directives that alpm needs
  missing=""
  for key in Operation Type Target When Exec; do
    if [ -z "$(directive "$hook" "$key")" ]; then
      missing="$missing $key"
    fi
  done
  if [ -z "$missing" ]; then
    ok "$rel has Operation, Type, Target, When and Exec"
  else
    fail "$rel has Operation, Type, Target, When and Exec" \
      "missing:$missing" \
      "alpm stops the transaction of the consumer on an incomplete hook" \
      "reproduce: cat $rel"
  fi

  # 2. Both section headers. A directive outside its section is not read.
  sections="$(grep_matches '^[[:space:]]*\[(Trigger|Action)\][[:space:]]*$' "$hook")"
  found="$(awk 'NF { n++ } END { print n + 0 }' <<< "$sections")"
  if [ "$found" -eq 2 ]; then
    ok "$rel has one [Trigger] and one [Action]"
  else
    fail "$rel has one [Trigger] and one [Action]" \
      "found $found section header(s)" \
      "reproduce: grep -nE '^\[(Trigger|Action)\]' $rel"
  fi

  # 3. When
  when="$(directive "$hook" When)"
  case "$when" in
    PreTransaction | PostTransaction)
      ok "$rel runs $when"
      ;;
    *)
      fail "$rel runs PreTransaction or PostTransaction" \
        "found: ${when:-nothing}" \
        "alpm refuses any other value" \
        "reproduce: grep -n When $rel"
      ;;
  esac

  # 4. A path under /usr/local belongs to this repository, so it must ship.
  exec_line="$(directive "$hook" Exec)"
  local_paths="$(tr ' ' '\n' <<< "$exec_line" | awk '/^\/usr\/local\//')"
  if [ -z "$local_paths" ]; then
    ok "$rel runs no path under /usr/local"
  else
    absent=""
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      [ -f "$SHIPPED$p" ] || absent="$absent $p"
    done <<< "$local_paths"
    if [ -z "$absent" ]; then
      ok "$rel runs $(tr '\n' ' ' <<< "$local_paths")and it ships in rootfs/any"
    else
      fail "each /usr/local path that $rel runs ships in rootfs/any" \
        "not in rootfs/any:$absent" \
        "the hook ships and its program does not, so each transaction of a consumer fails" \
        "reproduce: ls rootfs/any$(awk '{ print $1 }' <<< "$absent")"
    fi
  fi

  # 5. Depends names the package of the program that Exec runs.
  deps="$(directive "$hook" Depends)"
  program="$(awk '{ print $1 }' <<< "$exec_line")"
  owner="$(awk -v p="$program" '$1 == p { print $2 }' <<< "$OWNERS")"
  if [ -z "$owner" ]; then
    fail "the table OWNERS in this test names the package of $program, which $rel runs" \
      "add a line: $program <package>, from pacman -Qo $program" \
      "reproduce: grep -n Exec $rel"
  elif grep -qxF -e "$owner" <<< "$deps"; then
    ok "$rel depends on $owner, which owns $program"
  else
    fail "$rel depends on $owner, which owns $program" \
      "Depends: $(tr '\n' ' ' <<< "$deps")" \
      "alpm skips a hook whose Depends is not installed, and runs a hook whose program is missing" \
      "reproduce: grep -n 'Depends\|Exec' $rel"
  fi
done <<< "$hooks"

printf '# checked %d hook(s)\n' "$count"

summary
