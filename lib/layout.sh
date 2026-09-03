#!/usr/bin/env bash
#
# layout.sh — palette, adapter, segment, and executable-layout behavior.
#
# Public @airline-* options are durable configuration only at global scope.
# Palette files retain tmux's native configuration surface. Layouts are trusted Bash
# definitions with a validated declaration callback; airline collects their segments
# and adapters before committing private session configuration.

# shellcheck shell=bash

AIRLINE_CONFIG_PALETTE_FAILURE=70
AIRLINE_CONFIG_LAYOUT_FAILURE=80
AIRLINE_CONFIG_ERROR='config-error'
AIRLINE_PROBLEM_PALETTE='airline-palette'
AIRLINE_PROBLEM_LAYOUT='airline-layout'

#-----------------------------------------------------------------------------#
# Palette evaluation and effective configuration
#-----------------------------------------------------------------------------#

_palette_stage_clear () {
  local session="$1" element
  for element in "${AIRLINE_PALETTE_ELEMENTS[@]}"; do
    stage_unset_session "$session" "$element"
  done
}

_apply_public_unlocked () {
  local session="$1" element slot value missing=""
  local -A palette=()
  _AIRLINE_PALETTE_PATCHED=""
  _AIRLINE_SEGMENTS_PATCHED=""

  for element in "${AIRLINE_PALETTE_ELEMENTS[@]}"; do
    value="$(cfg_get_session "$session" "$element")"
    if pub_has "$element"; then
      value="$(pub_get "$element")"
      _AIRLINE_PALETTE_PATCHED=1
    fi
    if [[ -z "$value" ]]; then missing="${missing:+$missing, }$element"
    else palette[$element]="$value"; fi
  done
  if [[ -n "$missing" ]]; then
    printf 'airline: palette configuration is incomplete: missing %s\n' "$missing" >&2
    return "$AIRLINE_CONFIG_PALETTE_FAILURE"
  fi
  if [[ -n "$_AIRLINE_PALETTE_PATCHED" ]]; then
    for element in "${AIRLINE_PALETTE_ELEMENTS[@]}"; do
      cfg_set_session "$session" "$element" "${palette[$element]}"
    done
    prv_unset_session "$session" palette
  fi
  for slot in "${AIRLINE_SEGMENT_SLOTS[@]}"; do
    if pub_has "segment-$slot"; then
      cfg_set_session "$session" "segment-$slot" "$(pub_get "segment-$slot")"
      _AIRLINE_SEGMENTS_PATCHED=1
    fi
  done
  [[ -z "$_AIRLINE_SEGMENTS_PATCHED" ]] || prv_unset_session "$session" layout
}

_palette_select_unlocked () {
  local session="$1" name="$2" file element value missing="" rc=0
  local -A captured=()
  file="$(catalog_resolve "$session" palette "$name")"
  [[ -n "$file" ]] || return 2

  _palette_stage_clear "$session"
  source_file_session "$session" "$file" || rc=$?
  if (( rc != 0 )); then
    _palette_stage_clear "$session"
    printf "airline: palette '%s' could not be evaluated\n" "$name" >&2
    return "$AIRLINE_CONFIG_PALETTE_FAILURE"
  fi
  for element in "${AIRLINE_PALETTE_ELEMENTS[@]}"; do
    if stage_has_session "$session" "$element"; then
      value="$(stage_get_session "$session" "$element")"
      if [[ -n "$value" ]]; then captured[$element]="$value"
      else missing="${missing:+$missing, }$element"; fi
    else
      missing="${missing:+$missing, }$element"
    fi
  done
  _palette_stage_clear "$session"
  if [[ -n "$missing" ]]; then
    printf "airline: palette '%s' is incomplete: missing %s\n" "$name" "$missing" >&2
    return "$AIRLINE_CONFIG_PALETTE_FAILURE"
  fi
  for element in "${AIRLINE_PALETTE_ELEMENTS[@]}"; do
    cfg_set_session "$session" "$element" "${captured[$element]}"
  done
  prv_set_session "$session" palette "$name"
}

