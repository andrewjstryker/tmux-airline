#!/usr/bin/env bash
#
# lifecycle.sh — session initialization, state, and transaction diagnostics.
#
# This module coordinates session bootstrap and the session-wide active/suspended
# state. Command grammar lives in airline.sh; attention signals live in signal.sh.

# shellcheck shell=bash

if ! declare -F _layout_show >/dev/null; then
  printf 'lifecycle.sh: load layout.sh (and its layers) first\n' >&2
  return 1 2>/dev/null || exit 1
fi

#-----------------------------------------------------------------------------#
# Lifecycle
#-----------------------------------------------------------------------------#

# Bootstrap (the `init` command). Publish the CLI path and, on first run, seed defaults
# behind a sentinel (without clobbering user config or runtime state on a reload); then
# render.
_init () {   # <session>
  local session="$1" rc=0
  # The CLI path is the ONE published (public) option — the bootstrap handle, since a
  # script can't call the CLI to discover where the CLI lives. Everything else about
  # airline's state is read through the CLI, never a private option. Airline binds no
  # keys — a user wires their own (e.g. `bind F12 run "#{@airline-cli} session toggle"`).
  pub_set "$AIRLINE_KEY_CLI" "$AIRLINE_DIR/airline.sh"
  # tmux loads plugins once per server, but airline owns session-local runtime
  # state. Seed each later session through one indexed global infrastructure hook.
  hook_set "after-new-session[90]" \
    "run-shell -b \"'$AIRLINE_DIR/airline.sh' session init -t '#{session_id}'\""

  # Register airline's own shipped config dirs on each loadable kind's search path.
  # (segment is not loadable — it's public options a layout sets, or the user sets.)
  catalog_register_builtin "$session" palette "$AIRLINE_DIR/layouts/palettes"
  catalog_register_builtin "$session" adapter "$AIRLINE_DIR/layouts/adapters"
  catalog_register_builtin "$session" layout  "$AIRLINE_DIR/layouts/definitions"
  catalog_register_builtin "$session" classifier "$AIRLINE_DIR/runners/classifiers"
  catalog_register_builtin "$session" filter "$AIRLINE_DIR/runners/filters"
  catalog_register_builtin "$session" probe "$AIRLINE_DIR/runners/probes"
  catalog_register_builtin "$session" runner  "$AIRLINE_DIR/runners/definitions"

  with_session_transaction "$session" config _init_unlocked "$session" || rc=$?
  _report_config_result "$session" "$rc" init
  return "$rc"
}

_init_unlocked () {   # <session>
  local session="$1" layout seeded=""
  if [[ -z "$(cfg_get_session "$session" inner-bg)" ]]; then
    _palette_select_unlocked "$session" default || return $?
    seeded=1
  fi
  if [[ -n "$seeded" || -z "$(prv_get_session "$session" "$AIRLINE_KEY_DEFAULTS")" ]]; then
    layout="$(prv_get_session "$session" layout)"
    [[ -n "$layout" ]] || layout=adaptive
    _apply_layout_unlocked "$session" "$layout" || return $?
  fi
  _apply_public_unlocked "$session" || return $?
  _reapply_adapters_unlocked "$session" || return $?
  prv_set_session "$session" "$AIRLINE_KEY_DEFAULTS" 1
  render "$session" || true
}

# Copy explicitly present global public values over the private snapshot. A manual
# palette or segment write clears the corresponding named provenance; absent globals
# leave the committed value untouched.
_apply_unlocked () {   # <session>
  local session="$1"
  _apply_public_unlocked "$session" || return $?
  _reapply_adapters_unlocked "$session" || return $?
  render "$session" || true
}

_apply () {   # <session>
  local session="$1" rc=0
  with_session_transaction "$session" config _apply_unlocked "$session" || rc=$?
  _report_config_result "$session" "$rc" apply
  return "$rc"
}

_report_config_result () {   # <session> <rc> <operation>
  local session="$1" rc="$2" operation="$3" message
  case "$rc" in
    0)
      signal_problem_report "$session" airline-palette ok ""
      [[ "$operation" != init ]] || signal_problem_report "$session" airline-layout ok ""
      ;;
    "$AIRLINE_CONFIG_PALETTE_FAILURE")
      signal_problem_report "$session" airline-palette fail "$operation could not resolve a complete palette"
      ;;
    *)
      message="$(prv_get_session "$session" "$AIRLINE_CONFIG_ERROR")"
      [[ -n "$message" ]] || message="$operation could not apply a layout"
      signal_problem_report "$session" airline-layout fail "$message"
      ;;
  esac
}

