#!/usr/bin/env bash
#
# lifecycle.sh — shared command lifecycle, signals, state, and diagnostics.
#
# This internal module establishes command context, validates lifecycle and signal
# input, and orchestrates the lower layers. Command grammar lives in airline.sh.
#
# The verb grammar (in `airline.sh`) splits on the state model implemented here and
# in layout.sh and runner.sh.
# Dynamic nouns (status, health, problem) are live and scriptable: set + re-project a
# badge + redraw. Static config nouns (palette, segment) are read-only at the CLI;
# runner adds process-lifecycle orchestration over those existing signals. Users
# provide global input through `.tmux.conf`; airline copies it into a private,
# session-owned configuration snapshot. Palette/layout selections replace their
# respective axis in that snapshot while ephemeral runner updates remain live.

# shellcheck shell=bash

if ! declare -F _layout_show >/dev/null || ! declare -F _runner_invoke >/dev/null; then
  printf 'lifecycle.sh: load runner.sh and layout.sh (and their layers) first\n' >&2
  return 1 2>/dev/null || exit 1
fi

die () { printf 'airline: %s\n' "$*" >&2; exit 2; }

# CLI delegates resolve their execution context through tmux. An inherited
# AIRLINE_SESSION is deliberately not consulted: that variable is output supplied to
# a running layout, not a hidden user-facing target mechanism.
_require_current_session () {
  local session
  session="$(current_session)"
  [[ -n "$session" ]] || die "cannot resolve current session"
  printf '%s' "$session"
}

# Store one session problem and refresh its aggregate projection. This is the shared
# write path for the public command and airline's own managed components.
# `ok` is a recovery event, not retained state. Return 0 only when the visible badge
# changed, allowing the public path to skip redundant redraws.
_problem_store_unlocked () {   # <session> <key> <ok|warn|fail> [<message>]
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
  if [[ -n "$changed" ]] && problem_project "$session"; then projected=0; fi
  return "$projected"
}

_problem_store () {   # <session> <key> <ok|warn|fail> [<message>]
  with_session_transaction "$1" problem _problem_store_unlocked "$@"
}

# One "label   value" row — the single home for the `show` column width, so every
# noun's show and the top-level summary align identically.
_show_row () { printf '%-12s %s\n' "$1" "$2"; }

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
  _path_register_self "$session" palette "$AIRLINE_DIR/layouts/palettes"
  _path_register_self "$session" adapter "$AIRLINE_DIR/layouts/adapters"
  _path_register_self "$session" layout  "$AIRLINE_DIR/layouts/definitions"
  _path_register_self "$session" classifier "$AIRLINE_DIR/runners/classifiers"
  _path_register_self "$session" filter "$AIRLINE_DIR/runners/filters"
  _path_register_self "$session" probe "$AIRLINE_DIR/runners/probes"
  _path_register_self "$session" runner  "$AIRLINE_DIR/runners/definitions"

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
      _config_problem "$session" airline-palette ok ""
      [[ "$operation" != init ]] || _config_problem "$session" airline-layout ok ""
      ;;
    "$AIRLINE_CONFIG_PALETTE_FAILURE")
      _config_problem "$session" airline-palette fail "$operation could not resolve a complete palette"
      ;;
    *)
      message="$(prv_get_session "$session" "$AIRLINE_CONFIG_ERROR")"
      [[ -n "$message" ]] || message="$operation could not apply a layout"
      _config_problem "$session" airline-layout fail "$message"
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
  _show_row cli   "$(pub_get cli)"              # the one public (bootstrap) handle
  _show_row state "$(_state_word "$session")"  # lifecycle (active | suspended)
  printf '\npaths:\n'                           # catalog resolution, priority order
  local k
  for k in palette adapter layout classifier filter probe runner; do
    _show_row "$k" "$(coll_members_session "$session" "$(_path_ns "$k")")"
  done
  printf '\npalette:\n'; _palette_show "$session"
  printf '\nsegment:\n'; _static_show "$session" "segment-" _segment_slot_valid AIRLINE_SEGMENT_SLOTS
  printf '\nadapter:\n'; _adapter_show "$session"
  printf '\nlayout:\n';  _layout_show "$session"
}

#-----------------------------------------------------------------------------#
# Search paths — registered catalogs and the `use` mechanism
#-----------------------------------------------------------------------------#
# Each config kind (palette, layout/segment, adapter) has an ordered search PATH of
# directories, stored via collections.sh: the kind's registry list IS the path, in
# priority order. `<kind> use <name>` resolves <name> to the FIRST matching file on
# that path (or a literal path when it contains '/'), sources it, and renders.
# airline registers its own shipped dir per kind at init. (`register` to add more —
# piece 2.) Limitation: the path lives in a space-delimited registry, so a directory
# containing a space is unsupported — config/plugin dirs don't have spaces.

