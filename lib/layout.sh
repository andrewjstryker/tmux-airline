#!/usr/bin/env bash
#
# layout.sh — palette, adapter, segment, and executable-layout behavior.
#
# Public @airline-* options are durable configuration only at global scope.
# Palette tmux files and layout Bash programs retain their native authoring
# surfaces, but their session-local public writes are temporary evaluation output:
# airline captures, clears, and commits them into private session configuration.

# shellcheck shell=bash

if ! declare -F render >/dev/null; then
  printf 'layout.sh: load render.sh (and its layers) first\n' >&2
  return 1 2>/dev/null || exit 1
fi

AIRLINE_CONFIG_PALETTE_FAILURE=70
AIRLINE_CONFIG_LAYOUT_FAILURE=80
AIRLINE_STAGE_ADAPTERS='stage-adapters'

_layout_evaluating () { [[ -n "${AIRLINE_LAYOUT_SESSION:-}" ]]; }

_reject_layout_reentry () {
  _layout_evaluating || return 0
  prv_set_session "$AIRLINE_LAYOUT_SESSION" layout-violation "$1"
  die "layout evaluation cannot invoke $1"
}

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
  file="$(_path_resolve "$session" palette "$name")"
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
# Adapters — immediate outside a layout, declarations during layout evaluation
#-----------------------------------------------------------------------------#

_abspath () {
  local dir base
  dir="$(dirname -- "$1")"; base="$(basename -- "$1")"
  printf '%s/%s' "$(cd -- "$dir" 2>/dev/null && pwd)" "$base"
}

_source_adapter () {
  # shellcheck disable=SC2034
  local AIRLINE_SESSION="$1" file="$2"
  _palette_load
  # shellcheck source=/dev/null
  source "$file"
}

