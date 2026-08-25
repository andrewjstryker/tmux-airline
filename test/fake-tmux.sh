#!/usr/bin/env bash
#
# fake-tmux.sh — an in-memory stand-in for the tmux binary, for unit tests.
#
# tmux.sh is the ONE place airline talks to tmux (Invariant A), and it bottoms out
# in three private cores (_opt_show/_opt_write/_opt_clear) plus a few standalone
# verbs. This file sources the REAL tmux.sh — so every composed function above the
# leaves (opt_setif_*, opt_getor_*, the scope wrappers, and all of collections.sh /
# render.sh) runs unmodified and under test — then replaces only those leaves with
# bash associative arrays. No tmux process, no socket: a layer test that used to
# spin up and tear down a server now runs in-process.
#
# The fake reproduces only the leaf STORE semantics — get is empty when unset, set
# overwrites, unset removes, global/session/window scopes are independent, values
# with spaces survive. Those exact semantics are pinned against the real binary in
# tmux.bats; that suite is the contract this file must honour. Anything richer
# (format #{?…} evaluation, redraw side effects) is deliberately NOT modelled —
# the layer tests assert on the composed format STRINGS, never on tmux evaluating
# them, so a faithful store is all they need.
#
# Load order matches production: source this instead of src/tmux.sh, then load
# src/collections.sh and src/render.sh on top. The fake loaders do exactly that.

# shellcheck shell=bash

# Bring in the real mechanical layer (definitions only — sourcing tmux.sh makes no
# tmux call), then shadow its leaves below. Everything else stays the production code.
source "${PROJECT_ROOT:?fake-tmux.sh: PROJECT_ROOT must be set}/src/tmux.sh"

#-----------------------------------------------------------------------------#
# In-memory backing store
#-----------------------------------------------------------------------------#
# One option table, keyed by scope. A unit-separator (\037) joins the key parts so
# it can never collide with an option name or window id.
declare -gA _FAKE_OPT=()
declare -gA _FAKE_HOOK=()
declare -gA _FAKE_BIND=()
declare -g  _FAKE_WIN='@1'      # what current_window reports (override per test)
declare -g  _FAKE_SESSION='s1'  # what current_session reports (override per test)
declare -gi _FAKE_REDRAWS=0     # redraw call count (assertable if a test cares)

# Reset all fake state. Each test re-sources this file (via its loader), which
# re-declares the arrays empty, so this is only needed to clear mid-test.
fake_tmux_reset () {
  _FAKE_OPT=(); _FAKE_HOOK=(); _FAKE_BIND=()
  _FAKE_WIN='@1'; _FAKE_SESSION='s1'; _FAKE_REDRAWS=0
  _AIRLINE_TRANSACTION_CHANNEL=""
}

# Storage key from the scope tokens the cores receive:
#   global:  -g <name>                 → g␟<name>
#   session: -t <session> <name>        → s␟<session>␟<name>
#   window:  -w -t <win> <name>        → w␟<win>␟<name>
# (A trailing value arg, if any, is ignored here — only scope+name make the key.)
_fake_key () {
  if [[ "$1" == -g ]]; then printf 'g\037%s' "$2"
  elif [[ "$1" == -w ]]; then printf 'w\037%s\037%s' "$3" "$4"
  else                           printf 's\037%s\037%s' "$2" "$3"; fi
}

#-----------------------------------------------------------------------------#
# Leaf overrides — the three private cores tmux.sh bottoms out in.
#-----------------------------------------------------------------------------#
_opt_show  () {   # <scope…> <name>; raw scope only (policy handles inheritance)
  local key
  key="$(_fake_key "$@")"
  if [[ -v "_FAKE_OPT[$key]" ]]; then
    printf '%s' "${_FAKE_OPT[$key]}"
  fi
}
_opt_list () {
  local key name
  key="$(_fake_key "$@")"; name="${*: -1}"
  [[ -v "_FAKE_OPT[$key]" ]] && printf '%s %q' "$name" "${_FAKE_OPT[$key]}"
}
_opt_write () { _FAKE_OPT["$(_fake_key "$@")"]="${*: -1}"; }         # <scope…> <name> <value>
_opt_clear () { unset "_FAKE_OPT[$(_fake_key "$@")]"; }

#-----------------------------------------------------------------------------#
# Standalone verb overrides
#-----------------------------------------------------------------------------#
redraw         () { (( _FAKE_REDRAWS++ )) || true; }
current_window () { printf '%s' "$_FAKE_WIN"; }
resolve_window () { printf '%s' "$1"; }
current_pane () { printf '%%1'; }
current_path () { printf '/tmp'; }
current_session () { printf '%s' "$_FAKE_SESSION"; }
resolve_session () { printf '%s' "$1"; }
resolve_session_target () { printf '%s' "$1"; }
list_sessions () { printf '%s\n' "$_FAKE_SESSION"; }
hook_set       () { _FAKE_HOOK["$1"]="$2"; }
hook_unset     () { unset "_FAKE_HOOK[$1]"; }
key_bind       () { _FAKE_BIND["$1 $2"]="$3"; }
key_unbind     () { unset "_FAKE_BIND[$1 $2]"; }
runner_open_pane () { printf '%%2'; }
runner_open_window () { printf '%%2'; }
runner_retain_pane () { :; }

# Behavior tests assume tmux.sh's transaction contract. Run callbacks directly so
# the in-memory option store remains in this shell; real locking, traps, markers,
# and scheduling are exercised exhaustively by tmux.bats against a real server.
with_session_transaction () { local callback="$3"; shift 3; "$callback" "$@"; }
with_window_transaction  () { local callback="$3"; shift 3; "$callback" "$@"; }

# Load a tmux config file (palette / segments). Only the lines airline ships are
# modelled: `set`/`set-option` with optional `-g`, then NAME VALUE. Values may be
# quoted (e.g. "%Y-%m-%d %H:%M") or contain '#' (format strings like #S), so the
# line is re-split with the shell — these are airline's own trusted data files.
# Blank lines and whole-line comments (first non-space char '#') are skipped; an
# inline '#' is never treated as a comment (it is part of a format value).
source_file () {   # <file>
  local line trimmed name val; local -a t
  while IFS= read -r line || [[ -n "$line" ]]; do
    trimmed="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$trimmed" || "${trimmed:0:1}" == '#' ]] && continue
    eval "t=($trimmed)" 2>/dev/null || continue
    local i=1
    [[ "${t[1]:-}" == -g ]] && i=2
    name="${t[$i]:-}"; val="${t[$((i+1))]:-}"
    [[ -n "$name" ]] && _FAKE_OPT["g\037$name"]="$val"
  done < "$1"
}

# Session-targeted palette source. Palette commands omit -g, so their public
# options land in the selected session while ordinary source_file retains the
# global configuration-file behavior above.
source_file_session () {   # <session> <file>
  local session="$1" file="$2" line trimmed name val; local -a t
  while IFS= read -r line || [[ -n "$line" ]]; do
    trimmed="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$trimmed" || "${trimmed:0:1}" == '#' || "$trimmed" == *=* ]] && continue
    eval "t=($trimmed)" 2>/dev/null || continue
    local i=1
    [[ "${t[1]:-}" == -g ]] && i=2
    name="${t[$i]:-}"; val="${t[$((i+1))]:-}"
    [[ -n "$name" ]] && _FAKE_OPT["$(_fake_key -t "$session" "$name")"]="$val"
  done < "$file"
}

# vim: ft=bash
