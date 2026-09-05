#!/usr/bin/env bash
#
# catalog.sh — registered search paths and bare-name resolution.
#
# Layout and runner own the behavior of the elements they load. Catalog owns only
# the shared trust boundary: which directories are registered, their priority,
# resolving/listing bare names within them, and reading their declared metadata.
# Paths are session-owned collections.

# shellcheck shell=bash

_catalog_namespace () { printf 'path-%s' "$1"; }   # <kind> -> collection namespace
_catalog_error () { printf 'airline: %s\n' "$*" >&2; return 2; }

# Register one shipped directory at the low-priority end of a kind's path. Missing
# optional directories are ignored; collection registration is idempotent.
catalog_register_builtin () {   # <session> <kind> <dir>
  local session="$1" kind="$2" dir="$3"
  [[ -d "$dir" ]] || return 0
  coll_register session "$session" "$(_catalog_namespace "$kind")" "$dir"
}

catalog_paths () {   # <session> <kind> -> space-delimited priority order
  coll_members session "$1" "$(_catalog_namespace "$2")"
}

# Resolve a bare name to the first file on the kind's path. A slash is rejected:
# callers must use their explicit load operation for a literal path.
catalog_resolve () {   # <session> <kind> <bare-name>
  local session="$1" kind="$2" name="$3" dir
  [[ "$name" != */* ]] || return
  for dir in $(catalog_paths "$session" "$kind"); do
    [[ -f "$dir/$name" ]] && { printf '%s' "$dir/$name"; return; }
  done
}

# List every resolvable bare name once, in path priority order. A name in a
# higher-priority directory shadows the same name in later directories.
catalog_list () {   # <session> <kind>
  local session="$1" kind="$2" dir f name seen=" "
  for dir in $(catalog_paths "$session" "$kind"); do
    [[ -d "$dir" ]] || continue
    for f in "$dir"/*; do
      [[ -f "$f" ]] || continue
      name="${f##*/}"
      case "$seen" in *" $name "*) continue ;; esac
      seen+="$name "
      printf '%s\n' "$name"
    done
  done
}

# Element metadata is declared in marked header comments and read without executing
# the file. Inspection must not run a catalog element: adapters and palettes are
# side-effecting snippets, so sourcing one to read its summary would apply it.
#
#   #| summary: Check one or more HTTP endpoints
#   #| usage: <endpoint> [<endpoint>...]
#
# The value is the rest of the line verbatim, so there are no quoting or line
# continuation rules to get wrong; a field that will not fit on one line does not
# belong here. Scanning stops at the first line that is neither blank nor a comment,
# which bounds the read and keeps declarations in the header.
#
# Emits key<TAB>value records in file order, or one value when a key is named.
# Returns non-zero when a named key is absent, so callers can distinguish an absent
# field from an empty one.
catalog_metadata () {   # <file> [<key>]
  local file="$1" wanted="${2:-}" line key value seen=" " found=""
  local meta_re='^#\|[[:space:]]*([a-z][a-z-]*):[[:space:]]?(.*)$'
  [[ -f "$file" ]] || { _catalog_error "metadata: no such file: $file"; return; }
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "${line//[[:space:]]/}" ]] || continue
    [[ "$line" == '#'* ]] || break
    [[ "$line" == '#|'* ]] || continue
    [[ "$line" =~ $meta_re ]] || {
      _catalog_error "metadata: malformed marker in $file: $line"; return
    }
    key="${BASH_REMATCH[1]}"; value="${BASH_REMATCH[2]}"
    case "$seen" in
      *" $key "*) _catalog_error "metadata: duplicate '$key' in $file"; return ;;
    esac
    seen+="$key "
    if [[ -z "$wanted" ]]; then
      printf '%s\t%s\n' "$key" "$value"
    elif [[ "$key" == "$wanted" ]]; then
      printf '%s' "$value"; found=1
    fi
  done < "$file"
  [[ -z "$wanted" || -n "$found" ]]
}

# Register a user directory at the high-priority end of the path. Registration is
# the trust decision that allows later bare-name use to source executable content.
catalog_register () {   # <session> <kind> <dir>
  local session="$1" kind="$2" dir="${3:-}"
  (( $# == 3 )) || { _catalog_error "$kind register: need exactly one <dir>"; return; }
  [[ -d "$dir" ]] || { _catalog_error "$kind register: no such directory: $dir"; return; }
  coll_prepend session "$session" "$(_catalog_namespace "$kind")" "$dir"
}

# vim: ft=bash