#-----------------------------------------------------------------------------#
# Adapters
#-----------------------------------------------------------------------------#

_abspath () {
  local dir base
  dir="$(dirname -- "$1")"; base="$(basename -- "$1")"
  printf '%s/%s' "$(cd -- "$dir" 2>/dev/null && pwd)" "$base"
}

_source_adapter () {
  # shellcheck disable=SC2034
  local AIRLINE_SESSION="$1" file="$2"
  render_palette_load
  # shellcheck source=/dev/null
  source "$file"
}

_apply_adapter_unlocked () {
  local session="$1" name file; shift
  [[ $# -gt 0 ]] || command_die "adapter use: need <name>"
  for name in "$@"; do
    [[ "$name" != */* ]] || command_die "adapter use: '$name' — bare name (or 'adapter load <path>')"
    file="$(catalog_resolve "$session" adapter "$name")"
    [[ -n "$file" ]] || command_die "adapter use: '$name' not found on the adapter path"
    _source_adapter "$session" "$file"
    coll_set session "$session" adapters "$name" use "$name"
  done
}

_load_adapter_unlocked () {
  local session="$1" path="${2:-}" abs
  [[ -n "$path" ]] || command_die "adapter load: need <path>"
  abs="$(_abspath "$path")"
  [[ -f "$abs" ]] || command_die "adapter load: no such file: $path"
  _source_adapter "$session" "$abs"
  coll_set session "$session" adapters "${abs##*/}" load "$abs"
}

_clear_adapters () {
  local session="$1" adapter
  for adapter in $(coll_members session "$session" adapters); do
    coll_unregister session "$session" adapters "$adapter"
  done
}

_reapply_adapters_unlocked () {
  local session="$1" key kind handle file
  for key in $(coll_members session "$session" adapters); do
    IFS=$'\t' read -r kind handle <<< "$(coll_get session "$session" adapters "$key")"
    case "$kind" in
      use)
        file="$(catalog_resolve "$session" adapter "$handle")"
        [[ -n "$file" ]] || command_die "adapter use: '$handle' not found on the adapter path"
        _source_adapter "$session" "$file"
        ;;
      load)
        [[ -f "$handle" ]] || command_die "adapter load: no such file: $handle"
        _source_adapter "$session" "$handle"
        ;;
      "")
        # Upgrade names-only adapter membership written by pre-snapshot releases.
        file="$(catalog_resolve "$session" adapter "$key")"
        [[ -n "$file" ]] || continue
        _source_adapter "$session" "$file"
        coll_set session "$session" adapters "$key" use "$key"
        ;;
    esac
  done
}

#-----------------------------------------------------------------------------#
# Layout definition contract and evaluation
#-----------------------------------------------------------------------------#