_apply_adapter_unlocked () {
  local session="$1" name file; shift
  [[ $# -gt 0 ]] || die "adapter use: need <name>"
  for name in "$@"; do
    [[ "$name" != */* ]] || die "adapter use: '$name' — bare name (or 'adapter load <path>')"
    file="$(_path_resolve "$session" adapter "$name")"
    [[ -n "$file" ]] || die "adapter use: '$name' not found on the adapter path"
    _source_adapter "$session" "$file"
    coll_set_session "$session" adapters "$name" use "$name"
  done
}

_load_adapter_unlocked () {
  local session="$1" path="${2:-}" abs
  [[ -n "$path" ]] || die "adapter load: need <path>"
  abs="$(_abspath "$path")"
  [[ -f "$abs" ]] || die "adapter load: no such file: $path"
  _source_adapter "$session" "$abs"
  coll_set_session "$session" adapters "${abs##*/}" load "$abs"
}

_staged_adapters_clear () {
  local session="$1" key
  for key in $(coll_members_session "$session" "$AIRLINE_STAGE_ADAPTERS"); do
    coll_unregister_session "$session" "$AIRLINE_STAGE_ADAPTERS" "$key"
  done
}

_stage_adapter_use () {
  local session="$1" name file; shift
  [[ $# -gt 0 ]] || die "adapter use: need <name>"
  for name in "$@"; do
    [[ "$name" != */* ]] || die "adapter use: '$name' — bare name (or 'adapter load <path>')"
    file="$(_path_resolve "$session" adapter "$name")"
    [[ -n "$file" ]] || die "adapter use: '$name' not found on the adapter path"
    coll_set_session "$session" "$AIRLINE_STAGE_ADAPTERS" "$name" use "$name"
  done
}

_stage_adapter_load () {
  local session="$1" path="${2:-}" abs key
  [[ -n "$path" ]] || die "adapter load: need <path>"
  abs="$(_abspath "$path")"
  [[ -f "$abs" ]] || die "adapter load: no such file: $path"
  key="${abs##*/}"
  coll_set_session "$session" "$AIRLINE_STAGE_ADAPTERS" "$key" load "$abs"
}

_clear_adapters () {
  local session="$1" adapter
  for adapter in $(coll_members_session "$session" adapters); do
    coll_unregister_session "$session" adapters "$adapter"
  done
}

_apply_staged_adapters_unlocked () {
  local session="$1" key kind handle
  _clear_adapters "$session"
  for key in $(coll_members_session "$session" "$AIRLINE_STAGE_ADAPTERS"); do
    IFS=$'\t' read -r kind handle <<< "$(coll_get_session "$session" "$AIRLINE_STAGE_ADAPTERS" "$key")"
    case "$kind" in
      use)  _apply_adapter_unlocked "$session" "$handle" ;;
      load) _load_adapter_unlocked "$session" "$handle" ;;
    esac
  done
  _staged_adapters_clear "$session"
}

_reapply_adapters_unlocked () {
  local session="$1" key kind handle file
  for key in $(coll_members_session "$session" adapters); do
    IFS=$'\t' read -r kind handle <<< "$(coll_get_session "$session" adapters "$key")"
    case "$kind" in
      use)
        file="$(_path_resolve "$session" adapter "$handle")"
        [[ -n "$file" ]] || die "adapter use: '$handle' not found on the adapter path"
        _source_adapter "$session" "$file"
        ;;
      load)
        [[ -f "$handle" ]] || die "adapter load: no such file: $handle"
        _source_adapter "$session" "$handle"
        ;;
      "")
        # Upgrade names-only adapter membership written by pre-snapshot releases.
        file="$(_path_resolve "$session" adapter "$key")"
        [[ -n "$file" ]] || continue
        _source_adapter "$session" "$file"
        coll_set_session "$session" adapters "$key" use "$key"
        ;;
    esac
  done
}

#-----------------------------------------------------------------------------#
# Layout evaluation
#-----------------------------------------------------------------------------#

_layout_file () {
  local session="$1" handle="$2"
  if [[ "$handle" == */* ]]; then [[ -f "$handle" ]] && printf '%s' "$handle"
  else _path_resolve "$session" layout "$handle"; fi
}

_segment_stage_clear () {
  local session="$1" slot
  for slot in "${AIRLINE_SEGMENT_SLOTS[@]}"; do
    stage_unset_session "$session" "segment-$slot"
  done
}

_apply_layout_unlocked () {
  local session="$1" handle="$2" file rc=0 slot value
  local layout_dir="$AIRLINE_DIR" layout_cli="$AIRLINE_DIR/airline.sh" layout_path="$AIRLINE_DIR:$PATH"
  local -A segments=()
  file="$(_layout_file "$session" "$handle")"
  [[ -n "$file" ]] || { printf "airline: layout '%s' not found\n" "$handle" >&2; return "$AIRLINE_CONFIG_LAYOUT_FAILURE"; }

  _segment_stage_clear "$session"
  _staged_adapters_clear "$session"
  prv_unset_session "$session" layout-violation
  AIRLINE_DIR="$layout_dir" AIRLINE_CLI="$layout_cli" \
    AIRLINE_SESSION="$session" AIRLINE_LAYOUT_SESSION="$session" \
    AIRLINE_TMUX="${AIRLINE_TMUX:-tmux}" PATH="$layout_path" bash "$file" || rc=$?
  [[ -z "$(prv_get_session "$session" layout-violation)" ]] || rc=2
  prv_unset_session "$session" layout-violation
  if (( rc != 0 )); then
    _segment_stage_clear "$session"
    _staged_adapters_clear "$session"
    printf "airline: layout '%s' exited with status %s\n" "$handle" "$rc" >&2
    return "$AIRLINE_CONFIG_LAYOUT_FAILURE"
  fi

  for slot in "${AIRLINE_SEGMENT_SLOTS[@]}"; do
    if stage_has_session "$session" "segment-$slot"; then value="$(stage_get_session "$session" "segment-$slot")"
    else value=""; fi
    segments[$slot]="$value"
  done
  _segment_stage_clear "$session"
  for slot in "${AIRLINE_SEGMENT_SLOTS[@]}"; do
    cfg_set_session "$session" "segment-$slot" "${segments[$slot]}"
  done
  prv_set_session "$session" layout "$handle"
  _apply_staged_adapters_unlocked "$session"
}

#-----------------------------------------------------------------------------#
# Discovery
#-----------------------------------------------------------------------------#

_layout_show () {
  local session="$1" x="${2:-}" handle; handle="$(prv_get_session "$session" layout)"
  case "$x" in
    name) printf '%s\n' "$handle" ;;
    path) printf '%s\n' "$(_layout_file "$session" "$handle")" ;;
    "")   _show_row name "$handle"; _show_row path "$(_layout_file "$session" "$handle")" ;;
    *)    die "layout show: unknown field '$x' (name | path)" ;;
  esac
}

_static_show () {
  local session="$1" keypfx="$2" valid="$3" listname="$4" x="${5:-}"
  if [[ -n "$x" ]]; then
    "$valid" "$x" || die "show: unknown target '$x'"
    cfg_get_session "$session" "${keypfx}${x}"
    return 0
  fi
  local -n all="$listname"; local key
  for key in "${all[@]}"; do _show_row "$key" "$(cfg_get_session "$session" "${keypfx}${key}")"; done
}

_palette_show () {
  local session="$1" x="${2:-}"
  [[ "$x" == name ]] && { prv_get_session "$session" palette; return 0; }
  [[ -z "$x" ]] && _show_row name "$(prv_get_session "$session" palette)"
  _static_show "$session" "" _palette_element_valid AIRLINE_PALETTE_ELEMENTS "$x"
}

_adapter_show () {
  local session="$1" adapter
  for adapter in $(coll_members_session "$session" adapters); do printf '%s\n' "$adapter"; done
}

#-----------------------------------------------------------------------------#
# CLI behavior boundary
#-----------------------------------------------------------------------------#

_config_problem () { _problem_store "$1" "$2" "$3" "$4" || true; }

layout_palette_show () { local s; s="$(_require_current_session)"; _palette_show "$s" "$@"; }
layout_palette_use () {
  local s name rc=0
  _reject_layout_reentry "palette use"
  [[ $# -eq 1 && -n "$1" ]] || die "palette use: need exactly one <name>"
  name="$1"; [[ "$name" != */* ]] || die "palette use: '$name' — use a bare name"
  s="$(_require_current_session)"
  [[ -n "$(_path_resolve "$s" palette "$name")" ]] || die "palette use: '$name' not found on the palette path"
  with_session_transaction "$s" config _palette_use_apply_unlocked "$s" "$name" || rc=$?
  if (( rc == AIRLINE_CONFIG_PALETTE_FAILURE )); then
    _config_problem "$s" airline-palette fail "palette '$name' is incomplete or could not be evaluated"
  else _config_problem "$s" airline-palette ok ""; fi
  (( rc == 0 )) || return "$rc"
}
layout_palette_available () { local s; s="$(_require_current_session)"; _path_available "$s" palette; }
layout_palette_register () { local s; s="$(_require_current_session)"; _register "$s" palette "$@"; }

layout_segment_show () {
  local s; s="$(_require_current_session)"
  _static_show "$s" "segment-" _segment_slot_valid AIRLINE_SEGMENT_SLOTS "$@"
}

layout_adapter_use () {
  local s rc=0
  if _layout_evaluating; then
    s="$AIRLINE_LAYOUT_SESSION"
    _stage_adapter_use "$s" "$@"
  else
    s="$(_require_current_session)"
    with_session_transaction "$s" config _adapter_use_render_unlocked "$s" "$@" || rc=$?
    if (( rc == AIRLINE_CONFIG_PALETTE_FAILURE )); then
      _config_problem "$s" airline-palette fail "adapter use could not resolve a complete palette"
    else _config_problem "$s" airline-palette ok ""; fi
    return "$rc"
  fi
}
layout_adapter_load () {
  local s rc=0
  if _layout_evaluating; then
    s="$AIRLINE_LAYOUT_SESSION"
    _stage_adapter_load "$s" "$@"
  else
    s="$(_require_current_session)"
    with_session_transaction "$s" config _adapter_load_render_unlocked "$s" "$@" || rc=$?
    if (( rc == AIRLINE_CONFIG_PALETTE_FAILURE )); then
      _config_problem "$s" airline-palette fail "adapter load could not resolve a complete palette"
    else _config_problem "$s" airline-palette ok ""; fi
    return "$rc"
  fi
}
layout_adapter_show () { _adapter_show "$(_require_current_session)"; }
layout_adapter_available () { local s; s="$(_require_current_session)"; _path_available "$s" adapter; }
layout_adapter_register () { local s; s="$(_require_current_session)"; _register "$s" adapter "$@"; }

layout_use () {
  local s name rc=0
  _reject_layout_reentry "layout use"
  [[ $# -eq 1 && -n "$1" ]] || die "layout use: need exactly one <name>"
  name="$1"; [[ "$name" != */* ]] || die "layout use: '$name' — bare name (or 'layout load <path>')"
  s="$(_require_current_session)"
  [[ -n "$(_path_resolve "$s" layout "$name")" ]] || die "layout use: '$name' not found"
  with_session_transaction "$s" config _layout_use_render_unlocked "$s" "$name" || rc=$?
  case "$rc" in
    0) _config_problem "$s" airline-palette ok ""; _config_problem "$s" airline-layout ok "" ;;
    "$AIRLINE_CONFIG_PALETTE_FAILURE")
      _config_problem "$s" airline-palette fail "layout use could not resolve a complete palette" ;;
    "$AIRLINE_CONFIG_LAYOUT_FAILURE")
      _config_problem "$s" airline-palette ok ""
      _config_problem "$s" airline-layout fail "layout '$name' could not be applied" ;;
  esac
  (( rc == 0 )) || return "$rc"
}
layout_load () {
  local s path abs rc=0
  _reject_layout_reentry "layout load"
  [[ $# -eq 1 && -n "$1" ]] || die "layout load: need <path>"
  path="$1"; abs="$(_abspath "$path")"; [[ -f "$abs" ]] || die "layout load: no such file: $path"
  s="$(_require_current_session)"
  with_session_transaction "$s" config _layout_load_render_unlocked "$s" "$abs" || rc=$?
  case "$rc" in
    0) _config_problem "$s" airline-palette ok ""; _config_problem "$s" airline-layout ok "" ;;
    "$AIRLINE_CONFIG_PALETTE_FAILURE")
      _config_problem "$s" airline-palette fail "layout load could not resolve a complete palette" ;;
    "$AIRLINE_CONFIG_LAYOUT_FAILURE")
      _config_problem "$s" airline-palette ok ""
      _config_problem "$s" airline-layout fail "layout '$abs' could not be applied" ;;
  esac
  (( rc == 0 )) || return "$rc"
}
layout_show () { local s; s="$(_require_current_session)"; _layout_show "$s" "$@"; }
layout_available () { local s; s="$(_require_current_session)"; _path_available "$s" layout; }
layout_register () { local s; s="$(_require_current_session)"; _register "$s" layout "$@"; }

_palette_use_apply_unlocked () {
  _apply_public_unlocked "$1" &&
    _palette_select_unlocked "$1" "$2" &&
    _reapply_adapters_unlocked "$1" && { render "$1" || true; }
}
_layout_use_render_unlocked () {
  _apply_public_unlocked "$1" &&
    _reapply_adapters_unlocked "$1" &&
    _apply_layout_unlocked "$1" "$2" && { render "$1" || true; }
}
_layout_load_render_unlocked () { _layout_use_render_unlocked "$@"; }
_adapter_use_render_unlocked () {
  _apply_public_unlocked "$1" &&
    _reapply_adapters_unlocked "$1" &&
    _apply_adapter_unlocked "$@" && { render "$1" || true; }
}
_adapter_load_render_unlocked () {
  _apply_public_unlocked "$1" &&
    _reapply_adapters_unlocked "$1" &&
    _load_adapter_unlocked "$@" && { render "$1" || true; }
}

# vim: ft=bash
