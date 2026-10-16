# shellcheck shell=bash
#
# Shared functions for the scripts in this directory. Sourced, never executed.
#
#   . "$(dirname "$0")/lib.sh"
#
# Set PROG before you source this file. Messages start with "$PROG: ".
#
# The sections:
#   messages       die, warn, note
#   conf files     conf_get, conf_keys, conf_check_grammar
#   http           http_get: one GET with deadlines and bounded retries
#   registries     reg_host, reg_token, reg_head, reg_get, reg_blob, reg_tags,
#                  reg_head_limit
#
# Rules that every function here keeps:
#   - Every curl call has --connect-timeout and --max-time.
#   - A function returns a status. It does not exit, except die.
#   - "Absent" is a registry answer (404 with a not-found code). Every other
#     failure is an error, never an absence.

: "${PROG:=lib}"

#---------------------------------------------------------------------------#
# Messages
#---------------------------------------------------------------------------#

# die MESSAGE [DETAIL ...]
die() {
  echo "$PROG: $1" >&2
  shift
  while [ "$#" -gt 0 ]; do
    echo "  $1" >&2
    shift
  done
  exit 1
}

warn() {
  echo "$PROG: warning: $*" >&2
}

note() {
  echo "$PROG: $*" >&2
}

# need COMMAND...
need() {
  local c
  for c in "$@"; do
    command -v "$c" > /dev/null || die "$c is required and is not on PATH"
  done
}

#---------------------------------------------------------------------------#
# Conf files: `key = value`, one per line, `#` starts a comment line.
#
# A conf file is data. It is parsed, never sourced. A key that occurs twice
# is an error, because the second value would win without a word.
#---------------------------------------------------------------------------#

# conf_get FILE KEY
# Prints the value of KEY. Returns 1 when FILE has no KEY, 2 when FILE has
# KEY more than once or cannot be read.
conf_get() {
  local file="$1" key="$2" rc=0 out
  [ -r "$file" ] || return 2
  out="$(awk -v k="$key" '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    {
      line = $0
      eq = index(line, "=")
      if (eq == 0) next
      name = substr(line, 1, eq - 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
      if (name != k) next
      val = substr(line, eq + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
      n++
      v = val
    }
    END {
      if (n == 0) exit 1
      if (n > 1) exit 2
      print v
    }' "$file")" || rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  printf '%s\n' "$out"
}

# conf_keys FILE
# Prints every key of FILE, one per line, in file order.
conf_keys() {
  awk '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    {
      eq = index($0, "=")
      if (eq == 0) { print "!" $0; next }
      name = substr($0, 1, eq - 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
      print name
    }' "$1"
}

#---------------------------------------------------------------------------#
# HTTP
#---------------------------------------------------------------------------#

# The User-Agent of every request this repository makes. A server operator
# who reads it can find the source.
HTTP_UA="${HTTP_UA:-docker-archlinux (+https://github.com/${GITHUB_REPOSITORY:-pkgforge-dev/docker-archlinux})}"

# http_get URL OUT [CURL_ARG ...]
# One GET. Writes the body to OUT and prints the HTTP status code (000 when no
# answer came). Retries a transient failure (no answer, 429, 5xx) up to
# HTTP_TRIES times (default 3), with a pause of 5, 10, 20 s. Returns 0 when a
# status was received, 1 when no attempt got an answer.
http_get() {
  local url="$1" out="$2" tries="${HTTP_TRIES:-3}" n=0 code rc pause=5
  shift 2
  while :; do
    n=$((n + 1))
    rc=0
    code="$(curl -sS -L --connect-timeout "${HTTP_CONNECT_TIMEOUT:-15}" \
      --max-time "${HTTP_MAX_TIME:-120}" -A "$HTTP_UA" \
      -o "$out" -w '%{http_code}' "$@" "$url")" || rc=$?
    [ -n "$code" ] || code=000
    case "$code" in
      000 | 429 | 5[0-9][0-9]) ;;
      *)
        printf '%s\n' "$code"
        return 0
        ;;
    esac
    if [ "$n" -ge "$tries" ]; then
      printf '%s\n' "$code"
      [ "$code" != 000 ] && return 0
      warn "no answer from $url after $n attempts (curl exit $rc)"
      return 1
    fi
    sleep "$pause"
    pause=$((pause * 2))
  done
}

#---------------------------------------------------------------------------#
# Registries (OCI distribution API)
#
# REGISTRY is the name a user writes: ghcr.io, docker.io, quay.io. reg_host
# gives the API host. A token comes from the realm that the registry names in
# its WWW-Authenticate challenge, so no token endpoint is written here.
#
# Credentials are optional. Set REG_USER_<NAME> and REG_PASS_<NAME>, where
# NAME is the registry with every character outside [A-Za-z0-9] as _, for
# example REG_USER_docker_io. Without them every read is anonymous.
#---------------------------------------------------------------------------#

REG_ACCEPT="application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json"