_layout_file () {
  local session="$1" handle="$2"
  if [[ "$handle" == */* ]]; then [[ -f "$handle" ]] && printf '%s' "$handle"
  else catalog_resolve "$session" layout "$handle"; fi
}

declare -gA AIRLINE_LAYOUT_CONFIG_SEGMENTS=()
declare -gA AIRLINE_LAYOUT_CONFIG_SEGMENT_SEEN=()
declare -gA AIRLINE_LAYOUT_CONFIG_ADAPTER_SEEN=()
declare -ga AIRLINE_LAYOUT_CONFIG_ADAPTER_KEYS=()
declare -ga AIRLINE_LAYOUT_CONFIG_ADAPTER_KINDS=()
declare -ga AIRLINE_LAYOUT_CONFIG_ADAPTER_HANDLES=()
AIRLINE_LAYOUT_CONFIG_SESSION=""
AIRLINE_LAYOUT_CONFIG_INVALID=""
AIRLINE_LAYOUT_CONFIG_MESSAGE=""

_layout_contract_reset () {
  AIRLINE_LAYOUT_CONFIG_SEGMENTS=()
  AIRLINE_LAYOUT_CONFIG_SEGMENT_SEEN=()
  AIRLINE_LAYOUT_CONFIG_ADAPTER_SEEN=()
  AIRLINE_LAYOUT_CONFIG_ADAPTER_KEYS=()
  AIRLINE_LAYOUT_CONFIG_ADAPTER_KINDS=()
  AIRLINE_LAYOUT_CONFIG_ADAPTER_HANDLES=()
  AIRLINE_LAYOUT_CONFIG_INVALID=""
  AIRLINE_LAYOUT_CONFIG_MESSAGE=""
}

_layout_contract_reject () {
  [[ -n "$AIRLINE_LAYOUT_CONFIG_INVALID" ]] || AIRLINE_LAYOUT_CONFIG_MESSAGE="$1"
  AIRLINE_LAYOUT_CONFIG_INVALID=1
  return 1
}

_layout_declare_segment () {
  local slot="${1:-}" value="${2:-}"
  (( $# == 2 )) || { _layout_contract_reject "segment needs exactly <slot> <value>"; return; }
  render_segment_slot_valid "$slot" || { _layout_contract_reject "unknown segment slot '$slot'"; return; }
  [[ -z "${AIRLINE_LAYOUT_CONFIG_SEGMENT_SEEN[$slot]:-}" ]] || {
    _layout_contract_reject "segment '$slot' was declared more than once"; return;
  }
  AIRLINE_LAYOUT_CONFIG_SEGMENT_SEEN[$slot]=1
  AIRLINE_LAYOUT_CONFIG_SEGMENTS[$slot]="$value"
}

_layout_declare_adapter_use () {
  local name file
  (( $# > 0 )) || { _layout_contract_reject "adapter use needs <name>"; return; }
  for name in "$@"; do
    [[ -n "$name" && "$name" != */* ]] || {
      _layout_contract_reject "adapter use needs bare names"; return;
    }
    file="$(catalog_resolve "$AIRLINE_LAYOUT_CONFIG_SESSION" adapter "$name")"
    [[ -n "$file" ]] || { _layout_contract_reject "adapter '$name' was not found"; return; }
    [[ -z "${AIRLINE_LAYOUT_CONFIG_ADAPTER_SEEN[$name]:-}" ]] || {
      _layout_contract_reject "adapter '$name' was declared more than once"; return;
    }
    AIRLINE_LAYOUT_CONFIG_ADAPTER_SEEN[$name]=1
    AIRLINE_LAYOUT_CONFIG_ADAPTER_KEYS+=("$name")
    AIRLINE_LAYOUT_CONFIG_ADAPTER_KINDS+=(use)
    AIRLINE_LAYOUT_CONFIG_ADAPTER_HANDLES+=("$name")
  done
}

_layout_declare_adapter_load () {
  local path="${1:-}" abs key
  if (( $# != 1 )) || [[ -z "$path" ]]; then
    _layout_contract_reject "adapter load needs exactly <path>"
    return
  fi
  abs="$(_abspath "$path")"
  [[ -f "$abs" ]] || { _layout_contract_reject "adapter file '$path' was not found"; return; }
  key="${abs##*/}"
  [[ -z "${AIRLINE_LAYOUT_CONFIG_ADAPTER_SEEN[$key]:-}" ]] || {
    _layout_contract_reject "adapter '$key' was declared more than once"; return;
  }
  AIRLINE_LAYOUT_CONFIG_ADAPTER_SEEN[$key]=1
  AIRLINE_LAYOUT_CONFIG_ADAPTER_KEYS+=("$key")
  AIRLINE_LAYOUT_CONFIG_ADAPTER_KINDS+=(load)
  AIRLINE_LAYOUT_CONFIG_ADAPTER_HANDLES+=("$abs")
}

_layout_declare () {   # <segment|adapter> ...
  local kind="${1:-}" verb="${2:-}"; shift || true
  [[ -z "$AIRLINE_LAYOUT_CONFIG_INVALID" ]] || return 1
  case "$kind" in
    segment) _layout_declare_segment "$@" ;;
    adapter)
      shift || true
      case "$verb" in
        use)  _layout_declare_adapter_use "$@" ;;
        load) _layout_declare_adapter_load "$@" ;;
        *)    _layout_contract_reject "adapter needs use or load" ;;
      esac
      ;;
    *) _layout_contract_reject "unknown declaration '$kind'" ;;
  esac
}

