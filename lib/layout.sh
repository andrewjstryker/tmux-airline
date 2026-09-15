#!/usr/bin/env bash
#
# layout.sh — palette, widget, segment, and executable-layout behavior.
#
# Palette options are public session state; private configuration retains restore data.
# Palette files retain tmux's native configuration surface. Layouts are trusted Bash
# definitions with a validated declaration callback; airline collects their segments
# and widgets before committing session configuration.

# shellcheck shell=bash

AIRLINE_CONFIG_PALETTE_FAILURE=70
AIRLINE_CONFIG_LAYOUT_FAILURE=80
AIRLINE_CONFIG_ERROR='config-error'
AIRLINE_PROBLEM_PALETTE='airline-palette'
AIRLINE_PROBLEM_LAYOUT='airline-layout'

#-----------------------------------------------------------------------------#
# Palette evaluation and effective configuration
#-----------------------------------------------------------------------------#

_palette_public_has () { opt_has_global "$(palette_public_name "$1")"; }
_palette_public_get_into () { opt_get_into "$1" global server "$(palette_public_name "$2")"; }
_palette_public_has_session () { opt_has_session "$1" "$(palette_public_name "$2")"; }
_palette_public_get_session_into () { opt_get_into "$1" session "$2" "$(palette_public_name "$3")"; }
_palette_source_file_session () {
  local session="$1" source="$2" staged text rc=0 stage_prefix
  staged="$(mktemp)" || return
  text="$(cat "$source")" || { rm -f "$staged"; return 1; }
  stage_prefix="$(prv_name 'stage-')"
  printf '%s\n' "${text//@airline-palette-/$stage_prefix}" > "$staged"
  source_file_session "$session" "$staged" || rc=$?
  rm -f "$staged"
  return "$rc"
}

_palette_stage_clear () {
  local session="$1" element
  for element in "${AIRLINE_PALETTE_ELEMENTS[@]}"; do
    stage_unset_session "$session" "$element"
  done
}

_apply_public_unlocked () {
  local session="$1" element slot value current displayed defaults missing=""
  local -A palette=()
  _AIRLINE_PALETTE_PATCHED=""
  _AIRLINE_SEGMENTS_PATCHED=""

  prv_get_session_into defaults "$session" "$AIRLINE_KEY_DEFAULTS" || return
  for element in "${AIRLINE_PALETTE_ELEMENTS[@]}"; do
    cfg_get_session_into value "$session" "$element"
    if [[ -z "$defaults" ]] && _palette_public_has "$element"; then
      _palette_public_get_into value "$element"
      _AIRLINE_PALETTE_PATCHED=1
    fi
    if _palette_public_has_session "$session" "$element"; then
      _palette_public_get_session_into current "$session" "$element"
      prv_get_session_into displayed "$session" "display-$element" || return
      if [[ "$current" != "$displayed" ]]; then
        value="$current"; _AIRLINE_PALETTE_PATCHED=1
      fi
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
      widget_retire_session "$session" "$slot" || return
      pub_get_into value "segment-$slot" || return
      cfg_set_session "$session" "segment-$slot" "$value"
      _AIRLINE_SEGMENTS_PATCHED=1
    fi
  done
  [[ -z "$_AIRLINE_SEGMENTS_PATCHED" ]] || prv_unset_session "$session" layout
}

_palette_evaluate_unlocked () {   # <session> <file> <handle> <destination>; caller owns config transaction
  local session="$1" file="$2" name="$3" element value missing="" rc=0
  local -n captured="$4"
  captured=()

  _palette_stage_clear "$session"
  _palette_source_file_session "$session" "$file" || rc=$?
  if (( rc != 0 )); then
    _palette_stage_clear "$session"
    printf "airline: palette '%s' could not be evaluated\n" "$name" >&2
    return "$AIRLINE_CONFIG_PALETTE_FAILURE"
  fi
  for element in "${AIRLINE_PALETTE_ELEMENTS[@]}"; do
    if stage_has_session "$session" "$element"; then
      stage_get_session_into value "$session" "$element"
      if [[ -n "$value" ]]; then
        # Caller supplies an associative array through the nameref.
        # shellcheck disable=SC2034,SC2004
        captured[$element]="$value"
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
}

