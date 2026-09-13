#!/usr/bin/env bash
# Native format widgets and bounded, instance-scoped observation jobs.
# shellcheck shell=bash
# shellcheck disable=SC2030,SC2031 # widget contexts intentionally live in isolated workers.

widget_quote () {
  local arg
  for arg in "$@"; do printf "'%s' " "${arg//\'/\'\\\'\'}"; done
}
widget_reading () { printf '#{%s}' "$(prv_name "widget-$AIRLINE_WIDGET_INSTANCE-value")"; }
widget_job () {
  printf '#(%s)' "$(widget_quote "$AIRLINE_DIR/airline.sh" widget run -t "$AIRLINE_WIDGET_SESSION" "$AIRLINE_WIDGET_INSTANCE")"
}
widget_literal () { local text="$1"; printf '%s' "${text//#/##}"; }

widget_output_valid () {
  local bytes clean
  bytes="$(wc -c < "$1")"
  (( bytes <= $2 )) && [[ $(wc -l < "$1") -le 1 ]] || return 2
  # Check raw bytes before Bash strips NULs or trailing newlines on capture.
  clean="$(LC_ALL=C tr -d '\000-\011\013-\037\177' < "$1" | wc -c)"
  (( clean == bytes ))
}

widget_format () (   # <session> <instance> <definition> [args...]
  local AIRLINE_WIDGET_SESSION="$1" AIRLINE_WIDGET_INSTANCE="$2" file="$3" output rc=0 unavailable=0
  shift 3
  unset -f airline_widget_format airline_widget_available airline_widget_sample
  output="$(mktemp)" || return 1
  trap 'rc=$?; rm -f "$output"; if (( rc == 3 && unavailable == 0 )); then exit 2; fi' EXIT
  # Source output is not a format; definitions must be quiet.
  # shellcheck source=/dev/null
  source "$file" > "$output" || return
  [[ ! -s "$output" ]] || { echo 'airline: widget source wrote to stdout' >&2; return 2; }
  declare -F airline_widget_format >/dev/null || { echo 'airline: missing airline_widget_format' >&2; return 2; }
  local interval budget
  interval="$(catalog_metadata "$file" interval)"; interval="${interval:-5}"
  budget="$(catalog_metadata "$file" timeout)"; budget="${budget:-1}"
  if [[ ! "$interval" =~ ^[1-9][0-9]{0,5}$ || ! "$budget" =~ ^[1-9][0-9]{0,2}$ ]] || (( budget > interval )); then
    echo 'airline: invalid widget interval or timeout' >&2; return 2
  fi
  airline_widget_format "$@" > "$output" || return
  # Check before command substitution strips trailing newlines.
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
    # shellcheck disable=SC2034 # Read by the EXIT trap after this function returns.
    case "$rc" in 0) ;; 3) unavailable=1; return 3 ;; *) return 2 ;; esac
  fi
  printf '%s' "$format"
)