_path_ns () { printf 'path-%s' "$1"; }        # kind → collection ns

# Register airline's own shipped dir for a kind (idempotent; skips if absent).
_path_register_self () {   # <session> <kind> <dir>
  local session="$1" kind="$2" dir="$3"
  [[ -d "$dir" ]] && coll_register_session "$session" "$(_path_ns "$kind")" "$dir"
}

# Resolve a bare <name> to the first hit walking the kind's path. Names are simple
# (no '/'): `use` only reaches BLESSED locations — `register` a dir to add one; there
# is no literal-path escape hatch (we don't load/execute from arbitrary paths).
# Echoes the file path, empty when unresolved.
_path_resolve () {   # <session> <kind> <name>
  local session="$1" kind="$2" name="$3" dir
  [[ "$name" == */* ]] && return          # not a bare name → unresolvable here
  for dir in $(coll_members_session "$session" "$(_path_ns "$kind")"); do
    [[ -f "$dir/$name" ]] && { printf '%s' "$dir/$name"; return; }
  done
}

# List every bare name resolvable on the kind's path — the catalog selection surface.
# One name per line, deduped in path order (a shadowing user dir collapses with the
# shipped name it overrides). The read-side counterpart to _path_resolve; the shared
# core of every noun's `list` verb (palette / adapter / layout).
_path_list () {   # <session> <kind>
  local session="$1" kind="$2" dir f name seen=" "
  for dir in $(coll_members_session "$session" "$(_path_ns "$kind")"); do
    [[ -d "$dir" ]] || continue
    for f in "$dir"/*; do
      [[ -f "$f" ]] || continue
      name="${f##*/}"
      case "$seen" in *" $name "*) continue ;; esac
      seen+="$name "; printf '%s\n' "$name"
    done
  done
}