_layout_definition_evaluate () {   # <session> <file>
  local session="$1" file="$2" rc=0
  AIRLINE_LAYOUT_CONFIG_SESSION="$session"
  _layout_contract_reset
  unset -f airline_layout_configure 2>/dev/null || true
  airline () { _layout_contract_reject "nested airline commands are not layout declarations"; }
  # shellcheck source=/dev/null
  source "$file" || rc=$?
  if (( rc == 0 )) && ! declare -F airline_layout_configure >/dev/null; then
    _layout_contract_reject "missing airline_layout_configure"
    rc=1
  fi
  if (( rc == 0 )); then
    airline_layout_configure _layout_declare || rc=$?
  fi
  unset -f airline
  [[ -z "$AIRLINE_LAYOUT_CONFIG_INVALID" ]] || rc=1
  return "$rc"
}

_layout_adapters_apply_unlocked () {
  local session="$1" i kind handle file
  for (( i=0; i<${#AIRLINE_LAYOUT_CONFIG_ADAPTER_KEYS[@]}; i++ )); do
    kind="${AIRLINE_LAYOUT_CONFIG_ADAPTER_KINDS[i]}"
    handle="${AIRLINE_LAYOUT_CONFIG_ADAPTER_HANDLES[i]}"
    case "$kind" in
      use)
        file="$(catalog_resolve "$session" adapter "$handle")"
        [[ -n "$file" ]] || return 1
        _source_adapter "$session" "$file" || return 1
        ;;
      load) _source_adapter "$session" "$handle" || return 1 ;;
    esac
  done
}

_layout_commit_unlocked () {
  local session="$1" handle="$2" slot i
  for slot in "${AIRLINE_SEGMENT_SLOTS[@]}"; do
    cfg_set_session "$session" "segment-$slot" "${AIRLINE_LAYOUT_CONFIG_SEGMENTS[$slot]:-}"
  done
  _clear_adapters "$session"
  for (( i=0; i<${#AIRLINE_LAYOUT_CONFIG_ADAPTER_KEYS[@]}; i++ )); do
    coll_set session "$session" adapters \
      "${AIRLINE_LAYOUT_CONFIG_ADAPTER_KEYS[i]}" \
      "${AIRLINE_LAYOUT_CONFIG_ADAPTER_KINDS[i]}" \
      "${AIRLINE_LAYOUT_CONFIG_ADAPTER_HANDLES[i]}"
  done
  prv_set_session "$session" layout "$handle"
}

_layout_failure () {   # <session> <handle> <detail>
  local session="$1" handle="$2" detail="$3" message
  message="layout '$handle' $detail"
  prv_set_session "$session" "$AIRLINE_CONFIG_ERROR" "$message"
  printf 'airline: %s\n' "$message" >&2
  return "$AIRLINE_CONFIG_LAYOUT_FAILURE"
}

_apply_layout_unlocked () {
  local session="$1" handle="$2" file output rc=0 detail
  file="$(_layout_file "$session" "$handle")"
  [[ -n "$file" ]] || { _layout_failure "$session" "$handle" "was not found"; return; }
  prv_unset_session "$session" "$AIRLINE_CONFIG_ERROR"
  output="$(mktemp "${TMPDIR:-/tmp}/airline-layout-contract.XXXXXX")" || return 1
  _layout_definition_evaluate "$session" "$file" > "$output" || rc=$?
  if [[ -s "$output" ]]; then
    AIRLINE_LAYOUT_CONFIG_MESSAGE="wrote to stdout"
    rc=1
  fi
  rm -f "$output"
  if (( rc != 0 )); then
    detail="could not be evaluated"
    [[ -z "$AIRLINE_LAYOUT_CONFIG_MESSAGE" ]] || detail="$AIRLINE_LAYOUT_CONFIG_MESSAGE"
    _layout_failure "$session" "$handle" "$detail"
    return
  fi
  _layout_adapters_apply_unlocked "$session" || {
    _layout_failure "$session" "$handle" "could not apply its adapters"; return;
  }
  _layout_commit_unlocked "$session" "$handle"
}

#-----------------------------------------------------------------------------#
# Discovery
#-----------------------------------------------------------------------------#

_layout_show () {
  local session="$1" x="${2:-}" handle; handle="$(prv_get_session "$session" layout)"
  case "$x" in
    name) printf '%s\n' "$handle" ;;
    path) printf '%s\n' "$(_layout_file "$session" "$handle")" ;;
    "")   command_show_row name "$handle"; command_show_row path "$(_layout_file "$session" "$handle")" ;;
    *)    command_die "layout show: unknown field '$x' (name | path)" ;;
  esac
}

