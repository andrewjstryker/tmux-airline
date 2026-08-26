#!/usr/bin/env bash
#
# signal.sh — status, health, problems, and transient consumption.
#
# Status and health are window-scoped contributor collections; problems are
# session-scoped. Signal owns validation, transactional mutation, projection
# orchestration, redraw gating, and the consume-on-view hook.

# shellcheck shell=bash

signal_condition_valid () {
  local level
  for level in "${AIRLINE_CONDITION_LEVELS[@]}"; do [[ "$level" == "$1" ]] && return 0; done
  return 1
}

_signal_status_valid () {
  local level
  for level in "${AIRLINE_STATUS_LEVELS[@]}"; do [[ "$level" == "$1" ]] && return 0; done
  return 1
}

# Store one managed session problem and refresh its aggregate projection. `ok` is
# recovery, not retained state. Return 0 only when the visible badge changed.
_signal_problem_store_unlocked () {   # <session> <key> <ok|warn|fail> [<message>]
  local session="$1" key="$2" level="$3" message="${4:-}" tuple desired
  local changed="" projected=1
  if [[ "$level" == ok ]]; then
    tuple="$(coll_get_session "$session" problem "$key")"
    if coll_has_session "$session" problem "$key" || [[ -n "$tuple" ]]; then
      coll_unregister_session "$session" problem "$key"
      changed=1
    fi
  else
    tuple="$(coll_get_session "$session" problem "$key")"
    desired="$(printf '%s\t%s' "$level" "$message")"
    if ! coll_has_session "$session" problem "$key" || [[ "$tuple" != "$desired" ]]; then
      coll_set_session "$session" problem "$key" "$level" "$message"
      changed=1
    fi
  fi
  if [[ -n "$changed" ]] && render_problem_project "$session"; then projected=0; fi
  return "$projected"
}

_signal_problem_store () {   # <session> <key> <ok|warn|fail> [<message>]
  with_session_transaction "$1" problem _signal_problem_store_unlocked "$@"
}

# Shared reporting path for airline-owned layout and runner problems. Managed
# reporters already hold canonical session ids and validated tuples.
signal_problem_report () {   # <session> <key> <ok|warn|fail> [<message>]
  _signal_problem_store "$@" && redraw
  return 0
}

_signal_ensure_transient_hook () {
  opt_set_global focus-events on
  hook_set "pane-focus-out[90]" \
    "run-shell -b \"'$AIRLINE_DIR/airline.sh' signal clear-transient -t #{window_id}\""
}

_signal_clear_transient_namespace_unlocked () {   # <window> <status|health>
  local win="$1" ns="$2" changed="" key f1 f2
  for key in $(coll_members_window "$win" "$ns"); do
    IFS=$'\t' read -r f1 f2 <<< "$(coll_get_window "$win" "$ns" "$key")"
    [[ "$f2" == 1 ]] && { coll_unregister_window "$win" "$ns" "$key"; changed=1; }
  done
  [[ -n "$changed" ]] || return 1
  "render_${ns}_project" "$win"
}

