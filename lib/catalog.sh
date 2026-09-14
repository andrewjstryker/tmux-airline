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
_catalog_extension () {
  case "$1" in
    palette) printf '.conf' ;;
    widget|layout|classifier|filter|probe|runner) printf '.sh' ;;
    *) return 2 ;;
  esac
}

# Register one shipped directory at the low-priority end of a kind's path. Missing
# optional directories are ignored; collection registration is idempotent.
catalog_register_builtin () {   # <session> <kind> <dir>
  local session="$1" kind="$2" dir="$3"
  [[ -d "$dir" ]] || return 0
  coll_register session "$session" "$(_catalog_namespace "$kind")" "$dir"
}

# Register shipped paths inside the caller's session configuration transaction.
catalog_register_builtins () {
  local session="$1"
  catalog_register_builtin "$session" palette "$AIRLINE_DIR/layouts/palettes"
  catalog_register_builtin "$session" widget "$AIRLINE_DIR/layouts/widgets"
  catalog_register_builtin "$session" layout  "$AIRLINE_DIR/layouts/definitions"
  catalog_register_builtin "$session" classifier "$AIRLINE_DIR/runners/classifiers"
  catalog_register_builtin "$session" filter "$AIRLINE_DIR/runners/filters"
  catalog_register_builtin "$session" probe "$AIRLINE_DIR/runners/probes"
  catalog_register_builtin "$session" runner "$AIRLINE_DIR/runners/definitions"
}

catalog_paths () {   # <session> <kind> -> space-delimited priority order
  coll_members session "$1" "$(_catalog_namespace "$2")"
}

# Resolve a bare name to the first file on the kind's path. A slash is rejected:
# callers must use their explicit load operation for a literal path.
catalog_resolve () {   # <session> <kind> <bare-name>
  local session="$1" kind="$2" name="$3" dir extension
  [[ "$name" != */* ]] || return
  extension="$(_catalog_extension "$kind")" || return
  for dir in $(catalog_paths "$session" "$kind"); do
    [[ -f "$dir/$name$extension" ]] && { printf '%s' "$dir/$name$extension"; return; }
  done
}

# List every resolvable bare name once, in path priority order. A name in a
# higher-priority directory shadows the same name in later directories.
catalog_list () {   # <session> <kind>
  local session="$1" kind="$2" dir f name seen=" " extension
  extension="$(_catalog_extension "$kind")" || return
  for dir in $(catalog_paths "$session" "$kind"); do
    [[ -d "$dir" ]] || continue
    for f in "$dir"/*; do
      [[ -f "$f" ]] || continue
      name="${f##*/}"
      [[ "$name" == *"$extension" ]] || continue
      name="${name%$extension}"
      case "$seen" in *" $name "*) continue ;; esac
      seen+="$name "
      printf '%s\n' "$name"
    done
  done
}

# Element metadata is declared in marked header comments and read without executing
# the file. Metadata inspection must not run catalog elements: palettes are
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

# Read option annotations without sourcing the file. Literal option names and
# alternations are supported; function names and brace placement are irrelevant.
catalog_options () {   # <file> -> option<TAB>annotation
  local file="$1" line marker active="" found=""
  local arm_re='^[[:space:]]*\(?[[:space:]]*(-[a-zA-Z0-9_-]+([[:space:]]*\|[[:space:]]*-[a-zA-Z0-9_-]+)*)[[:space:]]*\).*#[|][[:space:]]*(.+)$'
  [[ -f "$file" ]] || { _catalog_error "options: no such file: $file"; return; }
  while IFS= read -r line || [[ -n "$line" ]]; do
    marker="${line#"${line%%[![:space:]]*}"}"
    case "$marker" in
      '# options:begin')
        [[ -z "$found" ]] || { _catalog_error "options: duplicate section in $file"; return; }
        active=1; found=1 ;;
      '# options:end')
        [[ -n "$active" ]] || { _catalog_error "options: unmatched section end in $file"; return; }
        active="" ;;
      *)
        if [[ -n "$active" && "$line" =~ $arm_re ]]; then
          printf '%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]}"
        fi ;;
    esac
  done < "$file"
  [[ -z "$active" ]] || { _catalog_error "options: incomplete section in $file"; return; }
}

# Every catalog kind shares the same discovery contract: a non-empty summary,
# with optional file-wide fields in the same marked header.
catalog_metadata_valid () {   # <file>
  local summary
  summary="$(catalog_metadata "$1" summary)" || return 1
  [[ -n "${summary//[[:space:]]/}" ]]
}

catalog_describe_resolve () {   # <session> <kind> <name> -> validated file
  local session="$1" kind="$2" name="${3:-}" file
  [[ -n "$name" ]] || command_die "$kind describe: need <name>"
  [[ "$name" != */* ]] || command_die "$kind describe: need a bare name"
  file="$(catalog_resolve "$session" "$kind" "$name")"
  [[ -n "$file" ]] || command_die "$kind describe: '$name' not found on the $kind path"
  catalog_metadata_valid "$file" || command_die "$kind describe: '$name' has invalid metadata"
  printf '%s' "$file"
}

# Domain descriptions call this directly before adding derived fields. Metadata
# stays in the header; evaluating an implementation is never how we discover it.
catalog_describe_render () {   # <name> <file>
  local name="$1" file="$2" metadata options key value
  metadata="$(catalog_metadata "$file")" || return 1
  options="$(catalog_options "$file")" || return 1
  command_show_row name "$name"
  while IFS=$'\t' read -r key value; do
    case "$key" in
      summary) command_show_row summary "$value" ;;
      usage) command_show_row arguments "${value:-none}" ;;
    esac
  done <<< "$metadata"
  command_show_row path "$file"
  if [[ -n "$options" ]]; then
    printf 'options:\n'
    while IFS=$'\t' read -r key value; do
      printf '  %s %s\n' "$key" "$value"
    done <<< "$options"
  fi
}

catalog_describe () {   # <kind> <name>; common CLI behavior
  local kind="$1" file; shift
  (( $# == 1 )) || command_die "$kind describe: need exactly one <$kind>"
  file="$(catalog_describe_resolve "$(command_current_session)" "$kind" "$1")" || return
  catalog_describe_render "$1" "$file"
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