reg_host() {
  case "$1" in
    docker.io | index.docker.io | registry-1.docker.io) printf 'registry-1.docker.io\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# reg_cred_var KIND REGISTRY -> the name of the variable that holds it.
reg_cred_var() {
  local n
  n="$(printf '%s' "$2" | tr -c 'A-Za-z0-9' '_')"
  printf 'REG_%s_%s\n' "$1" "$n"
}

# reg_token REGISTRY REPO
# Prints a pull token for REPO (empty when the registry needs none). Returns 1
# when the registry cannot be read, 3 when the token endpoint refuses the
# repository with 401, 403 or 404. For an anonymous read that means the
# repository does not exist or is not public: GHCR answers 403 for both.
reg_token() {
  local registry="$1" repo="$2" host work code realm service user pass uvar pvar
  host="$(reg_host "$registry")"
  work="$(mktemp -d)"
  code="$(HTTP_TRIES=2 http_get "https://$host/v2/" "$work/body" -D "$work/hdr")" || {
    rm -rf "$work"
    return 1
  }
  if [ "$code" = 200 ]; then
    rm -rf "$work"
    printf '\n'
    return 0
  fi
  realm="$(awk 'tolower($0) ~ /^www-authenticate: *bearer/ {
      if (match($0, /realm="[^"]*"/)) print substr($0, RSTART + 7, RLENGTH - 8)
    }' "$work/hdr" | tr -d '\r' | awk 'NR == 1')"
  service="$(awk 'tolower($0) ~ /^www-authenticate: *bearer/ {
      if (match($0, /service="[^"]*"/)) print substr($0, RSTART + 9, RLENGTH - 10)
    }' "$work/hdr" | tr -d '\r' | awk 'NR == 1')"
  if [ -z "$realm" ]; then
    warn "$host answered HTTP $code to /v2/ with no Bearer challenge"
    rm -rf "$work"
    return 1
  fi
  uvar="$(reg_cred_var USER "$registry")"
  pvar="$(reg_cred_var PASS "$registry")"
  user="${!uvar:-}"
  pass="${!pvar:-}"
  local auth=()
  if [ -n "$user" ] && [ -n "$pass" ]; then
    auth=(-u "$user:$pass")
  fi
  code="$(http_get "$realm?service=$service&scope=repository:$repo:pull" "$work/token" "${auth[@]}")" || {
    rm -rf "$work"
    return 1
  }
  case "$code" in
    200) ;;
    401 | 403 | 404)
      rm -rf "$work"
      return 3
      ;;
    *)
      warn "the token endpoint $realm answered HTTP $code for $repo"
      rm -rf "$work"
      return 1
      ;;
  esac
  jq -r '.token // .access_token // empty' "$work/token" | tr -d '\r'
  rm -rf "$work"
}

# reg_head REGISTRY REPO REF [TOKEN]
# Prints "<http code> <digest>". The digest is empty unless the code is 200.
# Returns 1 only when no answer came. A caller decides what a code means:
# 404 is absent, every other code is an error. A repository that the token
# endpoint refuses (reg_token status 3) prints "404 ".
reg_head() {
  local registry="$1" repo="$2" ref="$3" token="${4-}" host work code digest rc=0
  host="$(reg_host "$registry")"
  if [ "$#" -lt 4 ]; then
    token="$(reg_token "$registry" "$repo")" || rc=$?
    case "$rc" in
      0) ;;
      3)
        printf '404 \n'
        return 0
        ;;
      *) return 1 ;;
    esac
  fi
  work="$(mktemp -d)"
  local hdrs=(-H "Accept: $REG_ACCEPT")
  [ -n "$token" ] && hdrs+=(-H "Authorization: Bearer $token")
  code="$(http_get "https://$host/v2/$repo/manifests/$ref" "$work/body" -I -D "$work/hdr" "${hdrs[@]}")" || {
    rm -rf "$work"
    return 1
  }
  digest=""
  if [ "$code" = 200 ]; then
    digest="$(awk 'tolower($1) == "docker-content-digest:" { print $2 }' "$work/hdr" | tr -d '\r' | awk 'END { print }')"
  fi
  rm -rf "$work"
  printf '%s %s\n' "$code" "$digest"
}

# reg_get REGISTRY REPO REF OUT [TOKEN]
# Writes the manifest or index to OUT and prints the HTTP code.
reg_get() {
  local registry="$1" repo="$2" ref="$3" out="$4" token="${5-}" host
  host="$(reg_host "$registry")"
  if [ "$#" -lt 5 ]; then
    token="$(reg_token "$registry" "$repo")" || return 1
  fi
  local hdrs=(-H "Accept: $REG_ACCEPT")
  [ -n "$token" ] && hdrs+=(-H "Authorization: Bearer $token")
  http_get "https://$host/v2/$repo/manifests/$ref" "$out" "${hdrs[@]}"
}

