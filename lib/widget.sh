#!/usr/bin/env bash
# Stateless native format widgets.
# shellcheck shell=bash

widget_quote () {
  local arg
  for arg in "$@"; do printf "'%s' " "${arg//\'/\'\\\'\'}"; done
}

widget_runtime () {
  [[ -n "${AIRLINE_WIDGET_RUNTIME:-}" ]] || return 2
  printf '#(%s)' "$(widget_quote "$AIRLINE_WIDGET_RUNTIME" "$@")"
}

widget_literal () { local text="$1"; printf '%s' "${text//#/##}"; }

widget_arguments () { # <catalog name> <file> <destination array> [placement args...]
  local name="$1" file="$2" destination="$3" key value options
  shift 3
  local -n resolved="$destination"
  resolved=()
  options="$(catalog_metadata "$file" options)"
  [[ -n "$options" ]] || { resolved=("$@"); return; }
  [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]] || return 2
  local -A values=()
  for key in $options; do
    [[ "$key" =~ ^[a-z][a-z-]*$ && -z "${values[$key]+present}" ]] || return 2
    value="$(catalog_metadata "$file" "default-$key")" || {
      echo "airline: $name: missing default-$key metadata" >&2; return 2;
    }
    values[$key]="$value"
    value="$(pub_get "widget-$name-$key")"
    [[ -z "$value" ]] || values[$key]="$value"
  done
  while (( $# )); do
    key="${1#--}"
    [[ "$1" == --* && "$key" =~ ^[a-z][a-z-]*$ && $# -ge 2 && -n "${values[$key]+present}" ]] || {
      echo "airline: $name: expected a declared option and value" >&2; return 2;
    }
    values[$key]="$2"; shift 2
  done
  for key in $options; do resolved+=("--$key" "${values[$key]}"); done
}

widget_text () {
  local text; text="$(widget_literal "$1")"
  text="${text//,/#,}"; printf '%s' "${text//\}/#\}}"
}

widget_output_valid () {
  local bytes clean
  bytes="$(wc -c < "$1")"
  (( bytes <= $2 )) && [[ $(wc -l < "$1") -le 1 ]] || return 2
  clean="$(LC_ALL=C tr -d '\000-\011\013-\037\177' < "$1" | wc -c)"
  (( clean == bytes ))
}

widget_format () (   # <session> <instance> <definition> <fg> <bg> [args...]
  # These locals are the widget's sourced-file API; definitions read them by name.
  # shellcheck disable=SC2034
  local AIRLINE_WIDGET_SESSION="$1" AIRLINE_WIDGET_INSTANCE="$2" file="$3"
  local AIRLINE_WIDGET_FG="$4" AIRLINE_WIDGET_BG="$5" output rc=0 unavailable=0
  shift 5
  AIRLINE_WIDGET_RUNTIME="${file%.sh}"
  unset -f airline_widget_format airline_widget_available 2>/dev/null || true
  output="$(mktemp)" || return 1
  trap 'rc=$?; rm -f "$output"; if (( rc == 3 && unavailable == 0 )); then exit 2; fi' EXIT
  # shellcheck disable=SC1090
  source "$file" > "$output" || return
  [[ ! -s "$output" ]] || { echo 'airline: widget source wrote to stdout' >&2; return 2; }
  declare -F airline_widget_format >/dev/null || { echo 'airline: missing airline_widget_format' >&2; return 2; }
  airline_widget_format "$AIRLINE_WIDGET_FG" "$AIRLINE_WIDGET_BG" "$@" > "$output" || return
  widget_output_valid "$output" 8192 || {
    echo 'airline: widget format must be one line, at most 8192 bytes' >&2; return 2;
  }
  local format; format="$(cat "$output")"
  local directive='(#[[]|,)(align|list|range|fill|width)='
  [[ ! "$format" =~ [[:cntrl:]] && ! "$format" =~ $directive ]] || {
    echo 'airline: invalid control or layout directive in widget format' >&2; return 2;
  }
  if declare -F airline_widget_available >/dev/null; then
    airline_widget_available "$@" > "$output" || rc=$?
    [[ ! -s "$output" ]] || return 2
    # shellcheck disable=SC2034
    case "$rc" in 0) ;; 3) unavailable=1; return 3 ;; *) return 2 ;; esac
  fi
  printf '%s' "$format"
)

widget_describe () (
  (( $# >= 1 )) || command_die 'widget describe: need <widget> [arguments...]'
  local name="$1" session file format rc=0; shift
  session="$(command_current_session)"
  file="$(catalog_describe_resolve "$session" widget "$name")" || return
  local -a arguments=()
  widget_arguments "$name" "$file" arguments "$@" || return
  set -- "${arguments[@]}"
  format="$(widget_format "$session" inspect "$file" \
    '#{@airline-palette-emphasized}' '#{@airline-palette-inner-bg}' "$@")" || rc=$?
  (( rc == 0 || rc == 3 )) || return "$rc"
  catalog_describe_render "$name" "$file" || return
  command_show_row effective-arguments "$(widget_quote "$@")"
  if (( rc == 3 )); then command_show_row available no
  else command_show_row available yes; command_show_row format "$format"; fi
)

widget_list () {
  (( $# == 0 )) || command_die 'widget list: takes no arguments'
  catalog_list "$(command_current_session)" widget
}
widget_register () { catalog_register "$(command_current_session)" widget "$@"; }
widget_show_session () {
  local id session="$1"
  for id in $(coll_members session "$session" widgets); do
    command_show_row "$id" "$(prv_get_session "$session" "widget-$id-name")"
  done
}

widget_retire_session () {
  local session="$1" slot="${2:-}" id count i
  for id in $(coll_members session "$session" widgets); do
    [[ -z "$slot" || "$(prv_get_session "$session" "widget-$id-slot")" == "$slot" ]] || continue
    count="$(prv_get_session "$session" "widget-$id-argc")"
    for ((i=0; i<${count:-0}; i++)); do prv_unset_session "$session" "widget-$id-arg-$i"; done
    for i in file name slot argc; do prv_unset_session "$session" "widget-$id-$i"; done
    coll_unregister session "$session" widgets "$id"
  done
  for id in $(coll_members session "$session" layout-parts); do
    if [[ -z "$slot" || "$(coll_get session "$session" layout-parts "$id")" == "$slot"$'\t'* ]]; then
      coll_unregister session "$session" layout-parts "$id"
    fi
  done
  for id in $(coll_members session "$session" adapters); do coll_unregister session "$session" adapters "$id"; done
  for id in $(coll_members session "$session" path-adapter); do coll_unregister session "$session" path-adapter "$id"; done
}