# The top-level `show` command: the active configuration. The non-noun globals first
# (the bootstrap handle, lifecycle state, and the search paths), then each CONFIG noun's
# own bare `show` — the noun reports its own active state, so nothing is printed twice (a
# palette/layout name shows once, inside its section). The dynamic per-window nouns
# (status/health/problem) are NOT global config, so they're excluded — inspect them
# through their own `show` commands. Mirrors exactly what each `<noun> show` prints bare.
_show_config () {   # <session>
  local session="$1"
  command_show_row cli   "$(pub_get cli)"              # the one public (bootstrap) handle
  command_show_row state "$(_state_word "$session")"  # lifecycle (active | suspended)
  printf '\npaths:\n'                           # catalog resolution, priority order
  local k
  for k in palette adapter layout classifier filter probe runner; do
    command_show_row "$k" "$(catalog_paths "$session" "$k")"
  done
  printf '\npalette:\n'; _palette_show "$session"
  printf '\nsegment:\n'; _static_show "$session" "segment-" _segment_slot_valid AIRLINE_SEGMENT_SLOTS
  printf '\nadapter:\n'; _adapter_show "$session"
  printf '\nlayout:\n';  _layout_show "$session"
}

# The active/suspended state. `suspend` mutes the palette (the derived flat look, via
# _palette_load) and traps the prefix so keys pass through — the nested-session signal
# "this tmux is dormant." `resume` restores. The flat/vibrant colour is derived, not a
# second palette. State is private; read it through `session show`, not the option.
_state_word () {   # <session>
  [[ "$(prv_get_session "$1" "$AIRLINE_KEY_SUSPENDED")" == 1 ]] && echo suspended || echo active
}

_state_set () {   # <session> <1=suspended|0=active>
  local session="$1" value="$2"
  prv_set_session "$session" "$AIRLINE_KEY_SUSPENDED" "$value"
  if [[ "$value" == 1 ]]; then
    opt_set_session "$session" prefix None
    opt_set_session "$session" key-table off
  else
    opt_unset_session "$session" prefix
    opt_unset_session "$session" key-table
  fi
  render "$session" || true
}

# Transaction diagnostics. tmux.sh owns marker discovery, liveness checks, and
# recovery; lifecycle owns only command validation and user-facing errors.
_lock_show () {
  (( $# == 0 )) || command_die "lock show: takes no arguments"
  transaction_list
}

_lock_clear () {   # <session|window> <target> <namespace>
  local scope="${1:-}" target="${2:-}" namespace="${3:-}" rc=0
  (( $# == 3 )) || command_die "lock clear: need <session|window> <target> <namespace>"
  transaction_clear "$scope" "$target" "$namespace" || rc=$?
  case "$rc" in
    0) ;;
    2) command_die "lock clear: invalid scope, target, namespace, or marker" ;;
    3) command_die "lock clear: no such outstanding transaction" ;;
    4) command_die "lock clear: transaction owner is still active" ;;
    *) command_die "lock clear: recovery failed" ;;
  esac
}

# CLI delegation targets. These functions are the behavior boundary behind the
# grammar in airline.sh; they are internal implementation, not a second user API.
lifecycle_init () {   # [-t <session>]
  local target="" session
  while (( $# )); do
    case "$1" in
      -t)
        [[ $# -ge 2 && -n "$2" ]] || command_die "session init: -t requires <session>"
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
  _init "$session"
}
lifecycle_apply () { _apply "$(command_current_session)"; }
lifecycle_show () {
  local field="${1:-}" session
  (( $# <= 1 )) || command_die "session show: too many arguments"
  [[ -z "$field" || "$field" == state ]] || command_die "session show: unknown field '$field'"
  session="$(command_current_session)"
  if [[ "$field" == state ]]; then
    _state_word "$session"
    return
  fi
  with_session_transaction "$session" config _show_config "$session"
}

lifecycle_session_suspend () { _state_set "$(command_current_session)" 1; }
lifecycle_session_resume () { _state_set "$(command_current_session)" 0; }
lifecycle_session_toggle () {
  local session
  session="$(command_current_session)"
  if [[ "$(_state_word "$session")" == suspended ]]; then
    _state_set "$session" 0
  else
    _state_set "$session" 1
  fi
}
lifecycle_lock_show () { _lock_show "$@"; }
lifecycle_lock_clear () { _lock_clear "$@"; }
# vim: ft=bash
