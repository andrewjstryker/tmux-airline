#!/usr/bin/env bash
#
# tmux.sh — the mechanical layer: the ONE place that talks to the tmux binary.
#
# Everything airline reads or writes in tmux goes through these functions; the
# layers above call them and never invoke `tmux` directly — a build-time lint
# enforces that, so this file is the sole entry on its allowlist.
#
# Conventions:
#   * No flags. Scope and behaviour are encoded in the function NAME
#     (opt_set_window, not opt_set -w); arguments are fixed and positional.
#   * Getters echo to stdout (empty when unset); predicates use exit status;
#     mutators are silent.
#   * A few private cores (_opt_*) make the actual tmux call; the public
#     functions are thin wrappers that bake in scope.
#   * A function exists only for a tmux subcommand that is NOT an option. Built-in
#     options go through the opt_* accessor matching their native ownership.
#
# Modern Bash (4.3+) is assumed.

# shellcheck shell=bash

#-----------------------------------------------------------------------------#
# Scalar options
#-----------------------------------------------------------------------------#
# Private cores: the last positional is the option name; everything before it is
# the tmux scope ("-g", or "-w -t @2"). The wrappers pass each scope token as a
# separate, quoted argument, so there is no scope-string word-splitting here (and
# thus no SC2086 to disable).

_opt_show  () { tmux show-options -qv "$@"; }   # <scope…> <name>
_opt_list  () { tmux show-options -q  "$@"; }   # same, retaining name/presence
_opt_write () { tmux set-option   -q  "$@"; }   # <scope…> <name> <value>
_opt_clear () { tmux set-option   -qu "$@"; }   # <scope…> <name>

# --- global scope ---
opt_get_global   () { _opt_show  -g "$1"; }
opt_set_global   () { _opt_write -g "$1" "$2"; }
opt_unset_global () { _opt_clear -g "$1"; }

# --- session scope (explicit session id/name) ---
opt_get_session   () { _opt_show  -t "$1" "$2"; }
opt_set_session   () { _opt_write -t "$1" "$2" "$3"; }
opt_unset_session () { _opt_clear -t "$1" "$2"; }
opt_has_session   () { [[ -n "$(_opt_list -t "$1" "$2")" ]]; }

# --- window scope (explicit window id; "current" is resolved by the caller) ---
opt_get_window   () { _opt_show  -w -t "$1" "$2"; }
opt_set_window   () { _opt_write -w -t "$1" "$2" "$3"; }
opt_unset_window () { _opt_clear -w -t "$1" "$2"; }

# --- composed: get-or-default ---
opt_getor_global () {
  local v; v="$(opt_get_global "$1")"
  if [[ -n $v ]]; then printf '%s' "$v"; else printf '%s' "$2"; fi
}
opt_getor_session () {
  local v; v="$(opt_get_session "$1" "$2")"
  if [[ -n $v ]]; then printf '%s' "$v"; else printf '%s' "$3"; fi
}
opt_getor_window () {
  local v; v="$(opt_get_window "$1" "$2")"
  if [[ -n $v ]]; then printf '%s' "$v"; else printf '%s' "$3"; fi
}

# --- composed: set-if-needed (write only when the value changes) ---
# Returns 0 (success) and writes when the value moved; returns 1 (no write) when
# the option already holds the value. Lets callers gate a redraw:
#   opt_setif_global status-left "$bar" && redraw
opt_setif_global () {
  [[ "$(opt_get_global "$1")" == "$2" ]] && return 1
  opt_set_global "$1" "$2"
}
opt_setif_session () {
  [[ "$(opt_get_session "$1" "$2")" == "$3" ]] && return 1
  opt_set_session "$1" "$2" "$3"
}
opt_setif_window () {
  [[ "$(opt_get_window "$1" "$2")" == "$3" ]] && return 1
  opt_set_window "$1" "$2" "$3"
}

#-----------------------------------------------------------------------------#
# Airline option namespaces — POLICY (DESIGN.md §State model / §Enforcement)
#-----------------------------------------------------------------------------#
# airline owns two option namespaces, and this file is the ONE place their
# prefixes are written:
#   public  (@airline-<key>)   user-set static config — palettes, segments
#   private (@airline--<key>)  airline-managed dynamic state — badges, flags
# Everything above addresses airline options by BARE key through the functions
# below; it never spells a prefix. (Native tmux options — status-left, prefix,
# focus-events, … — are not airline's namespace and keep their real names via
# opt_*.) The lint enforces this: a literal @airline- name outside this file is a
# violation.
#
# The surface is intentionally asymmetric, shaped by how each tier is used:
#   * public values are user-configured global defaults with optional session-local
#     runtime overrides; they are never embedded by a constructed name.
#   * private state is airline-owned and scoped to its actual owner: session or
#     window. Stable badge names are embedded in tmux #{?…} selectors.

# --- public configuration: global defaults plus session-local overrides ---
pub_get   () { opt_get_global   "@airline-$1"; }        # <key>
pub_set   () { opt_set_global   "@airline-$1" "$2"; }   # <key> <value>
pub_unset () { opt_unset_global "@airline-$1"; }        # <key>
pub_get_session   () {   # <session> <key>; local override, then global config default
  local name="@airline-$2"
  if opt_has_session "$1" "$name"; then opt_get_session "$1" "$name"
  else opt_get_global "$name"; fi
}
pub_set_session   () { opt_set_session   "$1" "@airline-$2" "$3"; } # <session> <key> <value>
pub_unset_session () { opt_unset_session "$1" "@airline-$2"; }       # <session> <key>

# --- private: name builder (for composition / format embedding, not get/set) ---
# collections builds its <ns> / <ns>-<key> scheme on this; render embeds a badge
# option name in a live selector with it. The single home for the @airline-- prefix.
prv_name () { printf '@airline--%s' "$1"; }             # <key> → option name

