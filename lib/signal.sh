#!/usr/bin/env bash
#
# signal.sh — status, health, problems, and transient status consumption.
#
# Status is window-scoped display state: it is message-free and may be transient.
# Health and problem are persistent keyed conditions with the same level/message
# operations; health is owned by a window, while problem is owned by a session.
#
# Signal owns validation, transactional mutation, projection orchestration, redraw
# gating, and the consume-on-view hook.

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

_signal_validate_key () {   # <command> <key>
  local command="$1" key="$2"
  [[ -n "$key" ]] || command_die "$command: need <key>"
  [[ "$key" != *[[:space:]]* ]] || command_die "$command: key must not contain whitespace"
}

_signal_validate_condition () {   # <command> <ok|warn|fail> <message>
  local command="$1" level="$2" message="$3"
  signal_condition_valid "$level" || command_die "$command: invalid level '$level'"
  [[ "$message" != *$'\t'* ]] || command_die "$command: message must not contain a tab"
  case "$level" in
    ok) [[ -z "$message" ]] || command_die "$command: ok takes no <message>" ;;
    warn|fail) [[ -n "$message" ]] || command_die "$command: need <message>" ;;
  esac
}

_signal_resolve_window () {   # <destination> <command> [<target>]
  local -n destination="$1"
  local command="$2" target="${3:-}" resolved
  if [[ -z "$target" ]]; then
    resolved="$(current_window)" || command_die "$command: cannot resolve current window"
    target="$resolved"
  fi
  resolved="$(resolve_window "$target")" || command_die "$command: cannot resolve window '$target'"
  [[ -n "$resolved" ]] || command_die "$command: cannot resolve window '$target'"
  destination="$resolved"
}

_signal_resolve_session () {   # <destination> <command> <target>
  local -n destination="$1"
  local command="$2" target="$3" resolved
  [[ -n "$target" ]] || command_die "$command: need <session>"
  resolved="$(resolve_session_target "$target")" || \
    command_die "$command: cannot resolve session '$target'"
  [[ -n "$resolved" ]] || command_die "$command: cannot resolve session '$target'"
  # shellcheck disable=SC2034 # assignment is through the caller-selected nameref
  destination="$resolved"
}

# Projection status is private redraw protocol: 0 means the aggregate scalar
# changed, 1 means it did not. Public signal operations return ordinary success in
# both cases; failures above 1 still propagate.
_signal_project_and_redraw () {   # <status|health|problem> <owner>
  local namespace="$1" owner="$2" rc=0
  case "$namespace" in
    status)  render_status_project "$owner" || rc=$? ;;
    health)  render_health_project "$owner" || rc=$? ;;
    problem) render_problem_project "$owner" || rc=$? ;;
  esac
  case "$rc" in
    0) redraw ;;
    1) return 0 ;;
    *) return "$rc" ;;
  esac
}

#-----------------------------------------------------------------------------#
# Persistent conditions — common health/problem implementation
#-----------------------------------------------------------------------------#

_signal_condition_store_unlocked () {   # <window|session> <owner> <ns> <key> <level> <message>
  local scope="$1" owner="$2" namespace="$3" key="$4" level="$5" message="$6"
  local get="coll_get_$scope" has="coll_has_$scope" set="coll_set_$scope"
  local unset="coll_unregister_$scope" tuple desired has_rc=0

  tuple="$("$get" "$owner" "$namespace" "$key")" || return
  "$has" "$owner" "$namespace" "$key" || has_rc=$?
  (( has_rc <= 1 )) || return "$has_rc"

  if [[ "$level" == ok ]]; then
    if (( has_rc == 1 )) && [[ -z "$tuple" ]]; then return 0; fi
    "$unset" "$owner" "$namespace" "$key" || return
  else
    desired="$(printf '%s\t%s' "$level" "$message")"
    if (( has_rc == 0 )) && [[ "$tuple" == "$desired" ]]; then return 0; fi
    "$set" "$owner" "$namespace" "$key" "$level" "$message" || return
  fi

  _signal_project_and_redraw "$namespace" "$owner"
}