signal_clear_transient () {   # [-t <window>]
  local win="" ns changed=""
  while (( $# )); do
    case "$1" in
      -t)
        [[ $# -ge 2 && -n "$2" ]] || command_die "signal clear-transient: -t requires <window>"
        [[ -z "$win" ]] || command_die "signal clear-transient: duplicate -t"
        win="$2"
        shift 2
        ;;
      *) command_die "signal clear-transient: unknown argument '$1'" ;;
    esac
  done
  [[ -n "$win" ]] || win="$(current_window)"
  win="$(resolve_window "$win")"
  [[ -n "$win" ]] || command_die "signal clear-transient: cannot resolve window"
  for ns in status health; do
    with_window_transaction "$win" "$ns" _signal_clear_transient_namespace_unlocked \
      "$win" "$ns" && changed=1
  done
  [[ -n "$changed" ]] && redraw
  return 0
}

_signal_set_unlocked () {   # <ns> <clear-value|""> <key> <value> <transient> <window>
  local ns="$1" clear_value="$2" key="$3" value="$4" transient="$5" win="$6"
  if [[ -n "$clear_value" && "$value" == "$clear_value" ]]; then
    coll_unregister_window "$win" "$ns" "$key"
  else
    coll_set_window "$win" "$ns" "$key" "$value" "$transient"
  fi
  "render_${ns}_project" "$win"
}

_signal_set () {   # <ns> <validator> <clear-value|""> <key> <value> [options]
  local ns="$1" valid="$2" clear_value="$3"; shift 3
  local key="" value="" transient="" win=""; local -a pos=()
  while (( $# )); do
    case "$1" in
      --transient) transient=1; shift ;;
      -t)
        [[ $# -ge 2 && -n "$2" ]] || command_die "$ns set: -t requires <window>"
        win="$2"
        shift 2
        ;;
      *) pos+=("$1"); shift ;;
    esac
  done
  key="${pos[0]:-}"; value="${pos[1]:-}"
  [[ -n "$key" ]] || command_die "$ns set: need <key>"
  "$valid" "$value" || command_die "$ns set: invalid value '$value'"
  [[ -n "$win" ]] || win="$(current_window)"
  win="$(resolve_window "$win")"
  with_window_transaction "$win" "$ns" _signal_set_unlocked \
    "$ns" "$clear_value" "$key" "$value" "$transient" "$win" && redraw
  [[ -n "$transient" ]] && _signal_ensure_transient_hook
  return 0
}

_signal_clear_unlocked () {   # <ns> <key> <window>
  local ns="$1" key="$2" win="$3"
  coll_unregister_window "$win" "$ns" "$key"
  "render_${ns}_project" "$win"
}

_signal_clear () {   # <ns> <key> [-t <window>]
  local ns="$1"; shift
  local key="" win=""
  while (( $# )); do
    case "$1" in
      -t)
        [[ $# -ge 2 && -n "$2" ]] || command_die "$ns clear: -t requires <window>"
        win="$2"
        shift 2
        ;;
      *) key="$1"; shift ;;
    esac
  done
  [[ -n "$key" ]] || command_die "$ns clear: need <key>"
  [[ -n "$win" ]] || win="$(current_window)"
  win="$(resolve_window "$win")"
  with_window_transaction "$win" "$ns" _signal_clear_unlocked "$ns" "$key" "$win" && redraw
  return 0
}

_signal_show_unlocked () {   # <ns> <window> [<key>]
  local ns="$1" win="$2" key="${3:-}" f1 f2 member
  if [[ -n "$key" ]]; then
    IFS=$'\t' read -r f1 _ <<< "$(coll_get_window "$win" "$ns" "$key")"
    printf '%s\n' "$f1"
    return 0
  fi
  for member in $(coll_members_window "$win" "$ns"); do
    IFS=$'\t' read -r f1 f2 <<< "$(coll_get_window "$win" "$ns" "$member")"
    command_show_row "$member" "$f1${f2:+  (transient)}"
  done
}

_signal_show () {   # <ns> [<key>] [-t <window>]
  local ns="$1"; shift
  local key="" win=""
  while (( $# )); do
    case "$1" in
      -t)
        [[ $# -ge 2 && -n "$2" ]] || command_die "$ns show: -t requires <window>"
        win="$2"
        shift 2
        ;;
      *) key="$1"; shift ;;
    esac
  done
  [[ -n "$win" ]] || win="$(current_window)"
  win="$(resolve_window "$win")"
  with_window_transaction "$win" "$ns" _signal_show_unlocked "$ns" "$win" "$key"
}

_signal_problem_session () {   # <verb> <session-target>
  local verb="$1" target="${2:-}" session
  [[ -n "$target" ]] || command_die "problem $verb: need <session>"
  session="$(resolve_session_target "$target")"
  [[ -n "$session" ]] || command_die "problem $verb: cannot resolve session '$target'"
  printf '%s' "$session"
}

signal_problem_set () {   # <session> <key> <level> [<message...>]
  local target="${1:-}" key="${2:-}" level="${3:-}" message session
  shift $(( $# < 3 ? $# : 3 ))
  message="$*"
  session="$(_signal_problem_session set "$target")"
  [[ -n "$key" ]] || command_die "problem set: need <key>"
  [[ "$key" != *[[:space:]]* ]] || command_die "problem set: key must not contain whitespace"
  signal_condition_valid "$level" || command_die "problem set: invalid level '$level'"
  if [[ "$level" != ok ]]; then
    [[ -n "$message" ]] || command_die "problem set: need <message>"
    [[ "$message" != *$'\t'* ]] || command_die "problem set: message must not contain a tab"
  fi
  _signal_problem_store "$session" "$key" "$level" "$message" && redraw
  return 0
}

signal_problem_clear () {   # <session> <key>
  local target="${1:-}" key="${2:-}" session
  (( $# <= 2 )) || command_die "problem clear: too many arguments"
  session="$(_signal_problem_session clear "$target")"
  [[ -n "$key" ]] || command_die "problem clear: need <key>"
  _signal_problem_store "$session" "$key" ok "" && redraw
  return 0
}

_signal_problem_show_session_unlocked () {   # <session> [<key>] [<grouped=1>]
  local session="$1" key="${2:-}" grouped="${3:-}" tuple level message member members
  if [[ -n "$key" ]]; then
    coll_get_session "$session" problem "$key"
    return 0
  fi
  members="$(coll_members_session "$session" problem)"
  [[ -z "$grouped" || -z "$members" ]] || printf '%s:\n' "$session"
  for member in $members; do
    tuple="$(coll_get_session "$session" problem "$member")"
    IFS=$'\t' read -r level message <<< "$tuple"
    command_show_row "${grouped:+  }$member" "$level${message:+  $message}"
  done
}

_signal_problem_show_session () {   # <session> [<key>] [<grouped=1>]
  with_session_transaction "$1" problem _signal_problem_show_session_unlocked "$@"
}

signal_problem_show () {   # [<session> [<key>]]
  local target="${1:-}" key="${2:-}" session
  (( $# <= 2 )) || command_die "problem show: too many arguments"
  if [[ -n "$target" ]]; then
    session="$(_signal_problem_session show "$target")"
    _signal_problem_show_session "$session" "$key"
    return 0
  fi
  for session in $(list_sessions); do
    _signal_problem_show_session "$session" "" 1
  done
}

signal_status_set () { _signal_set status _signal_status_valid "" "$@"; }
signal_status_clear () { _signal_clear status "$@"; }
signal_status_show () { _signal_show status "$@"; }
signal_health_set () { _signal_set health signal_condition_valid ok "$@"; }
signal_health_clear () { _signal_clear health "$@"; }
signal_health_show () { _signal_show health "$@"; }

# vim: ft=bash