_palette_commit_unlocked () {   # <session> <file> <handle>
  local session="$1" file="$2" handle="$3" element
  local -A evaluated=()
  _palette_evaluate_unlocked "$session" "$file" "$handle" evaluated || return
  for element in "${AIRLINE_PALETTE_ELEMENTS[@]}"; do
    cfg_set_session "$session" "$element" "${evaluated[$element]}" || return
  done
  prv_set_session "$session" palette "$handle"
}

_palette_select_unlocked () {   # <session> <name>; initialization selects the default
  local session="$1" name="$2" file
  file="$(catalog_resolve "$session" palette "$name")"
  [[ -n "$file" ]] || return 2
  _palette_commit_unlocked "$session" "$file" "$name"
}

#-----------------------------------------------------------------------------#
# Adapters
#-----------------------------------------------------------------------------#

_abspath () {
  local dir base
  dir="$(dirname -- "$1")"; base="$(basename -- "$1")"
  printf '%s/%s' "$(cd -- "$dir" 2>/dev/null && pwd)" "$base"
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
declare -ga AIRLINE_LAYOUT_PART_SLOTS=() AIRLINE_LAYOUT_PART_KINDS=()
declare -ga AIRLINE_LAYOUT_PART_NAMES=() AIRLINE_LAYOUT_PART_FORMATS=()
declare -ga AIRLINE_LAYOUT_PART_IDS=() AIRLINE_LAYOUT_PART_FILES=()
declare -gA AIRLINE_LAYOUT_WIDGET_ARGS=() AIRLINE_LAYOUT_WIDGET_ARGC=()
AIRLINE_LAYOUT_GENERATION=""
AIRLINE_LAYOUT_CONFIG_SESSION=""
AIRLINE_LAYOUT_CONFIG_INVALID=""
AIRLINE_LAYOUT_CONFIG_MESSAGE=""

_layout_contract_reset () {
  AIRLINE_LAYOUT_CONFIG_SEGMENTS=()
  AIRLINE_LAYOUT_PART_SLOTS=(); AIRLINE_LAYOUT_PART_KINDS=()
  AIRLINE_LAYOUT_PART_NAMES=(); AIRLINE_LAYOUT_PART_FORMATS=()
  AIRLINE_LAYOUT_PART_IDS=(); AIRLINE_LAYOUT_PART_FILES=()
  AIRLINE_LAYOUT_WIDGET_ARGS=(); AIRLINE_LAYOUT_WIDGET_ARGC=()
  AIRLINE_LAYOUT_GENERATION="${BASHPID}-${RANDOM}-${RANDOM}"
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
  _layout_add_part "$slot" literal "" "$value" "" ""
}

_layout_add_part () {
  local slot="$1" kind="$2" name="$3" value="$4" id="$5" file="$6"
  AIRLINE_LAYOUT_PART_SLOTS+=("$slot"); AIRLINE_LAYOUT_PART_KINDS+=("$kind")
  AIRLINE_LAYOUT_PART_NAMES+=("$name"); AIRLINE_LAYOUT_PART_FORMATS+=("$value")
  AIRLINE_LAYOUT_PART_IDS+=("$id"); AIRLINE_LAYOUT_PART_FILES+=("$file")
  [[ -n "$value" ]] || return 0
  AIRLINE_LAYOUT_CONFIG_SEGMENTS[$slot]+="$(render_fragment "$slot" "$value")"
}

_layout_declare_widget () {
  local optional="$1" slot="${2:-}" name="${3:-}" file id format rc=0 index arg
  (( $# >= 3 )) || { _layout_contract_reject "widget needs <slot> <name> [arguments...]"; return; }
  shift 3
  render_segment_slot_valid "$slot" || { _layout_contract_reject "unknown segment slot '$slot'"; return; }
  file="$(catalog_describe_resolve "$AIRLINE_LAYOUT_CONFIG_SESSION" widget "$name")" || {
    _layout_contract_reject "widget '$name' not found or invalid"; return;
  }
  local -a arguments=()
  widget_arguments "$name" "$file" arguments "$@" || {
    _layout_contract_reject "widget '$name' has invalid policy arguments"; return;
  }
  set -- "${arguments[@]}"
  index=${#AIRLINE_LAYOUT_PART_SLOTS[@]}
  id="$AIRLINE_LAYOUT_GENERATION-$index"
  format="$(widget_format "$AIRLINE_LAYOUT_CONFIG_SESSION" "$id" "$file" \
    '#{@airline-palette-emphasized}' "#{@airline-palette-${AIRLINE_SLOT_TIER[$slot]}-bg}" "$@")" || rc=$?
  AIRLINE_LAYOUT_WIDGET_ARGC[$id]=$#
  index=0
  for arg in "$@"; do AIRLINE_LAYOUT_WIDGET_ARGS["$id-$index"]="$arg"; ((index+=1)); done
  if (( rc == 3 )) && [[ "$optional" == yes ]]; then
    _layout_add_part "$slot" unavailable "$name" "" "$id" "$file"
    return
  fi
  if (( rc == 3 )); then
    _layout_add_part "$slot" unavailable "$name" "" "$id" "$file"
    return
  fi
  (( rc == 0 )) || { _layout_contract_reject "widget '$name' could not be evaluated (status $rc)"; return; }
  _layout_add_part "$slot" widget "$name" "$format" "$id" "$file"
}

_layout_declare () {
  local kind="${1:-}"; shift || true
  [[ -z "$AIRLINE_LAYOUT_CONFIG_INVALID" ]] || return 1
  case "$kind" in
    segment) _layout_declare_segment "$@" ;;
    widget) _layout_declare_widget no "$@" ;;
    widget-optional) _layout_declare_widget yes "$@" ;;
    adapter) _layout_contract_reject "adapter declarations were removed; place a widget in a segment" ;;
    *) _layout_contract_reject "unknown declaration '$kind'" ;;
  esac
}