# Prepend a dir to a kind's search path — the one trust boundary: registering a dir
# blesses it, and only then can `use` reach names inside it.
_register () {   # <session> <kind> <dir>
  local session="$1" kind="$2" dir="${3:-}"
  [[ -n "$dir" ]] || die "$kind register: need <dir>"
  [[ -d "$dir" ]] || die "$kind register: no such directory: $dir"
  coll_prepend_session "$session" "$(_path_ns "$kind")" "$dir"
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

#-----------------------------------------------------------------------------#
# Transient (consume-on-view)
#-----------------------------------------------------------------------------#

_ensure_transient_hook () {
  opt_set_global focus-events on
  hook_set "pane-focus-out[90]" \
    "run-shell -b \"'$AIRLINE_DIR/airline.sh' signal clear-transient -t #{window_id}\""
}

# Drop one namespace's transient contributors and re-project its badge. The caller
# runs this inside that window collection's transaction.
_clear_transient_namespace_unlocked () {   # <window> <status|health>
  local win="$1" ns="$2" changed="" key f1 f2
  for key in $(coll_members_window "$win" "$ns"); do
    IFS=$'\t' read -r f1 f2 <<< "$(coll_get_window "$win" "$ns" "$key")"
    [[ "$f2" == 1 ]] && { coll_unregister_window "$win" "$ns" "$key"; changed=1; }
  done
  [[ -n "$changed" ]] || return 1
  "${ns}_project" "$win"
}

# Consume-on-view is a public signal operation. Status and health use separate locks
# in a fixed order; each collection mutation and projection is one window transaction.
_clear_transient () {   # [-t <window>]
  local win="" ns changed=""
  while (( $# )); do
    case "$1" in
      -t)
        [[ $# -ge 2 && -n "$2" ]] || die "signal clear-transient: -t requires <window>"
        [[ -z "$win" ]] || die "signal clear-transient: duplicate -t"
        win="$2"
        shift 2
        ;;
      *) die "signal clear-transient: unknown argument '$1'" ;;
    esac
  done
  [[ -n "$win" ]] || win="$(current_window)"
  win="$(resolve_window "$win")"
  [[ -n "$win" ]] || die "signal clear-transient: cannot resolve window"
  for ns in status health; do
    with_window_transaction "$win" "$ns" _clear_transient_namespace_unlocked "$win" "$ns" && changed=1
  done
  [[ -n "$changed" ]] && redraw
  return 0
}

#-----------------------------------------------------------------------------#
# Dynamic nouns — status & health (live: write + re-project a badge + redraw)
#-----------------------------------------------------------------------------#

_signal_set_unlocked () {   # <ns> <clear-value|""> <key> <value> <transient> <window>
  local ns="$1" clear_value="$2" key="$3" value="$4" transient="$5" win="$6"
  if [[ -n "$clear_value" && "$value" == "$clear_value" ]]; then
    coll_unregister_window "$win" "$ns" "$key"
  else
    coll_set_window "$win" "$ns" "$key" "$value" "$transient"
  fi
  "${ns}_project" "$win"
}

_signal_set () {   # <ns> <validator> <clear-value|""> <key> <value> [--transient] [-t <win>]
  local ns="$1" valid="$2" clear_value="$3"; shift 3
  local key="" value="" transient="" win="" ; local -a pos=()
  while (( $# )); do
    case "$1" in
      --transient) transient=1; shift ;;
      -t)
        [[ $# -ge 2 && -n "$2" ]] || die "$ns set: -t requires <window>"
        win="$2"
        shift 2
        ;;
      *)           pos+=("$1"); shift ;;
    esac
  done
  key="${pos[0]:-}"; value="${pos[1]:-}"
  [[ -n "$key" ]] || die "$ns set: need <key>"
  "$valid" "$value" || die "$ns set: invalid value '$value'"
  [[ -n "$win" ]] || win="$(current_window)"
  win="$(resolve_window "$win")"
  with_window_transaction "$win" "$ns" _signal_set_unlocked \
    "$ns" "$clear_value" "$key" "$value" "$transient" "$win" && redraw
  [[ -n "$transient" ]] && _ensure_transient_hook
  return 0
}

_signal_clear_unlocked () {   # <ns> <key> <window>
  local ns="$1" key="$2" win="$3"
  coll_unregister_window "$win" "$ns" "$key"
  "${ns}_project" "$win"
}

_signal_clear () {   # <ns> <key> [-t <win>]
  local ns="$1"; shift
  local key="" win=""
  while (( $# )); do
    case "$1" in
      -t)
        [[ $# -ge 2 && -n "$2" ]] || die "$ns clear: -t requires <window>"
        win="$2"
        shift 2
        ;;
      *) key="$1"; shift ;;
    esac
  done
  [[ -n "$key" ]] || die "$ns clear: need <key>"
  [[ -n "$win" ]] || win="$(current_window)"
  win="$(resolve_window "$win")"
  with_window_transaction "$win" "$ns" _signal_clear_unlocked "$ns" "$key" "$win" && redraw
  return 0
}

_signal_show_unlocked () {   # <ns> <window> [<key>]
  local ns="$1" win="$2" key="${3:-}" f1 f2 k
  if [[ -n "$key" ]]; then
    IFS=$'\t' read -r f1 _ <<< "$(coll_get_window "$win" "$ns" "$key")"
    printf '%s\n' "$f1"
    return 0
  fi
  for k in $(coll_members_window "$win" "$ns"); do
    IFS=$'\t' read -r f1 f2 <<< "$(coll_get_window "$win" "$ns" "$k")"
    _show_row "$k" "$f1${f2:+  (transient)}"
  done
}

_signal_show () {   # <ns> [<key>] [-t <win>]
  local ns="$1"; shift
  local key="" win=""
  while (( $# )); do
    case "$1" in
      -t)
        [[ $# -ge 2 && -n "$2" ]] || die "$ns show: -t requires <window>"
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

#-----------------------------------------------------------------------------#
# Session problems — cooperating widgets report failures encountered by one
# session's configured components. Mutation requires that session as input and
# never infers or writes another session. A bare show is intentionally server-wide.
#-----------------------------------------------------------------------------#

_problem_session () {   # <verb> <session-target>
  local verb="$1" target="${2:-}" session
  [[ -n "$target" ]] || die "problem $verb: need <session>"
  session="$(resolve_session_target "$target")"
  [[ -n "$session" ]] || die "problem $verb: cannot resolve session '$target'"
  printf '%s' "$session"
}

_problem_set () {   # <session> <key> <level> [<message...>]
  local target="${1:-}" key="${2:-}" level="${3:-}" message session
  shift $(( $# < 3 ? $# : 3 ))
  message="$*"
  session="$(_problem_session set "$target")"
  [[ -n "$key" ]] || die "problem set: need <key>"
  [[ "$key" != *[[:space:]]* ]] || die "problem set: key must not contain whitespace"
  _condition_level_valid "$level" || die "problem set: invalid level '$level'"
  if [[ "$level" != ok ]]; then
    [[ -n "$message" ]] || die "problem set: need <message>"
    [[ "$message" != *$'\t'* ]] || die "problem set: message must not contain a tab"
  fi
  _problem_store "$session" "$key" "$level" "$message" && redraw
  return 0
}

_problem_clear () {   # <session> <key>
  local target="${1:-}" key="${2:-}" session
  (( $# <= 2 )) || die "problem clear: too many arguments"
  session="$(_problem_session clear "$target")"
  [[ -n "$key" ]] || die "problem clear: need <key>"
  _problem_store "$session" "$key" ok "" && redraw
  return 0
}

_problem_show_session_unlocked () {   # <session> [<key>] [<grouped=1>]
  local session="$1" key="${2:-}" grouped="${3:-}" tuple level message k members
  if [[ -n "$key" ]]; then
    coll_get_session "$session" problem "$key"
    return 0
  fi
  members="$(coll_members_session "$session" problem)"
  if [[ -n "$grouped" && -n "$members" ]]; then printf '%s:\n' "$session"; fi
  for k in $members; do
    tuple="$(coll_get_session "$session" problem "$k")"
    IFS=$'\t' read -r level message <<< "$tuple"
    _show_row "${grouped:+  }$k" "$level${message:+  $message}"
  done
}

_problem_show_session () {   # <session> [<key>] [<grouped=1>]
  with_session_transaction "$1" problem _problem_show_session_unlocked "$@"
}

_problem_show () {   # [<session> [<key>]]; bare = every session with problems
  local target="${1:-}" key="${2:-}" session
  (( $# <= 2 )) || die "problem show: too many arguments"
  if [[ -n "$target" ]]; then
    session="$(_problem_session show "$target")"
    _problem_show_session "$session" "$key"
    return 0
  fi
  for session in $(list_sessions); do
    _problem_show_session "$session" "" 1
  done
}

# Transaction diagnostics. tmux.sh owns marker discovery, liveness checks, and
# recovery; lifecycle owns only command validation and user-facing errors.
_lock_show () {
  (( $# == 0 )) || die "lock show: takes no arguments"
  transaction_list
}

_lock_clear () {   # <session|window> <target> <namespace>
  local scope="${1:-}" target="${2:-}" namespace="${3:-}" rc=0
  (( $# == 3 )) || die "lock clear: need <session|window> <target> <namespace>"
  transaction_clear "$scope" "$target" "$namespace" || rc=$?
  case "$rc" in
    0) ;;
    2) die "lock clear: invalid scope, target, namespace, or marker" ;;
    3) die "lock clear: no such outstanding transaction" ;;
    4) die "lock clear: transaction owner is still active" ;;
    *) die "lock clear: recovery failed" ;;
  esac
}

# CLI delegation targets. These functions are the behavior boundary behind the
# grammar in airline.sh; they are internal implementation, not a second user API.
lifecycle_init () {   # [-t <session>]
  local target="" session
  while (( $# )); do
    case "$1" in
      -t)
        [[ $# -ge 2 && -n "$2" ]] || die "session init: -t requires <session>"
        [[ -z "$target" ]] || die "session init: duplicate -t"
        target="$2"
        shift 2
        ;;
      *) die "session init: unknown argument '$1'" ;;
    esac
  done
  if [[ -n "$target" ]]; then
    session="$(resolve_session_target "$target")"
    [[ -n "$session" ]] || die "session init: cannot resolve session '$target'"
  else
    session="$(_require_current_session)"
  fi
  _init "$session"
}
lifecycle_apply () { _apply "$(_require_current_session)"; }
lifecycle_show () {
  local field="${1:-}" session
  (( $# <= 1 )) || die "session show: too many arguments"
  [[ -z "$field" || "$field" == state ]] || die "session show: unknown field '$field'"
  session="$(_require_current_session)"
  if [[ "$field" == state ]]; then
    _state_word "$session"
    return
  fi
  with_session_transaction "$session" config _show_config "$session"
}

lifecycle_session_suspend () { _state_set "$(_require_current_session)" 1; }
lifecycle_session_resume () { _state_set "$(_require_current_session)" 0; }
lifecycle_session_toggle () {
  local session
  session="$(_require_current_session)"
  if [[ "$(_state_word "$session")" == suspended ]]; then
    _state_set "$session" 0
  else
    _state_set "$session" 1
  fi
}
lifecycle_signal_clear_transient () { _clear_transient "$@"; }
lifecycle_status_set () { _signal_set status _status_level_valid "" "$@"; }
lifecycle_status_clear () { _signal_clear status "$@"; }
lifecycle_status_show () { _signal_show status "$@"; }
lifecycle_health_set () { _signal_set health _condition_level_valid ok "$@"; }
lifecycle_health_clear () { _signal_clear health "$@"; }
lifecycle_health_show () { _signal_show health "$@"; }
lifecycle_problem_set () { _problem_set "$@"; }
lifecycle_problem_clear () { _problem_clear "$@"; }
lifecycle_problem_show () { _problem_show "$@"; }
lifecycle_lock_show () { _lock_show "$@"; }
lifecycle_lock_clear () { _lock_clear "$@"; }
# vim: ft=bash
