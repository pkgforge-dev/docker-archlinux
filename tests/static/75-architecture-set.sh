#!/usr/bin/env bash
#
# The architecture set lives in ports/*.conf, and only there.
#
#   1. scripts/ports check passes.
#   2. Each port has its files: rootfs/<arch>/etc/pacman.conf, the mirror
#      list, bootstrap/<arch>/etc/bootstrap-packages.txt and
#      mirrors/<arch>.anchors. No rootfs/, bootstrap/ or mirrors/ entry
#      belongs to a name that is not a port.
#   3. Each alias that another repository pulls by name is still an alias
#      (tests/fixtures/75-architecture-set/consumer-aliases).
#   4. ⛔ No file outside ports/, tests/fixtures/ and docs/ writes 3 or more
#      ports in one line. A port counts once, by any of its names: arch,
#      pacman_arch or an alias. A script, workflow or test reads the set from
#      scripts/ports, so a new port needs no edit there.
#   5. The `arch` line of each bootstrap/keyrings/*.pin is data that the
#      build stage reads, so the scan of 4 passes over it. It must name the
#      pacman_arch of each port whose keyring is that pin, and no other.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

PORTS="$REPO_ROOT/scripts/ports"
FX="$(fixture_dir)"

if [ ! -x "$PORTS" ]; then
  fail "scripts/ports is executable" "reproduce: ls -l scripts/ports"
  summary
  exit 1
fi

work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

#---------------------------------------------------------------------------#
# 1. scripts/ports check
#---------------------------------------------------------------------------#
rc=0
"$PORTS" check > "$work/check.out" 2> "$work/check.err" || rc=$?
if [ "$rc" -eq 0 ]; then
  ok "scripts/ports check passes"
else
  fail "scripts/ports check passes" "exit $rc: $(tr '\n' '|' < "$work/check.err")" "reproduce: scripts/ports check"
fi

mapfile -t ARCHES < <("$PORTS" list)

# is_port NAME -> 0 when NAME is a port
is_port() {
  local a
  for a in "${ARCHES[@]}"; do
    [ "$a" = "$1" ] && return 0
  done
  return 1
}

if [ "${#ARCHES[@]}" -eq 0 ]; then
  fail "scripts/ports lists the ports" "it lists none" "reproduce: scripts/ports list"
  summary
  exit 1
fi

#---------------------------------------------------------------------------#
# 2. The files of each port, and no file of a name that is not a port.
#---------------------------------------------------------------------------#
for arch in "${ARCHES[@]}"; do
  absent=""
  for p in "rootfs/$arch/etc/pacman.conf" "rootfs/$arch/etc/pacman.d/mirrorlist" \
    "bootstrap/$arch/etc/bootstrap-packages.txt" "mirrors/$arch.anchors"; do
    [ -f "$REPO_ROOT/$p" ] || absent="$absent $p"
  done
  if [ -z "$absent" ]; then
    ok "$arch has its rootfs, bootstrap and mirrors files"
  else
    fail "$arch has its rootfs, bootstrap and mirrors files" "not in the tree:$absent" "reproduce: ls$absent"
  fi
done