_layout_definition_evaluate () {   # <session> <file>
  local session="$1" file="$2" rc=0 output
  output="$(mktemp "${TMPDIR:-/tmp}/airline-layout-contract.XXXXXX")" || return 1
  AIRLINE_LAYOUT_CONFIG_SESSION="$session"
  _layout_contract_reset
  unset -f airline_layout_configure 2>/dev/null || true
  airline () { _layout_contract_reject "nested airline commands are not layout declarations"; }
  {
    # shellcheck source=/dev/null
    source "$file" || rc=$?
    if (( rc == 0 )) && ! declare -F airline_layout_configure >/dev/null; then
      _layout_contract_reject "missing airline_layout_configure"
      rc=1
    fi
    if (( rc == 0 )); then
      airline_layout_configure _layout_declare || rc=$?
    fi
  } > "$output"
  unset -f airline
  if [[ -s "$output" ]]; then
    AIRLINE_LAYOUT_CONFIG_MESSAGE="wrote to stdout"
    rc=1
  fi
  rm -f "$output"
  [[ -z "$AIRLINE_LAYOUT_CONFIG_INVALID" ]] || rc=1
  return "$rc"
}

_layout_commit_unlocked () {
  local session="$1" handle="$2" slot i id n
  widget_retire_session "$session" || return
  for slot in "${AIRLINE_SEGMENT_SLOTS[@]}"; do
    cfg_set_session "$session" "segment-$slot" "${AIRLINE_LAYOUT_CONFIG_SEGMENTS[$slot]:-}" || return
  done
  for ((i=0; i<${#AIRLINE_LAYOUT_PART_SLOTS[@]}; i++)); do
    id="${AIRLINE_LAYOUT_PART_IDS[i]}"
    coll_set session "$session" layout-parts "$i" "${AIRLINE_LAYOUT_PART_SLOTS[i]}" \
      "${AIRLINE_LAYOUT_PART_KINDS[i]}" "${AIRLINE_LAYOUT_PART_NAMES[i]}" "${AIRLINE_LAYOUT_PART_FORMATS[i]}" || return
    [[ -n "$id" ]] || continue
    coll_register session "$session" widgets "$id"
    prv_set_session "$session" "widget-$id-file" "${AIRLINE_LAYOUT_PART_FILES[i]}"
    prv_set_session "$session" "widget-$id-name" "${AIRLINE_LAYOUT_PART_NAMES[i]}"
    prv_set_session "$session" "widget-$id-slot" "${AIRLINE_LAYOUT_PART_SLOTS[i]}"
    prv_set_session "$session" "widget-$id-kind" "${AIRLINE_LAYOUT_PART_KINDS[i]}"
    prv_set_session "$session" "widget-$id-argc" "${AIRLINE_LAYOUT_WIDGET_ARGC[$id]}"
    for ((n=0; n<${AIRLINE_LAYOUT_WIDGET_ARGC[$id]}; n++)); do
      prv_set_session "$session" "widget-$id-arg-$n" "${AIRLINE_LAYOUT_WIDGET_ARGS[$id-$n]}"
    done
  done
  prv_set_session "$session" layout "$handle"
}

# Evaluation is also used by `layout describe`, so it records capability state in
# the committed layout rather than mutating the global problem ledger directly.
# Publishing after the configuration transaction avoids nested transactions.
layout_widget_claims_sync () {   # <session>
  local session="$1" id kind name
  for id in $(coll_members session "$session" widget-problem-retire); do
    signal_problem_close --session "$session" airline-widget "$id" || return
    with_session_transaction "$session" config coll_unregister session "$session" widget-problem-retire "$id" || return
  done
  for id in $(coll_members session "$session" widgets); do
    prv_get_session_into kind "$session" "widget-$id-kind" || return
    [[ "$kind" == unavailable ]] || continue
    prv_get_session_into name "$session" "widget-$id-name" || return
    signal_problem_report "$session" airline-widget "$id" warn "$name widget is unavailable" || return
  done
}

_layout_failure () {   # <session> <handle> <detail>
  local session="$1" handle="$2" detail="$3" message
  message="layout '$handle' $detail"
  prv_set_session "$session" "$AIRLINE_CONFIG_ERROR" "$message"
  printf 'airline: %s\n' "$message" >&2
  return "$AIRLINE_CONFIG_LAYOUT_FAILURE"
}

_apply_layout_unlocked () {
  local session="$1" handle="$2" file rc=0 detail
  file="$(_layout_file "$session" "$handle")"
  [[ -n "$file" ]] || { _layout_failure "$session" "$handle" "was not found"; return; }
  prv_unset_session "$session" "$AIRLINE_CONFIG_ERROR"
  _layout_definition_evaluate "$session" "$file" || rc=$?
  if (( rc != 0 )); then
    detail="could not be evaluated"
    [[ -z "$AIRLINE_LAYOUT_CONFIG_MESSAGE" ]] || detail="$AIRLINE_LAYOUT_CONFIG_MESSAGE"
    _layout_failure "$session" "$handle" "$detail"
    return
  fi
  _layout_commit_unlocked "$session" "$handle"
}

#-----------------------------------------------------------------------------#
# Discovery
#-----------------------------------------------------------------------------#

_layout_show () {
  local session="$1" x="${2:-}" handle; prv_get_session_into handle "$session" layout
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
  local -n all="$listname"; local key value
  for key in "${all[@]}"; do
    cfg_get_session_into value "$session" "${keypfx}${key}" || return
    command_show_row "$key" "$value"
  done
}

_palette_show () {
  local session="$1" x="${2:-}"
  [[ "$x" == name ]] && { prv_get_session "$session" palette; return 0; }
  [[ -z "$x" ]] && command_show_row name "$(prv_get_session "$session" palette)"
  if [[ -n "$x" ]]; then
    render_palette_element_valid "$x" || command_die "show: unknown target '$x'"
    opt_get_session "$session" "$(palette_public_name "$x")"
  else
    local element value
    for element in "${AIRLINE_PALETTE_ELEMENTS[@]}"; do
      opt_get_into value session "$session" "$(palette_public_name "$element")" || return
      command_show_row "$element" "$value"
    done
  fi
}

#-----------------------------------------------------------------------------#
# Public configuration services and CLI behavior boundary
#-----------------------------------------------------------------------------#

# Session coordination services. Layout owns initialization and application of the
# complete configuration snapshot; session owns only the session command and state.
_layout_initialize_unlocked () {   # <session>
  local session="$1" selected seeded=""
  catalog_register_builtins "$session" || return
  if [[ -z "$(cfg_get_session "$session" inner-bg)" ]]; then
    _palette_select_unlocked "$session" default || return $?
    seeded=1
  fi
  if [[ -n "$seeded" || -z "$(prv_get_session "$session" "$AIRLINE_KEY_DEFAULTS")" ]]; then
    prv_get_session_into selected "$session" layout
    [[ -n "$selected" ]] || selected=full
    _apply_layout_unlocked "$session" "$selected" || return $?
  fi
  _apply_public_unlocked "$session" || return $?
  prv_set_session "$session" "$AIRLINE_KEY_DEFAULTS" 1
  render "$session"
}

_layout_apply_unlocked () {   # <session>
  _apply_public_unlocked "$1" || return $?
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
      prv_get_session_into message "$session" "$AIRLINE_CONFIG_ERROR"
      [[ -n "$message" ]] || message="$operation could not apply a layout"
      signal_problem_report "$session" airline "$AIRLINE_PROBLEM_LAYOUT" fail "$message"
      ;;
  esac
}

layout_initialize () {   # <session>
  local session="$1" rc=0
  with_session_transaction "$session" config _layout_initialize_unlocked "$session" || rc=$?
  (( rc != 0 )) || layout_widget_claims_sync "$session" || rc=$?
  _layout_report_configuration_result "$session" "$rc" init
  return "$rc"
}

layout_apply () {   # <session>
  local session="$1" rc=0
  with_session_transaction "$session" config _layout_apply_unlocked "$session" || rc=$?
  (( rc != 0 )) || layout_widget_claims_sync "$session" || rc=$?
  _layout_report_configuration_result "$session" "$rc" apply
  return "$rc"
}

layout_configuration_show () {   # <session>; caller owns the config transaction
  local session="$1"
  printf '\npalette:\n'; _palette_show "$session"
  printf '\nsegment:\n'; _static_show "$session" "segment-" render_segment_slot_valid AIRLINE_SEGMENT_SLOTS
  printf '\nwidgets:\n'; widget_show_session "$session"
  printf '\nlayout:\n';  _layout_show "$session"
}

_layout_problem_message () {
  local session="$1" handle="$2" message
  prv_get_session_into message "$session" "$AIRLINE_CONFIG_ERROR"
  if [[ -n "$message" ]]; then printf '%s' "$message"
  else printf "layout '%s' could not be applied" "$handle"; fi
}

layout_palette_show () {
  local s
  (( $# <= 1 )) || command_die "palette show: too many arguments"
  s="$(command_current_session)"; _palette_show "$s" "$@"
}
layout_palette_use () {
  local s name file
  [[ $# -eq 1 && -n "$1" ]] || command_die "palette use: need exactly one <name>"
  name="$1"; [[ "$name" != */* ]] || command_die "palette use: '$name' — bare name (or 'palette load <path>')"
  s="$(command_current_session)"
  file="$(catalog_resolve "$s" palette "$name")"
  [[ -n "$file" ]] || command_die "palette use: '$name' not found on the palette path"
  _palette_apply "$s" "$file" "$name"
}
layout_palette_load () {
  local s path abs
  [[ $# -eq 1 && -n "$1" ]] || command_die "palette load: need exactly one <file>"
  path="$1"; abs="$(_abspath "$path")"
  [[ -f "$abs" ]] || command_die "palette load: no such file: $path"
  s="$(command_current_session)"
  _palette_apply "$s" "$abs" "$abs"
}
_palette_apply () {   # <session> <file> <handle>
  local s="$1" file="$2" handle="$3" rc=0
  with_session_transaction "$s" config _palette_apply_unlocked "$s" "$file" "$handle" || rc=$?
  if (( rc == AIRLINE_CONFIG_PALETTE_FAILURE )); then
    signal_problem_report "$s" airline "$AIRLINE_PROBLEM_PALETTE" fail "palette '$handle' is incomplete or could not be evaluated"
  elif (( rc == 0 )); then
    signal_problem_report "$s" airline "$AIRLINE_PROBLEM_PALETTE" ok ""
  fi
  return "$rc"
}
layout_palette_describe () {
  local s file
  (( $# == 1 )) || command_die "palette describe: need exactly one <palette>"
  s="$(command_current_session)"
  file="$(catalog_describe_resolve "$s" palette "$1")" || return
  with_session_transaction "$s" config _palette_describe_unlocked "$s" "$file" "$1"
}
_palette_describe_unlocked () {   # <session> <file> <name>
  local element
  local -A evaluated=()
  _palette_evaluate_unlocked "$1" "$2" "$3" evaluated || return
  catalog_describe_render "$3" "$2" || return
  for element in "${AIRLINE_PALETTE_ELEMENTS[@]}"; do
    command_show_row "$element" "${evaluated[$element]}"
  done
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

layout_use () {
  local s name rc=0
  [[ $# -eq 1 && -n "$1" ]] || command_die "layout use: need exactly one <name>"
  name="$1"; [[ "$name" != */* ]] || command_die "layout use: '$name' — bare name (or 'layout load <path>')"
  s="$(command_current_session)"
  [[ -n "$(catalog_resolve "$s" layout "$name")" ]] || command_die "layout use: '$name' not found"
  with_session_transaction "$s" config _layout_use_render_unlocked "$s" "$name" || rc=$?
  (( rc != 0 )) || layout_widget_claims_sync "$s" || rc=$?
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
  (( rc != 0 )) || layout_widget_claims_sync "$s" || rc=$?
  case "$rc" in
    0) signal_problem_report "$s" airline "$AIRLINE_PROBLEM_LAYOUT" ok "" ;;
    "$AIRLINE_CONFIG_PALETTE_FAILURE")
      signal_problem_report "$s" airline "$AIRLINE_PROBLEM_PALETTE" fail "layout load could not resolve a complete palette" ;;
    *) signal_problem_report "$s" airline "$AIRLINE_PROBLEM_LAYOUT" fail "$(_layout_problem_message "$s" "$abs")" ;;
  esac
  (( rc == 0 )) || return "$rc"
}
layout_describe () (
  local session file slot i id n
  (( $# == 1 )) || command_die "layout describe: need exactly one <layout>"
  session="$(command_current_session)"
  file="$(catalog_describe_resolve "$session" layout "$1")" || return
  if ! _layout_definition_evaluate "$session" "$file"; then
    printf "airline: layout '%s' %s\n" "$1" "${AIRLINE_LAYOUT_CONFIG_MESSAGE:-could not be evaluated}" >&2
    return "$AIRLINE_CONFIG_LAYOUT_FAILURE"
  fi
  catalog_describe_render "$1" "$file" || return
  printf '\nsegments:\n'
  for slot in "${AIRLINE_SEGMENT_SLOTS[@]}"; do
    command_show_row "$slot" "${AIRLINE_LAYOUT_CONFIG_SEGMENTS[$slot]:-}"
  done
  printf '\nfragments:\n'
  for ((i=0; i<${#AIRLINE_LAYOUT_PART_SLOTS[@]}; i++)); do
    printf '  %s %s %s %s\n' "${AIRLINE_LAYOUT_PART_SLOTS[i]}" "${AIRLINE_LAYOUT_PART_KINDS[i]}" \
      "${AIRLINE_LAYOUT_PART_NAMES[i]}" "${AIRLINE_LAYOUT_PART_FORMATS[i]}"
    if [[ -n "${AIRLINE_LAYOUT_PART_FILES[i]}" ]]; then
      printf '    source %s\n' "${AIRLINE_LAYOUT_PART_FILES[i]}"
      id="${AIRLINE_LAYOUT_PART_IDS[i]}"
      printf '    args'
      for ((n=0; n<${AIRLINE_LAYOUT_WIDGET_ARGC[$id]:-0}; n++)); do
        printf ' %q' "${AIRLINE_LAYOUT_WIDGET_ARGS[$id-$n]}"
      done
      printf '\n'
    fi
  done
)
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

_palette_apply_unlocked () {
  _apply_public_unlocked "$1" &&
    _palette_commit_unlocked "$1" "$2" "$3" &&
    render "$1"
}
_layout_use_render_unlocked () {
  _apply_public_unlocked "$1" &&
    _apply_layout_unlocked "$1" "$2" && render "$1"
}
_layout_load_render_unlocked () { _layout_use_render_unlocked "$@"; }

# vim: ft=bash