_signal_condition_store () {   # <window|session> <owner> <health|problem> <key> <level> <message>
  local scope="$1" owner="$2" namespace="$3" transaction="with_${1}_transaction"
  "$transaction" "$owner" "$namespace" _signal_condition_store_unlocked "$@"
}

_signal_condition_show_unlocked () {   # <window|session> <owner> <ns> [<key>] [<grouped>]
  local scope="$1" owner="$2" namespace="$3" key="${4:-}" grouped="${5:-}"
  local get="coll_get_$scope" members_fn="coll_members_$scope"
  local members member tuple level message
  if [[ -n "$key" ]]; then
    "$get" "$owner" "$namespace" "$key"
    return
  fi
  members="$("$members_fn" "$owner" "$namespace")" || return
  [[ -z "$grouped" || -z "$members" ]] || printf '%s:\n' "$owner"
  for member in $members; do
    tuple="$("$get" "$owner" "$namespace" "$member")" || return
    IFS=$'\t' read -r level message <<< "$tuple"
    command_show_row "${grouped:+  }$member" "$level${message:+  $message}"
  done
}

_signal_condition_show () {   # <window|session> <owner> <health|problem> [<key>] [<grouped>]
  local scope="$1" owner="$2" namespace="$3" transaction="with_${1}_transaction"
  "$transaction" "$owner" "$namespace" _signal_condition_show_unlocked "$@"
}

# Shared reporting path for airline-owned layout and runner problems. Managed
# reporters already hold canonical session ids and validated tuples.
signal_problem_report () {   # <session> <key> <ok|warn|fail> <message>
  _signal_condition_store session "$1" problem "$2" "$3" "${4:-}"
}

#-----------------------------------------------------------------------------#
# Status — window display state, optionally consumed after viewing
#-----------------------------------------------------------------------------#

_signal_ensure_transient_hook () {
  opt_set_global focus-events on || return
  hook_set "pane-focus-out[90]" \
    "run-shell -b \"'$AIRLINE_DIR/airline.sh' signal clear-transient -t #{window_id}\""
}

_signal_status_set_unlocked () {   # <window> <key> <value> <transient>
  local win="$1" key="$2" value="$3" transient="$4" tuple desired has_rc=0
  tuple="$(coll_get_window "$win" status "$key")" || return
  coll_has_window "$win" status "$key" || has_rc=$?
  (( has_rc <= 1 )) || return "$has_rc"
  desired="$(printf '%s\t%s' "$value" "$transient")"
  if (( has_rc == 0 )) && [[ "$tuple" == "$desired" ]]; then return 0; fi
  coll_set_window "$win" status "$key" "$value" "$transient" || return
  _signal_project_and_redraw status "$win"
}