# rootfs/any, bootstrap/any, bootstrap/keyrings and bootstrap/pacman-static
# serve every port.
orphans=""
for d in rootfs bootstrap; do
  [ -d "$REPO_ROOT/$d" ] || continue
  for sub in "$REPO_ROOT/$d"/*/; do
    [ -d "$sub" ] || continue
    name="$(basename "$sub")"
    case "$name" in any | keyrings | pacman-static) continue ;; esac
    is_port "$name" || orphans="$orphans $d/$name"
  done
done
if [ -d "$REPO_ROOT/mirrors" ]; then
  for f in "$REPO_ROOT"/mirrors/*; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    is_port "${name%%.*}" || orphans="$orphans mirrors/$name"
  done
fi
if [ -z "$orphans" ]; then
  ok "no rootfs, bootstrap or mirrors entry belongs to a name that is not a port"
else
  fail "no rootfs, bootstrap or mirrors entry belongs to a name that is not a port" "entries:$orphans" \
    "either ports/ lost a port, or these files outlived one" "reproduce: ls -d$orphans; scripts/ports list"
fi

#---------------------------------------------------------------------------#
# 3. The aliases that other repositories pull.
#---------------------------------------------------------------------------#
for arch in "${ARCHES[@]}"; do
  "$PORTS" aliases "$arch"
done > "$work/aliases"
if [ ! -f "$FX/consumer-aliases" ]; then
  fail "the consumer alias fixture exists" "reproduce: ls tests/fixtures/75-architecture-set/consumer-aliases"
else
  lost="$(awk 'NR == FNR { a[$1] = 1; next } !/^#/ && NF && !($1 in a) { printf "%s ", $1 }' "$work/aliases" "$FX/consumer-aliases")"
  n_consumed="$(awk '!/^#/ && NF' "$FX/consumer-aliases" | awk 'END { print NR + 0 }')"
  if [ "$n_consumed" -gt 0 ] && [ -z "$lost" ]; then
    ok "each of the $n_consumed aliases that mirror-archlinux pulls is an alias of a port"
  else
    fail "each alias that mirror-archlinux pulls is an alias of a port" "not an alias: ${lost:-none}; listed: $n_consumed" \
      "⛔ never rename or drop an alias" "reproduce: scripts/ports field aliases"
  fi
fi

#---------------------------------------------------------------------------#
# 4. No list of 3 or more ports outside ports/, tests/fixtures/ and docs/.
#---------------------------------------------------------------------------#
# Each name of each port: arch, pacman_arch and the aliases.
for arch in "${ARCHES[@]}"; do
  {
    printf '%s\n' "$arch"
    "$PORTS" get "$arch" pacman_arch
    "$PORTS" aliases "$arch"
  } | awk -v a="$arch" 'NF { print $1 "\t" a }'
done | LC_ALL=C sort -u > "$work/names"

# The files: tracked and new files from git, or every file when there is no
# git. A file that git lists and that is gone from the tree is passed over.
rc=0
if git -C "$REPO_ROOT" rev-parse --git-dir > "$work/gitdir" 2> "$work/git.err"; then
  git -C "$REPO_ROOT" ls-files -z -co --exclude-standard > "$work/files0" || rc=$?
else
  (cd "$REPO_ROOT" && find . -path ./.git -prune -o -type f -print0) > "$work/files0" || rc=$?
fi
if [ "$rc" -ne 0 ]; then
  fail "the files of the tree can be listed" "exit $rc" "reproduce: git ls-files -co --exclude-standard"
  summary
  exit 1
fi
: > "$work/files"
while IFS= read -r -d '' f; do
  f="${f#./}"
  case "$f" in
    ports/* | tests/fixtures/* | docs/*) continue ;;
  esac
  [ -f "$REPO_ROOT/$f" ] || continue
  printf '%s\n' "$f" >> "$work/files"
done < "$work/files0"

n_files="$(awk 'END { print NR + 0 }' "$work/files")"
: > "$work/hits"
# Binary files are passed over: grep -I lists the text files. grep exits 1
# when it lists none, and 2 when it cannot read a file.
mapfile -t all < "$work/files"
text=()
if [ "${#all[@]}" -gt 0 ]; then
  rc=0
  (cd "$REPO_ROOT" && grep -Il . "${all[@]}") > "$work/text" 2> "$work/grep.err" || rc=$?
  case "$rc" in
    0 | 1) mapfile -t text < "$work/text" ;;
    *)
      fail "each file of the tree can be read" "grep exited $rc: $(tr '\n' ' ' < "$work/grep.err")" \
        "reproduce: git ls-files -co --exclude-standard | xargs grep -Il ."
      ;;
  esac
fi
if [ "$n_files" -gt 0 ]; then
  if [ "${#text[@]}" -gt 0 ]; then
    (cd "$REPO_ROOT" && LC_ALL=C awk -F'\t' '
      NR == FNR { port[$1] = $2; next }
      # The arch line of a keyring pin: section 5 checks it.
      FILENAME ~ /^bootstrap\/keyrings\/[^\/]+\.pin$/ && /^[[:space:]]*arch[[:space:]]*=/ { next }
      {
        line = $0
        n = 0
        delete seen
        list = ""
        gsub(/[^A-Za-z0-9_]+/, " ", line)
        m = split(line, w, " ")
        for (i = 1; i <= m; i++) {
          if ((w[i] in port) && !(port[w[i]] in seen)) {
            seen[port[w[i]]] = 1
            n++
            list = list " " port[w[i]]
          }
        }
        if (n >= 3) printf "%s:%d:%s\n", FILENAME, FNR, list
      }' "$work/names" "${text[@]}") > "$work/hits"
  fi
fi

n_hits="$(awk 'END { print NR + 0 }' "$work/hits")"
if [ "$n_files" -eq 0 ]; then
  fail "the scan found files to read" "no file outside ports/, tests/fixtures/ and docs/" \
    "reproduce: git ls-files -co --exclude-standard"
elif [ "$n_hits" -eq 0 ]; then
  ok "no file of $n_files writes 3 or more ports in one line"
else
  # One assertion for each file, with each line.
  awk -F: '{ print $1 }' "$work/hits" | LC_ALL=C sort -u > "$work/hit-files"
  while IFS= read -r f; do
    fail "$f writes no list of 3 or more ports" \
      "$(awk -F: -v f="$f" '$1 == f { printf "line %s:%s; ", $2, $3 }' "$work/hits")" \
      "read the set from scripts/ports (list, field, matrix) instead" \
      "reproduce: sed -n '$(awk -F: -v f="$f" '$1 == f { print $2; exit }' "$work/hits")p' $f"
  done < "$work/hit-files"
fi

#---------------------------------------------------------------------------#
# 5. The arch line of each keyring pin is the set of its ports.
#---------------------------------------------------------------------------#
n_pins=0
for pin in "$REPO_ROOT"/bootstrap/keyrings/*.pin; do
  [ -f "$pin" ] || continue
  n_pins=$((n_pins + 1))
  name="$(basename "$pin" .pin)"
  got="$(awk '/^[[:space:]]*arch[[:space:]]*=/ { sub(/^[^=]*=/, ""); for (i = 1; i <= NF; i++) print $i }' "$pin" |
    LC_ALL=C sort -u | awk '{ printf "%s ", $0 }')"
  want="$(for arch in "${ARCHES[@]}"; do
    if [ "$("$PORTS" get "$arch" keyring)" = "$name" ]; then
      "$PORTS" get "$arch" pacman_arch
    fi
  done | LC_ALL=C sort -u | awk '{ printf "%s ", $0 }')"
  if [ -n "$want" ] && [ "$got" = "$want" ]; then
    ok "bootstrap/keyrings/$name.pin names the pacman_arch of each port with keyring = $name"
  else
    fail "bootstrap/keyrings/$name.pin names the pacman_arch of each port with keyring = $name" \
      "the pin: '${got% }'; the ports: '${want% }'" \
      "a pin that no port names, or a port that its pin does not name, gets no keyring" \
      "reproduce: grep -n '^arch' bootstrap/keyrings/$name.pin; scripts/ports field keyring"
  fi
done
if [ "$n_pins" -eq 0 ]; then
  fail "bootstrap/keyrings has a pin" "no *.pin file" "reproduce: ls bootstrap/keyrings"
fi

summary