_static_show () {
  local session="$1" keypfx="$2" valid="$3" listname="$4" x="${5:-}"
  if [[ -n "$x" ]]; then
    "$valid" "$x" || command_die "show: unknown target '$x'"
    cfg_get_session "$session" "${keypfx}${x}"
    return 0
  fi
  local -n all="$listname"; local key
  for key in "${all[@]}"; do command_show_row "$key" "$(cfg_get_session "$session" "${keypfx}${key}")"; done
}

_palette_show () {
  local session="$1" x="${2:-}"
  [[ "$x" == name ]] && { prv_get_session "$session" palette; return 0; }
  [[ -z "$x" ]] && command_show_row name "$(prv_get_session "$session" palette)"
  _static_show "$session" "" render_palette_element_valid AIRLINE_PALETTE_ELEMENTS "$x"
}

_adapter_show () {
  local session="$1" adapter
  for adapter in $(coll_members session "$session" adapters); do printf '%s\n' "$adapter"; done
}

#-----------------------------------------------------------------------------#
# Public configuration services and CLI behavior boundary
#-----------------------------------------------------------------------------#

# Session coordination services. Layout owns initialization and application of the
# complete configuration snapshot; session owns only the session command and state.
_layout_initialize_unlocked () {   # <session>
  local session="$1" selected seeded=""
  if [[ -z "$(cfg_get_session "$session" inner-bg)" ]]; then
    _palette_select_unlocked "$session" default || return $?
    seeded=1
  fi
  if [[ -n "$seeded" || -z "$(prv_get_session "$session" "$AIRLINE_KEY_DEFAULTS")" ]]; then
    selected="$(prv_get_session "$session" layout)"
    [[ -n "$selected" ]] || selected=adaptive
    _apply_layout_unlocked "$session" "$selected" || return $?
  fi
  _apply_public_unlocked "$session" || return $?
  _reapply_adapters_unlocked "$session" || return $?
  prv_set_session "$session" "$AIRLINE_KEY_DEFAULTS" 1
  render "$session"
}

_layout_apply_unlocked () {   # <session>
  _apply_public_unlocked "$1" || return $?
  _reapply_adapters_unlocked "$1" || return $?
  render "$1"
}

_layout_report_configuration_result () {   # <session> <rc> <operation>
  local session="$1" rc="$2" operation="$3" message
  case "$rc" in
    0)
      signal_problem_report "$session" airline "$AIRLINE_PROBLEM_PALETTE" ok ""
      [[ "$operation" != init ]] || signal_problem_report "$session" airline "$AIRLINE_PROBLEM_LAYOUT" ok ""
      ;;
    "$AIRLINE_CONFIG_PALETTE_FAILURE")
      signal_problem_report "$session" airline "$AIRLINE_PROBLEM_PALETTE" fail \
        "$operation could not resolve a complete palette"
      ;;
    *)
      message="$(prv_get_session "$session" "$AIRLINE_CONFIG_ERROR")"
      [[ -n "$message" ]] || message="$operation could not apply a layout"
      signal_problem_report "$session" airline "$AIRLINE_PROBLEM_LAYOUT" fail "$message"
      ;;
  esac
}