widget_describe () (
  (( $# >= 1 )) || command_die 'widget describe: need <widget> [arguments...]'
  local name="$1" session file format rc=0; shift
  session="$(command_current_session)"
  file="$(catalog_describe_resolve "$session" widget "$name")" || return
  format="$(widget_format "$session" inspect "$file" "$@")" || rc=$?
  (( rc == 0 || rc == 3 )) || return "$rc"
  catalog_describe_render "$name" "$file" || return
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
    coll_register session "$session" retired-widgets "$id"
    count="$(prv_get_session "$session" "widget-$id-argc")"
    for ((i=0; i<${count:-0}; i++)); do prv_unset_session "$session" "widget-$id-arg-$i"; done
    for i in file name slot argc value stamp; do prv_unset_session "$session" "widget-$id-$i"; done
    coll_unregister session "$session" widgets "$id"
  done
  for id in $(coll_members session "$session" layout-parts); do
    if [[ -z "$slot" || "$(coll_get session "$session" layout-parts "$id")" == "$slot"$'\t'* ]]; then
      coll_unregister session "$session" layout-parts "$id"
    fi
  done
  # Adapter-era metadata is obsolete; native plugin settings are not ours to erase.
  for id in $(coll_members session "$session" adapters); do coll_unregister session "$session" adapters "$id"; done
  for id in $(coll_members session "$session" path-adapter); do coll_unregister session "$session" path-adapter "$id"; done
  return 0
}

widget_reconcile_session () ( # outside config transactions, after retirement
  local session="$1" id root dir lock
  root="$(widget_cache_root)" || return
  for id in $(coll_members session "$session" retired-widgets); do
    [[ "$id" =~ ^[0-9]+-[0-9]+-[0-9]+-[0-9]+$ ]] || continue
    dir="$root/${session//[^0-9]/}/$id"
    # A running sample keeps this lock through publication and failure reporting.
    # Wait outside the config lock, then close its claim and remove its state.
    if [[ -d "$dir" ]]; then
      exec {lock}>"$dir/lock" || continue
      flock "$lock" || continue
    fi
    signal_problem_close --session "$session" airline-widget "$id" || return
    rm -rf -- "${dir:?}"
    with_session_transaction "$session" config coll_unregister session "$session" retired-widgets "$id" || return
    if [[ -n "${lock:-}" ]]; then exec {lock}>&-; unset lock; fi
  done
)

widget_cleanup () { # <canonical closed session>; hook-only service
  [[ $# == 1 && "$1" =~ ^\$[0-9]+$ ]] || return 2
  local root
  [[ -z "$(resolve_session_target "$1")" ]] || return 0
  root="$(widget_cache_root)" || return
  rm -rf -- "${root:?}/${1//[^0-9]/}"
}
widget_collect () {
  local root path live
  root="$(widget_cache_root)" || return
  live=" $(list_sessions | tr -d '$' | tr '\n' ' ') "
  for path in "$root"/*; do
    [[ -d "$path" && "${path##*/}" =~ ^[0-9]+$ ]] || continue
    [[ "$live" == *" ${path##*/} "* ]] || rm -rf -- "${path:?}"
  done
  return 0
}
widget_install_hooks () {
  hook_set 'session-closed[91]' \
    "run-shell -b \"'$AIRLINE_DIR/airline.sh' widget _cleanup '#{hook_session}'\""
}

_widget_publish () {   # <session> <instance> <value> <stamp>
  coll_has session "$1" widgets "$2" || return 3
  prv_set_session "$1" "widget-$2-value" "$3" || return
  prv_set_session "$1" "widget-$2-stamp" "$4" || return
  redraw
}

widget_run () (
  [[ $# == 3 && "$1" == -t ]] || command_die 'widget run: need -t <session> <instance>'
  local session id="$3" file argc i root dir interval budget now stamp value rc=0
  local -a args=()
  [[ "$id" =~ ^[0-9]+-[0-9]+-[0-9]+-[0-9]+$ ]] || return 2
  session="$(resolve_session_target "$2")"; [[ -n "$session" ]] || return 3
  coll_has session "$session" widgets "$id" || return 3
  root="$(widget_cache_root)" || return
  dir="${root:?}/${session//[^0-9]/}/$id"
  umask 077
  mkdir -p "$dir" || return
  exec {lock}>"$dir/lock" || return
  flock -n "$lock" || { printf '\n'; return 0; }
  # Retirement may have raced directory creation; do not recreate it thereafter.
  coll_has session "$session" widgets "$id" || { rm -rf -- "$dir"; return 3; }
  file="$(prv_get_session "$session" "widget-$id-file")"
  argc="$(prv_get_session "$session" "widget-$id-argc")"
  for ((i=0; i<${argc:-0}; i++)); do args+=("$(prv_get_session "$session" "widget-$id-arg-$i")"); done
  interval="$(catalog_metadata "$file" interval)"; interval="${interval:-5}"
  budget="$(catalog_metadata "$file" timeout)"; budget="${budget:-1}"
  [[ "$interval" =~ ^[1-9][0-9]{0,5}$ && "$budget" =~ ^[1-9][0-9]{0,2}$ ]] && (( budget <= interval )) || return 2
  printf -v now '%(%s)T' -1
  stamp=0; [[ ! -f "$dir/stamp" ]] || read -r stamp < "$dir/stamp"
  [[ "$stamp" =~ ^[0-9]+$ ]] || stamp=0
  if (( now >= stamp && now-stamp < interval )); then printf '\n'; return 0; fi
  printf '%s\n' "$now" > "$dir/stamp"
  (
    ulimit -f 16
    export AIRLINE_WIDGET_SESSION="$session" AIRLINE_WIDGET_INSTANCE="$id" AIRLINE_WIDGET_STATE_DIR="$dir"
    timeout -k 1 "$budget" "$AIRLINE_DIR/scripts/widget-sample" "$file" "${args[@]}"
  ) > "$dir/output" 2> "$dir/error" || rc=$?
  [[ -d "$dir" ]] || return 3
  if widget_output_valid "$dir/output" 4096; then value="$(cat "$dir/output")"
  else rc=2; value=''; fi
  [[ ! "$value" =~ [[:cntrl:]] ]] || rc=2
  if (( rc != 0 )); then value='?'; fi
  with_session_transaction "$session" config _widget_publish "$session" "$id" "$value" "$now" || return
  # The instance id includes its generation; another widget never recovers this claim.
  if coll_has session "$session" widgets "$id"; then
    if (( rc == 0 )); then signal_problem_report "$session" airline-widget "$id" ok ''
    else signal_problem_report "$session" airline-widget "$id" fail "$(prv_get_session "$session" "widget-$id-name"): sample failed ($rc) $(head -c 256 "$dir/error")"; fi
  fi || return
  printf '\n'
)