signal_status_set () {   # <key> <value> [--transient] [-t <window>]
  local key value transient="" win="" seen_transient="" seen_target=""
  local -a positionals=()
  while (( $# )); do
    case "$1" in
      --transient)
        [[ -z "$seen_transient" ]] || command_die "status set: duplicate --transient"
        transient=1; seen_transient=1; shift
        ;;
      -t)
        [[ $# -ge 2 && -n "$2" ]] || command_die "status set: -t requires <window>"
        [[ -z "$seen_target" ]] || command_die "status set: duplicate -t"
        [[ "$2" != -t && "$2" != --transient ]] || \
          command_die "status set: -t requires <window>"
        win="$2"; seen_target=1; shift 2
        ;;
      -*) command_die "status set: unknown option '$1'" ;;
      *) positionals+=("$1"); shift ;;
    esac
  done
  (( ${#positionals[@]} == 2 )) || command_die "status set: need exactly <key> <value>"
  key="${positionals[0]}"; value="${positionals[1]}"
  _signal_validate_key "status set" "$key"
  _signal_status_valid "$value" || command_die "status set: invalid value '$value'"
  _signal_resolve_window win "status set" "$win"
  with_window_transaction "$win" status _signal_status_set_unlocked \
    "$win" "$key" "$value" "$transient" || return
  [[ -z "$transient" ]] || _signal_ensure_transient_hook
}

_signal_status_clear_unlocked () {   # <window> <key>
  local win="$1" key="$2" tuple has_rc=0
  tuple="$(coll_get_window "$win" status "$key")" || return
  coll_has_window "$win" status "$key" || has_rc=$?
  (( has_rc <= 1 )) || return "$has_rc"
  if (( has_rc == 1 )) && [[ -z "$tuple" ]]; then return 0; fi
  coll_unregister_window "$win" status "$key" || return
  _signal_project_and_redraw status "$win"
}

signal_status_clear () {   # <key> [-t <window>]
  local key win="" seen_target=""; local -a positionals=()
  while (( $# )); do
    case "$1" in
      -t)
        [[ $# -ge 2 && -n "$2" ]] || command_die "status clear: -t requires <window>"
        [[ -z "$seen_target" ]] || command_die "status clear: duplicate -t"
        [[ "$2" != -t && "$2" != --transient ]] || \
          command_die "status clear: -t requires <window>"
        win="$2"; seen_target=1; shift 2
        ;;
      -*) command_die "status clear: unknown option '$1'" ;;
      *) positionals+=("$1"); shift ;;
    esac
  done
  (( ${#positionals[@]} == 1 )) || command_die "status clear: need exactly <key>"
  key="${positionals[0]}"
  _signal_validate_key "status clear" "$key"
  _signal_resolve_window win "status clear" "$win"
  with_window_transaction "$win" status _signal_status_clear_unlocked "$win" "$key"
}

_signal_status_show_unlocked () {   # <window> [<key>]
  local win="$1" key="${2:-}" tuple level transient member members
  if [[ -n "$key" ]]; then
    tuple="$(coll_get_window "$win" status "$key")" || return
    printf '%s\n' "${tuple%%$'\t'*}"
    return 0
  fi
  members="$(coll_members_window "$win" status)" || return
  for member in $members; do
    tuple="$(coll_get_window "$win" status "$member")" || return
    IFS=$'\t' read -r level transient <<< "$tuple"
    command_show_row "$member" "$level${transient:+  (transient)}"
  done
}

signal_status_show () {   # [<key>] [-t <window>]
  local key="" win="" seen_target=""; local -a positionals=()
  while (( $# )); do
    case "$1" in
      -t)
        [[ $# -ge 2 && -n "$2" ]] || command_die "status show: -t requires <window>"
        [[ -z "$seen_target" ]] || command_die "status show: duplicate -t"
        [[ "$2" != -t && "$2" != --transient ]] || \
          command_die "status show: -t requires <window>"
        win="$2"; seen_target=1; shift 2
        ;;
      -*) command_die "status show: unknown option '$1'" ;;
      *) positionals+=("$1"); shift ;;
    esac
  done
  (( ${#positionals[@]} <= 1 )) || command_die "status show: too many arguments"
  key="${positionals[0]:-}"
  (( ${#positionals[@]} == 0 )) || _signal_validate_key "status show" "$key"
  _signal_resolve_window win "status show" "$win"
  with_window_transaction "$win" status _signal_status_show_unlocked "$win" "$key"
}

_signal_status_clear_transient_unlocked () {   # <window>
  local win="$1" changed="" key tuple transient members
  members="$(coll_members_window "$win" status)" || return
  for key in $members; do
    tuple="$(coll_get_window "$win" status "$key")" || return
    transient="${tuple#*$'\t'}"
    if [[ "$transient" == 1 ]]; then
      coll_unregister_window "$win" status "$key" || return
      changed=1
    fi
  done
  [[ -n "$changed" ]] || return 0
  _signal_project_and_redraw status "$win"
}

signal_clear_transient () {   # [-t <window>]
  local win="" seen_target=""
  while (( $# )); do
    case "$1" in
      -t)
        [[ $# -ge 2 && -n "$2" ]] || command_die "signal clear-transient: -t requires <window>"
        [[ -z "$seen_target" ]] || command_die "signal clear-transient: duplicate -t"
        [[ "$2" != -t ]] || command_die "signal clear-transient: -t requires <window>"
        win="$2"; seen_target=1; shift 2
        ;;
      *) command_die "signal clear-transient: unknown argument '$1'" ;;
    esac
  done
  _signal_resolve_window win "signal clear-transient" "$win"
  with_window_transaction "$win" status _signal_status_clear_transient_unlocked "$win"
}

#-----------------------------------------------------------------------------#
# Health/problem public boundaries
#-----------------------------------------------------------------------------#

signal_health_set () {   # [-t <window>] <key> <ok> | <key> <warn|fail> <message...>
  local win="" key level message
  if [[ "${1:-}" == -t ]]; then
    if (( $# < 3 )) || [[ -z "$2" ]]; then command_die "health set: -t requires <window>"; fi
    win="$2"; shift 2
  elif [[ "${1:-}" == -* ]]; then
    command_die "health set: unknown option '$1'"
  fi
  key="${1:-}"; level="${2:-}"
  shift $(( $# < 2 ? $# : 2 ))
  message="$*"
  _signal_validate_key "health set" "$key"
  _signal_validate_condition "health set" "$level" "$message"
  _signal_resolve_window win "health set" "$win"
  _signal_condition_store window "$win" health "$key" "$level" "$message"
}

signal_health_clear () {   # [-t <window>] <key>
  local win="" key
  if [[ "${1:-}" == -t ]]; then
    if (( $# < 3 )) || [[ -z "$2" ]]; then command_die "health clear: -t requires <window>"; fi
    win="$2"; shift 2
  elif [[ "${1:-}" == -* ]]; then
    command_die "health clear: unknown option '$1'"
  fi
  (( $# == 1 )) || command_die "health clear: need exactly <key>"
  key="$1"
  _signal_validate_key "health clear" "$key"
  _signal_resolve_window win "health clear" "$win"
  _signal_condition_store window "$win" health "$key" ok ""
}

signal_health_show () {   # [-t <window>] [<key>]
  local win="" key=""
  if [[ "${1:-}" == -t ]]; then
    if (( $# < 2 )) || [[ -z "$2" ]]; then command_die "health show: -t requires <window>"; fi
    win="$2"; shift 2
  elif [[ "${1:-}" == -* ]]; then
    command_die "health show: unknown option '$1'"
  fi
  (( $# <= 1 )) || command_die "health show: too many arguments"
  key="${1:-}"
  (( $# == 0 )) || _signal_validate_key "health show" "$key"
  _signal_resolve_window win "health show" "$win"
  _signal_condition_show window "$win" health "$key"
}

signal_problem_set () {   # <session> <key> <ok> | <session> <key> <warn|fail> <message...>
  local target="${1:-}" key="${2:-}" level="${3:-}" message session
  shift $(( $# < 3 ? $# : 3 ))
  message="$*"
  [[ -n "$target" ]] || command_die "problem set: need <session>"
  _signal_validate_key "problem set" "$key"
  _signal_validate_condition "problem set" "$level" "$message"
  _signal_resolve_session session "problem set" "$target"
  _signal_condition_store session "$session" problem "$key" "$level" "$message"
}

signal_problem_clear () {   # <session> <key>
  local target="${1:-}" key="${2:-}" session
  (( $# <= 2 )) || command_die "problem clear: too many arguments"
  [[ -n "$target" ]] || command_die "problem clear: need <session>"
  _signal_validate_key "problem clear" "$key"
  _signal_resolve_session session "problem clear" "$target"
  _signal_condition_store session "$session" problem "$key" ok ""
}

signal_problem_show () {   # [<session> [<key>]]
  local target="${1:-}" key="${2:-}" session sessions
  (( $# <= 2 )) || command_die "problem show: too many arguments"
  if (( $# > 0 )); then
    [[ -n "$target" ]] || command_die "problem show: session must not be empty"
    (( $# < 2 )) || _signal_validate_key "problem show" "$key"
    _signal_resolve_session session "problem show" "$target"
    _signal_condition_show session "$session" problem "$key"
    return
  fi
  sessions="$(list_sessions)" || return
  for session in $sessions; do
    _signal_condition_show session "$session" problem "" 1 || return
  done
}

# vim: ft=bash
