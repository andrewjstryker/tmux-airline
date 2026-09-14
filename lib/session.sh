#!/usr/bin/env bash
#
# session.sh — session bootstrap, configuration coordination, and state.

# shellcheck shell=bash

_session_bootstrap () {   # <session>
  local session="$1"
  pub_set "$AIRLINE_KEY_CLI" "$AIRLINE_DIR/airline.sh"
  hook_set "after-new-session[90]" \
    "run-shell -b \"'$AIRLINE_DIR/airline.sh' session init -t '#{session_id}'\""
  hook_set_airline_window_styles "${AIRLINE_NATIVE_WINDOW_OPTIONS[@]}"
  signal_health_install_hooks
  signal_problem_install_hooks
  # Remove the pre-ledger session projection so it cannot shadow the global
  # badge after upgrading an already initialized tmux server.
  prv_unset_session "$session" "$AIRLINE_KEY_PROBLEM"

  layout_initialize "$session"
}

_session_state_word () {   # <session>
  [[ "$(prv_get_session "$1" "$AIRLINE_KEY_SUSPENDED")" == 1 ]] && \
    printf 'suspended\n' || printf 'active\n'
}

_session_state_set_unlocked () {   # <session> <1=suspended|0=active>
  local session="$1" value="$2"
  prv_set_session "$session" "$AIRLINE_KEY_SUSPENDED" "$value"
  if [[ "$value" == 1 ]]; then
    opt_set_session "$session" prefix None
    opt_set_session "$session" key-table off
  else
    opt_unset_session "$session" prefix
    opt_unset_session "$session" key-table
  fi
  render "$session"
}

_session_state_set () {   # <session> <1=suspended|0=active>
  with_session_transaction "$1" config _session_state_set_unlocked "$@"
}

_session_configuration_show_unlocked () {   # <session>
  local session="$1" kind
  command_show_row cli "$(pub_get cli)"
  command_show_row state "$(_session_state_word "$session")"
  printf '\npaths:\n'
  for kind in palette widget layout classifier filter probe runner; do
    command_show_row "$kind" "$(catalog_paths "$session" "$kind")"
  done
  layout_configuration_show "$session"
}

session_init () {   # [-t <session-target>]
  local target="" session
  while (( $# )); do
    case "$1" in
      -t)
        [[ $# -ge 2 && -n "$2" ]] || command_die "session init: -t requires <session-target>"
        [[ -z "$target" ]] || command_die "session init: duplicate -t"
        target="$2"
        shift 2
        ;;
      *) command_die "session init: unknown argument '$1'" ;;
    esac
  done
  if [[ -n "$target" ]]; then
    session="$(resolve_session_target "$target")"
    [[ -n "$session" ]] || command_die "session init: cannot resolve session '$target'"
  else
    session="$(command_current_session)"
  fi
  _session_bootstrap "$session" || return
  _session_config || return
}

_session_config () {   # [<file>]
  local file="${1:-${AIRLINE_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/airline/config}}"
  (( $# <= 1 )) || command_die 'session config: takes at most one <file>'
  [[ -f "$file" ]] || return 0
  [[ -r "$file" ]] || command_die "session config: cannot read '$file'"
  # The config file is a trusted batch of the existing CLI commands. Keep the
  # command name available even when the installable PATH shim is not installed.
  airline() { "$AIRLINE_DIR/airline.sh" "$@"; }
  # shellcheck disable=SC1090
  source "$file"
}

session_apply () {
  (( $# == 0 )) || command_die "session apply: takes no arguments"
  layout_apply "$(command_current_session)"
}

session_show () {   # [state]
  local field="${1:-}" session
  (( $# <= 1 )) || command_die "session show: too many arguments"
  [[ -z "$field" || "$field" == state ]] || command_die "session show: unknown field '$field'"
  session="$(command_current_session)"
  if [[ "$field" == state ]]; then
    _session_state_word "$session"
    return
  fi
  with_session_transaction "$session" config _session_configuration_show_unlocked "$session"
}

session_suspend () {
  (( $# == 0 )) || command_die "session suspend: takes no arguments"
  _session_state_set "$(command_current_session)" 1
}
session_resume () {
  (( $# == 0 )) || command_die "session resume: takes no arguments"
  _session_state_set "$(command_current_session)" 0
}
session_toggle () {
  local session
  (( $# == 0 )) || command_die "session toggle: takes no arguments"
  session="$(command_current_session)"
  if [[ "$(_session_state_word "$session")" == suspended ]]; then
    _session_state_set "$session" 0
  else
    _session_state_set "$session" 1
  fi
}

# vim: ft=bash