# reg_blob REGISTRY REPO DIGEST OUT [TOKEN]
# Writes the blob to OUT, checks its sha256, and prints the HTTP code.
# Returns 1 on no answer or on a digest mismatch.
reg_blob() {
  local registry="$1" repo="$2" digest="$3" out="$4" token="${5-}" host code got
  host="$(reg_host "$registry")"
  if [ "$#" -lt 5 ]; then
    token="$(reg_token "$registry" "$repo")" || return 1
  fi
  local hdrs=()
  [ -n "$token" ] && hdrs+=(-H "Authorization: Bearer $token")
  code="$(http_get "https://$host/v2/$repo/blobs/$digest" "$out" "${hdrs[@]}")" || return 1
  if [ "$code" = 200 ]; then
    got="sha256:$(sha256sum "$out" | awk '{ print $1 }')"
    if [ "$got" != "$digest" ]; then
      warn "blob $digest of $repo on $registry hashes to $got"
      return 1
    fi
  fi
  printf '%s\n' "$code"
}

# reg_tags REGISTRY REPO OUT
# Writes every tag of REPO to OUT, one per line, every page through the Link
# header. Returns 0 when the list is complete (empty for a repository that
# does not exist), 1 when it could not be read.
reg_tags() {
  local registry="$1" repo="$2" out="$3" host token work next code pages=0 name rc=0
  host="$(reg_host "$registry")"
  : > "$out"
  token="$(reg_token "$registry" "$repo")" || rc=$?
  case "$rc" in
    0) ;;
    3) return 0 ;;
    *) return 1 ;;
  esac
  work="$(mktemp -d)"
  : > "$out"
  next="/v2/$repo/tags/list?n=1000"
  while [ -n "$next" ]; do
    pages=$((pages + 1))
    if [ "$pages" -gt "${REG_TAGS_MAX_PAGES:-200}" ]; then
      warn "$repo on $registry still pages after $pages pages"
      rm -rf "$work"
      return 1
    fi
    local hdrs=()
    [ -n "$token" ] && hdrs+=(-H "Authorization: Bearer $token")
    code="$(http_get "https://$host$next" "$work/page" -D "$work/hdr" "${hdrs[@]}")" || {
      rm -rf "$work"
      return 1
    }
    if [ "$code" = 404 ] && [ "$pages" -eq 1 ]; then
      rm -rf "$work"
      return 0
    fi
    if [ "$code" != 200 ]; then
      warn "page $pages of the tag list of $repo on $registry answered HTTP $code"
      rm -rf "$work"
      return 1
    fi
    name="$(jq -r '.name // empty' "$work/page" | tr -d '\r')"
    if [ "$name" != "$repo" ] && [ "${name#library/}" != "$repo" ]; then
      warn "page $pages from $registry is not a tag list of $repo"
      rm -rf "$work"
      return 1
    fi
    jq -r '.tags // [] | .[]' "$work/page" | tr -d '\r' >> "$out"
    next="$(awk 'tolower($1) == "link:" {
        if (match($0, /<[^>]*>/)) print substr($0, RSTART + 1, RLENGTH - 2)
      }' "$work/hdr" | tr -d '\r' | awk 'END { print }')"
    case "$next" in
      "" | /*) ;;
      https://*) next="/${next#https://*/}" ;;
      *) next="/$next" ;;
    esac
  done
  rm -rf "$work"
}

# reg_head_limit REGISTRY REPO REF [TOKEN]
# As reg_head, with a third field: the count of the ratelimit-remaining
# header. Docker Hub sends it, and does not count the HEAD itself. Prints
# "<http code> <digest> <remaining>". An empty field is -, so that read
# splits the line into three fields.
reg_head_limit() {
  local registry="$1" repo="$2" ref="$3" token="${4-}" host work code digest left rc=0
  host="$(reg_host "$registry")"
  if [ "$#" -lt 4 ]; then
    token="$(reg_token "$registry" "$repo")" || rc=$?
    case "$rc" in
      0) ;;
      3)
        printf '404 - -\n'
        return 0
        ;;
      *) return 1 ;;
    esac
  fi
  work="$(mktemp -d)"
  local hdrs=(-H "Accept: $REG_ACCEPT")
  [ -n "$token" ] && hdrs+=(-H "Authorization: Bearer $token")
  code="$(http_get "https://$host/v2/$repo/manifests/$ref" "$work/body" -I -D "$work/hdr" "${hdrs[@]}")" || {
    rm -rf "$work"
    return 1
  }
  digest=""
  if [ "$code" = 200 ]; then
    digest="$(awk 'tolower($1) == "docker-content-digest:" { print $2 }' "$work/hdr" | tr -d '\r' | awk 'END { print }')"
  fi
  left="$(awk 'tolower($1) == "ratelimit-remaining:" { v = $2; sub(/;.*/, "", v); print v }' "$work/hdr" |
    tr -d '\r' | awk 'END { print }')"
  [[ "$left" =~ ^[0-9]+$ ]] || left="-"
  rm -rf "$work"
  printf '%s %s %s\n' "$code" "${digest:--}" "$left"
}