# --- private accessors (session and window scope; never global) ---
prv_get_session   () { opt_get_session   "$1" "@airline--$2"; }       # <session> <key>
prv_set_session   () { opt_set_session   "$1" "@airline--$2" "$3"; } # <session> <key> <value>
prv_setif_session () { opt_setif_session "$1" "@airline--$2" "$3"; } # <session> <key> <value>
prv_unset_session () { opt_unset_session "$1" "@airline--$2"; }       # <session> <key>
prv_get_window   () { opt_get_window   "$1" "@airline--$2"; }       # <win> <key>
prv_setif_window () { opt_setif_window "$1" "@airline--$2" "$3"; }  # <win> <key> <value>
prv_unset_window () { opt_unset_window "$1" "@airline--$2"; }       # <win> <key>

#-----------------------------------------------------------------------------#
# Standalone verbs — distinct tmux subcommands (not option get/set)
#-----------------------------------------------------------------------------#

# Force the status line to re-evaluate now. tmux only re-renders on
# status-interval or incidental events, so a live option change would otherwise
# lag; -S refreshes the status line. No attached client → harmless.
redraw () { tmux refresh-client -S 2>/dev/null || true; }

# Load a tmux source file (used for palette files).
source_file () { tmux source-file "$1"; }
source_file_session () { tmux source-file -t "$1" "$2"; }

# The id (@n) of the window the caller is acting in — lets window-scoped callers
# resolve "current" to an explicit id before calling opt_*_window.
current_window () { tmux display-message -p '#{window_id}'; }
resolve_window () { tmux display-message -p -t "$1" '#{window_id}'; }

# Ask tmux to resolve any valid target (session, window, or pane) to its owning
# session id. This keeps target grammar and current-context rules inside tmux.
resolve_session () { tmux display-message -p -t "$1" '#{session_id}'; }

# Resolve a SESSION target specifically. display-message accepts a pane target, so
# append tmux's session/window separator and let the empty window component select
# that session's current window. This prevents a problem command from accidentally
# treating a pane/window target as its required session input.
resolve_session_target () { tmux display-message -p -t "$1:" '#{session_id}'; }

# Canonical ids for every live session, one per line. Used by cross-session reads;
# mutations always resolve and touch exactly one caller-supplied session.
list_sessions () { tmux list-sessions -F '#{session_id}'; }

# The id ($n) of the session the caller is acting in. A process launched from a
# pane receives TMUX_PANE from tmux, so give that native target back to tmux for an
# unambiguous resolution. Commands without a pane retain tmux's normal current/
# most-recent context rules.
current_session () {
  if [[ -n "${TMUX_PANE:-}" ]]; then resolve_session "$TMUX_PANE"
  else tmux display-message -p '#{session_id}'
  fi
}

# Hooks (the pane-focus-out consume-on-view callback). <spec> is a full hook
# name, optionally indexed, e.g. "pane-focus-out[90]".
hook_set   () { tmux set-hook -g  "$1" "$2"; }
hook_unset () { tmux set-hook -gu "$1"; }

# Private server-coordinated advisory-lock leaves. Higher layers use only the
# scoped transaction functions below, never the lock mechanism directly.
_lock_acquire () { tmux wait-for -L "$1"; }
_lock_release () { tmux wait-for -U "$1"; }

# Run one callback while holding a lock scoped to an airline state owner and
# namespace. Higher layers declare the transaction boundary without knowing the
# wait-for mechanism, channel naming, or cleanup rules. Transactions deliberately
# do not nest: tmux locks are not reentrant, so nesting would deadlock.
_AIRLINE_TRANSACTION_CHANNEL=""

_transaction_cleanup () {
  local channel="${_AIRLINE_TRANSACTION_CHANNEL:-}"
  [[ -n "$channel" ]] || return 0
  _AIRLINE_TRANSACTION_CHANNEL=""
  _lock_release "$channel" || true
}

_transaction_abort () {   # <signal>
  local signal="$1"
  _transaction_cleanup
  trap - "$signal"
  kill -s "$signal" "$$"
}

_with_transaction () {   # <session|window> <target> <namespace> <callback> [<arg>...]
  local scope="$1" target="$2" namespace="$3" callback="$4" channel rc; shift 4
  [[ -z "${_AIRLINE_TRANSACTION_CHANNEL:-}" ]] || {
    printf 'airline: nested state transaction (%s)\n' "$_AIRLINE_TRANSACTION_CHANNEL" >&2
    return 2
  }
  target="${target//[^a-zA-Z0-9_-]/_}"
  namespace="${namespace//[^a-zA-Z0-9_-]/_}"
  channel="airline-$scope-$target-$namespace"
  _lock_acquire "$channel" || return 1
  _AIRLINE_TRANSACTION_CHANNEL="$channel"
  trap '_transaction_cleanup' EXIT
  trap '_transaction_abort HUP' HUP
  trap '_transaction_abort INT' INT
  trap '_transaction_abort TERM' TERM
  "$callback" "$@"; rc=$?
  _transaction_cleanup
  trap - EXIT HUP INT TERM
  return "$rc"
}

with_session_transaction () {   # <session> <namespace> <callback> [<arg>...]
  _with_transaction session "$@"
}

with_window_transaction () {    # <window> <namespace> <callback> [<arg>...]
  _with_transaction window "$@"
}

# Key bindings — a primitive for callers; airline itself binds no keys (a user wires
# their own, e.g. `bind F12 run "#{@airline-cli} state toggle"`). <table> is a key-table.
key_bind   () { tmux bind-key   -T "$1" "$2" "$3"; }
key_unbind () { tmux unbind-key -T "$1" "$2"; }

# vim: ft=bash
