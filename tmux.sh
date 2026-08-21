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
#   * A function exists only for a tmux subcommand that is NOT an option:
#     built-in options (prefix, key-table, status-left, …) go through
#     opt_set_global / opt_unset_global like any other option.
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
#   * public is read/written by computed bare keys, always at global scope, and is
#     never embedded in a format — so it needs accessors only, no name builder.
#   * private is reached through a few stable keys AND embedded by name inside tmux
#     #{?…} selectors (the badges), and spans global/session/window scope — so it needs a
#     name builder (prv_name) plus scoped accessors.

# --- public (always global) ---
pub_get   () { opt_get_global   "@airline-$1"; }        # <key>
pub_set   () { opt_set_global   "@airline-$1" "$2"; }   # <key> <value>
pub_unset () { opt_unset_global "@airline-$1"; }        # <key>

# --- private: name builder (for composition / format embedding, not get/set) ---
# collections builds its <ns> / <ns>-<key> scheme on this; render embeds a badge
# option name in a live selector with it. The single home for the @airline-- prefix.
prv_name () { printf '@airline--%s' "$1"; }             # <key> → option name

# --- private accessors (global, session, and window scope) ---
prv_get_global   () { opt_get_global   "@airline--$1"; }            # <key>
prv_set_global   () { opt_set_global   "@airline--$1" "$2"; }       # <key> <value>
prv_get_session   () { opt_get_session   "$1" "@airline--$2"; }       # <session> <key>
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

# The id (@n) of the window the caller is acting in — lets window-scoped callers
# resolve "current" to an explicit id before calling opt_*_window.
current_window () { tmux display-message -p '#{window_id}'; }

# The id ($n) of the session the caller is acting in. Session-scoped APIs accept
# an explicit target, but use this when invoked interactively without one.
current_session () { tmux display-message -p '#{session_id}'; }

# Hooks (the pane-focus-out consume-on-view callback). <spec> is a full hook
# name, optionally indexed, e.g. "pane-focus-out[90]".
hook_set   () { tmux set-hook -g  "$1" "$2"; }
hook_unset () { tmux set-hook -gu "$1"; }

# Key bindings — a primitive for callers; airline itself binds no keys (a user wires
# their own, e.g. `bind F12 run "#{@airline-cli} state toggle"`). <table> is a key-table.
key_bind   () { tmux bind-key   -T "$1" "$2" "$3"; }
key_unbind () { tmux unbind-key -T "$1" "$2"; }

# vim: ft=bash