layout_initialize () {   # <session>
  local session="$1" rc=0
  with_session_transaction "$session" config _layout_initialize_unlocked "$session" || rc=$?
  _layout_report_configuration_result "$session" "$rc" init
  return "$rc"
}

layout_apply () {   # <session>
  local session="$1" rc=0
  with_session_transaction "$session" config _layout_apply_unlocked "$session" || rc=$?
  _layout_report_configuration_result "$session" "$rc" apply
  return "$rc"
}

layout_configuration_show () {   # <session>; caller owns the config transaction
  local session="$1"
  printf '\npalette:\n'; _palette_show "$session"
  printf '\nsegment:\n'; _static_show "$session" "segment-" render_segment_slot_valid AIRLINE_SEGMENT_SLOTS
  printf '\nadapter:\n'; _adapter_show "$session"
  printf '\nlayout:\n';  _layout_show "$session"
}

_layout_problem_message () {
  local session="$1" handle="$2" message
  message="$(prv_get_session "$session" "$AIRLINE_CONFIG_ERROR")"
  if [[ -n "$message" ]]; then printf '%s' "$message"
  else printf "layout '%s' could not be applied" "$handle"; fi
}

layout_palette_show () {
  local s
  (( $# <= 1 )) || command_die "palette show: too many arguments"
  s="$(command_current_session)"; _palette_show "$s" "$@"
}
layout_palette_use () {
  local s name rc=0
  [[ $# -eq 1 && -n "$1" ]] || command_die "palette use: need exactly one <name>"
  name="$1"; [[ "$name" != */* ]] || command_die "palette use: '$name' — use a bare name"
  s="$(command_current_session)"
  [[ -n "$(catalog_resolve "$s" palette "$name")" ]] || command_die "palette use: '$name' not found on the palette path"
  with_session_transaction "$s" config _palette_use_apply_unlocked "$s" "$name" || rc=$?
  if (( rc == AIRLINE_CONFIG_PALETTE_FAILURE )); then
    signal_problem_report "$s" airline "$AIRLINE_PROBLEM_PALETTE" fail "palette '$name' is incomplete or could not be evaluated"
  else signal_problem_report "$s" airline "$AIRLINE_PROBLEM_PALETTE" ok ""; fi
  (( rc == 0 )) || return "$rc"
}
layout_palette_list () {
  local s
  (( $# == 0 )) || command_die "palette list: takes no arguments"
  s="$(command_current_session)"; catalog_list "$s" palette
}
layout_palette_register () { local s; s="$(command_current_session)"; catalog_register "$s" palette "$@"; }

layout_segment_show () {
  local s
  (( $# <= 1 )) || command_die "segment show: too many arguments"
  s="$(command_current_session)"
  _static_show "$s" "segment-" render_segment_slot_valid AIRLINE_SEGMENT_SLOTS "$@"
}

layout_adapter_use () {
  local s rc=0; s="$(command_current_session)"
  with_session_transaction "$s" config _adapter_use_render_unlocked "$s" "$@" || rc=$?
  if (( rc == AIRLINE_CONFIG_PALETTE_FAILURE )); then
    signal_problem_report "$s" airline "$AIRLINE_PROBLEM_PALETTE" fail "adapter use could not resolve a complete palette"
  fi
  return "$rc"
}
layout_adapter_load () {
  local s rc=0
  (( $# == 1 )) || command_die "adapter load: need exactly one <file>"
  s="$(command_current_session)"
  with_session_transaction "$s" config _adapter_load_render_unlocked "$s" "$@" || rc=$?
  if (( rc == AIRLINE_CONFIG_PALETTE_FAILURE )); then
    signal_problem_report "$s" airline "$AIRLINE_PROBLEM_PALETTE" fail "adapter load could not resolve a complete palette"
  fi
  return "$rc"
}
layout_adapter_show () {
  (( $# == 0 )) || command_die "adapter show: takes no arguments"
  _adapter_show "$(command_current_session)"
}
layout_adapter_list () {
  local s
  (( $# == 0 )) || command_die "adapter list: takes no arguments"
  s="$(command_current_session)"; catalog_list "$s" adapter
}
layout_adapter_register () { local s; s="$(command_current_session)"; catalog_register "$s" adapter "$@"; }

layout_use () {
  local s name rc=0
  [[ $# -eq 1 && -n "$1" ]] || command_die "layout use: need exactly one <name>"
  name="$1"; [[ "$name" != */* ]] || command_die "layout use: '$name' — bare name (or 'layout load <path>')"
  s="$(command_current_session)"
  [[ -n "$(catalog_resolve "$s" layout "$name")" ]] || command_die "layout use: '$name' not found"
  with_session_transaction "$s" config _layout_use_render_unlocked "$s" "$name" || rc=$?
  case "$rc" in
    0) signal_problem_report "$s" airline "$AIRLINE_PROBLEM_LAYOUT" ok "" ;;
    "$AIRLINE_CONFIG_PALETTE_FAILURE")
      signal_problem_report "$s" airline "$AIRLINE_PROBLEM_PALETTE" fail "layout use could not resolve a complete palette" ;;
    *) signal_problem_report "$s" airline "$AIRLINE_PROBLEM_LAYOUT" fail "$(_layout_problem_message "$s" "$name")" ;;
  esac
  (( rc == 0 )) || return "$rc"
}
layout_load () {
  local s path abs rc=0
  [[ $# -eq 1 && -n "$1" ]] || command_die "layout load: need <path>"
  path="$1"; abs="$(_abspath "$path")"; [[ -f "$abs" ]] || command_die "layout load: no such file: $path"
  s="$(command_current_session)"
  with_session_transaction "$s" config _layout_load_render_unlocked "$s" "$abs" || rc=$?
  case "$rc" in
    0) signal_problem_report "$s" airline "$AIRLINE_PROBLEM_LAYOUT" ok "" ;;
    "$AIRLINE_CONFIG_PALETTE_FAILURE")
      signal_problem_report "$s" airline "$AIRLINE_PROBLEM_PALETTE" fail "layout load could not resolve a complete palette" ;;
    *) signal_problem_report "$s" airline "$AIRLINE_PROBLEM_LAYOUT" fail "$(_layout_problem_message "$s" "$abs")" ;;
  esac
  (( rc == 0 )) || return "$rc"
}
layout_show () {
  local s
  (( $# <= 1 )) || command_die "layout show: too many arguments"
  s="$(command_current_session)"; _layout_show "$s" "$@"
}
layout_list () {
  local s
  (( $# == 0 )) || command_die "layout list: takes no arguments"
  s="$(command_current_session)"; catalog_list "$s" layout
}
layout_register () { local s; s="$(command_current_session)"; catalog_register "$s" layout "$@"; }

_palette_use_apply_unlocked () {
  _apply_public_unlocked "$1" &&
    _palette_select_unlocked "$1" "$2" &&
    _reapply_adapters_unlocked "$1" && render "$1"
}
_layout_use_render_unlocked () {
  _apply_public_unlocked "$1" &&
    _reapply_adapters_unlocked "$1" &&
    _apply_layout_unlocked "$1" "$2" && render "$1"
}
_layout_load_render_unlocked () { _layout_use_render_unlocked "$@"; }
_adapter_use_render_unlocked () {
  _apply_public_unlocked "$1" &&
    _reapply_adapters_unlocked "$1" &&
    _apply_adapter_unlocked "$@" && render "$1"
}
_adapter_load_render_unlocked () {
  _apply_public_unlocked "$1" &&
    _reapply_adapters_unlocked "$1" &&
    _load_adapter_unlocked "$@" && render "$1"
}

# vim: ft=bash
