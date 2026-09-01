#!/usr/bin/env bash
#
# tmux.sh — the mechanical layer: the ONE place that talks to the tmux binary.
#
# Everything airline reads or writes in tmux goes through these functions; the
# layers above call them and never invoke `tmux` directly — a build-time lint
# enforces that, so this file is the sole entry on its allowlist.
#
# Conventions:
#   * Callers never pass tmux flags. Generic option access takes a scope value;
#     fixed-policy scalar accessors may encode ownership in names such as
#     opt_set_window. Arguments are fixed and positional.
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

# ShellCheck cannot see that this nameref assignment mutates the caller's array.
# shellcheck disable=SC2034
_scope_option_args () {   # <array-destination> <global|session|window> <target>
  local -n scope_arguments="$1"
  local scope="$2" target="$3"
  case "$scope" in
    global)  scope_arguments=(-g) ;;
    session) [[ -n "$target" ]] || return 2; scope_arguments=(-t "$target") ;;
    window)  [[ -n "$target" ]] || return 2; scope_arguments=(-w -t "$target") ;;
    *) return 2 ;;
  esac
}

# A transaction-local option workspace. tmux serializes listed values using its
# configuration syntax (one escaped option per line), which lets us load an entire
# scope with one client, serve scalar accessors from Bash, and submit the final
# ordered diff as one command sequence. Presence is stored separately from value so
# an explicitly empty user option remains distinct from an absent one.
_AIRLINE_OPT_WORKSPACE=""
_AIRLINE_OPT_OWNER_SCOPE=""
_AIRLINE_OPT_OWNER_TARGET=""
_AIRLINE_OPT_REDRAW=""
declare -gA _AIRLINE_OPT_VALUE=()
declare -gA _AIRLINE_OPT_PRESENT=()
declare -gA _AIRLINE_OPT_BASE_VALUE=()
declare -gA _AIRLINE_OPT_BASE_PRESENT=()
declare -gA _AIRLINE_OPT_SCOPE=()
declare -gA _AIRLINE_OPT_TARGET=()
declare -gA _AIRLINE_OPT_NAME=()
declare -gA _AIRLINE_OPT_DIRTY=()
declare -gA _AIRLINE_OPT_LOADED=()
declare -ga _AIRLINE_OPT_DIRTY_ORDER=()

_opt_key () {   # <destination-variable> <scope> <target> <name>
  local -n destination="$1"
  printf -v destination '%s\037%s\037%s' "$2" "$3" "$4"
}

_opt_decode () {   # <tmux-serialized-value> <destination-variable>
  local encoded="$1"; local -n destination="$2"
  if [[ ${#encoded} -ge 2 && "${encoded:0:1}" == '"' && "${encoded: -1}" == '"' ]]; then
    encoded="${encoded:1:${#encoded}-2}"
  fi
  printf -v destination '%b' "$encoded"
}

_opt_snapshot_line () {   # <scope> <target> <serialized-option-line>
  local scope="$1" target="$2" line="$3" name encoded value key
  [[ -n "$line" ]] || return 0
  name="${line%% *}"
  encoded="${line#"$name"}"
  encoded="${encoded# }"
  _opt_decode "$encoded" value
  _opt_key key "$scope" "$target" "$name"
  _AIRLINE_OPT_VALUE["$key"]="$value"
  _AIRLINE_OPT_PRESENT["$key"]=1
  _AIRLINE_OPT_BASE_VALUE["$key"]="$value"
  _AIRLINE_OPT_BASE_PRESENT["$key"]=1
  _AIRLINE_OPT_SCOPE["$key"]="$scope"
  _AIRLINE_OPT_TARGET["$key"]="$target"
  _AIRLINE_OPT_NAME["$key"]="$name"
}

_opt_snapshot () {   # <global|session|window> <target>
  local scope="$1" target="$2" line raw table_key
  local -a scope_args
  _scope_option_args scope_args "$scope" "$target" || return
  if [[ "$scope" == global ]]; then
    # Native global options occupy separate session and window tables. Load the
    # extra window table first so an identically named user option in the ordinary
    # global session table retains `set -g` / `show -g` precedence.
    raw="$(_opt_list -gw)" || return
    while IFS= read -r line; do _opt_snapshot_line global "" "$line"; done <<< "$raw"
  fi
  raw="$(_opt_list "${scope_args[@]}")" || return
  while IFS= read -r line; do _opt_snapshot_line "$scope" "$target" "$line"; done <<< "$raw"
  printf -v table_key '%s\037%s' "$scope" "$target"
  _AIRLINE_OPT_LOADED["$table_key"]=1
}

_opt_snapshot_if_needed () {   # <global|session|window> <target>
  local table_key
  [[ -n "$_AIRLINE_OPT_WORKSPACE" ]] || return 0
  printf -v table_key '%s\037%s' "$1" "$2"
  [[ -n "${_AIRLINE_OPT_LOADED[$table_key]:-}" ]] || _opt_snapshot "$1" "$2"
}

_opt_workspace_begin () {   # <global|session|window> <target>
  local scope="$1" target="$2"
  [[ -z "$_AIRLINE_OPT_WORKSPACE" ]] || return 2
  _AIRLINE_OPT_VALUE=(); _AIRLINE_OPT_PRESENT=()
  _AIRLINE_OPT_BASE_VALUE=(); _AIRLINE_OPT_BASE_PRESENT=()
  _AIRLINE_OPT_SCOPE=(); _AIRLINE_OPT_TARGET=(); _AIRLINE_OPT_NAME=()
  _AIRLINE_OPT_DIRTY=(); _AIRLINE_OPT_LOADED=(); _AIRLINE_OPT_DIRTY_ORDER=()
  _AIRLINE_OPT_REDRAW=""
  _opt_snapshot global "" || return 1
  [[ "$scope" == global ]] || _opt_snapshot "$scope" "$target" || return 1
  _AIRLINE_OPT_OWNER_SCOPE="$scope"
  _AIRLINE_OPT_OWNER_TARGET="$target"
  _AIRLINE_OPT_WORKSPACE=1
}

_opt_workspace_end () {
  _AIRLINE_OPT_WORKSPACE=""; _AIRLINE_OPT_REDRAW=""
  _AIRLINE_OPT_OWNER_SCOPE=""; _AIRLINE_OPT_OWNER_TARGET=""
  _AIRLINE_OPT_VALUE=(); _AIRLINE_OPT_PRESENT=()
  _AIRLINE_OPT_BASE_VALUE=(); _AIRLINE_OPT_BASE_PRESENT=()
  _AIRLINE_OPT_SCOPE=(); _AIRLINE_OPT_TARGET=(); _AIRLINE_OPT_NAME=()
  _AIRLINE_OPT_DIRTY=(); _AIRLINE_OPT_LOADED=(); _AIRLINE_OPT_DIRTY_ORDER=()
}

_opt_workspace_reload () {
  local scope="$_AIRLINE_OPT_OWNER_SCOPE" target="$_AIRLINE_OPT_OWNER_TARGET"
  [[ -n "$_AIRLINE_OPT_WORKSPACE" ]] || return 0
  _opt_workspace_end
  _opt_workspace_begin "$scope" "$target"
}

_opt_read () {   # <global|session|window> <target> <name>
  local scope="$1" target="$2" name="$3" key
  local -a scope_args
  _scope_option_args scope_args "$scope" "$target" || return
  if [[ -n "$_AIRLINE_OPT_WORKSPACE" ]]; then
    _opt_snapshot_if_needed "$scope" "$target" || return
    _opt_key key "$scope" "$target" "$name"
    [[ -n "${_AIRLINE_OPT_PRESENT[$key]:-}" ]] && printf '%s' "${_AIRLINE_OPT_VALUE[$key]}"
    return 0
  fi
  _opt_show "${scope_args[@]}" "$name"
}

_opt_present () {   # <global|session|window> <target> <name>
  local scope="$1" target="$2" name="$3" key
  local -a scope_args
  _scope_option_args scope_args "$scope" "$target" || return
  if [[ -n "$_AIRLINE_OPT_WORKSPACE" ]]; then
    _opt_snapshot_if_needed "$scope" "$target" || return
    _opt_key key "$scope" "$target" "$name"
    [[ -n "${_AIRLINE_OPT_PRESENT[$key]:-}" ]]
    return
  fi
  [[ -n "$(_opt_list "${scope_args[@]}" "$name")" ]]
}

_opt_mark_dirty () {   # <key>
  local key="$1"
  [[ -n "${_AIRLINE_OPT_DIRTY[$key]:-}" ]] || _AIRLINE_OPT_DIRTY_ORDER+=("$key")
  _AIRLINE_OPT_DIRTY["$key"]=1
}

_opt_store () {   # <global|session|window> <target> <name> <value>
  local scope="$1" target="$2" name="$3" value="$4" key
  local -a scope_args
  _scope_option_args scope_args "$scope" "$target" || return
  if [[ -z "$_AIRLINE_OPT_WORKSPACE" ]]; then
    _opt_write "${scope_args[@]}" "$name" "$value"
    return
  fi
  _opt_key key "$scope" "$target" "$name"
  _AIRLINE_OPT_VALUE["$key"]="$value"
  _AIRLINE_OPT_PRESENT["$key"]=1
  _AIRLINE_OPT_SCOPE["$key"]="$scope"
  _AIRLINE_OPT_TARGET["$key"]="$target"
  _AIRLINE_OPT_NAME["$key"]="$name"
  _opt_mark_dirty "$key"
}

_opt_remove () {   # <global|session|window> <target> <name>
  local scope="$1" target="$2" name="$3" key
  local -a scope_args
  _scope_option_args scope_args "$scope" "$target" || return
  if [[ -z "$_AIRLINE_OPT_WORKSPACE" ]]; then
    _opt_clear "${scope_args[@]}" "$name"
    return
  fi
  _opt_key key "$scope" "$target" "$name"
  unset '_AIRLINE_OPT_VALUE[$key]' '_AIRLINE_OPT_PRESENT[$key]'
  _AIRLINE_OPT_SCOPE["$key"]="$scope"
  _AIRLINE_OPT_TARGET["$key"]="$target"
  _AIRLINE_OPT_NAME["$key"]="$name"
  _opt_mark_dirty "$key"
}

_opt_escape_sequence_arg () {   # <value> <destination-variable>
  local input="$1"; local -n destination="$2"
  destination="$input"
  # tmux treats an individual or trailing semicolon as a command separator even
  # after shell argv parsing. One additional backslash makes it data.
  [[ "$destination" == *';' ]] && destination="${destination%;}\\;"
}

_opt_workspace_flush () {
  local key scope target name value changed="" redraw="$_AIRLINE_OPT_REDRAW"
  local -a commands=() scope_args=()
  [[ -n "$_AIRLINE_OPT_WORKSPACE" ]] || return 0
  for key in "${_AIRLINE_OPT_DIRTY_ORDER[@]}"; do
    if [[ -n "${_AIRLINE_OPT_PRESENT[$key]:-}" ]]; then
      if [[ -n "${_AIRLINE_OPT_BASE_PRESENT[$key]:-}" &&
            "${_AIRLINE_OPT_BASE_VALUE[$key]}" == "${_AIRLINE_OPT_VALUE[$key]}" ]]; then
        continue
      fi
    elif [[ -z "${_AIRLINE_OPT_BASE_PRESENT[$key]:-}" ]]; then
      continue
    fi
    scope="${_AIRLINE_OPT_SCOPE[$key]}"; target="${_AIRLINE_OPT_TARGET[$key]}"
    name="${_AIRLINE_OPT_NAME[$key]}"
    _scope_option_args scope_args "$scope" "$target" || return
    [[ ${#commands[@]} -eq 0 ]] || commands+=(';')
    if [[ -n "${_AIRLINE_OPT_PRESENT[$key]:-}" ]]; then
      _opt_escape_sequence_arg "${_AIRLINE_OPT_VALUE[$key]}" value
      commands+=(set-option -q "${scope_args[@]}" "$name" "$value")
    else
      commands+=(set-option -qu "${scope_args[@]}" "$name")
    fi
    changed=1
  done
  if [[ -n "$changed" ]]; then
    tmux "${commands[@]}" || return 1
  fi
  _AIRLINE_OPT_DIRTY=(); _AIRLINE_OPT_DIRTY_ORDER=()
  _AIRLINE_OPT_BASE_VALUE=(); _AIRLINE_OPT_BASE_PRESENT=()
  for key in "${!_AIRLINE_OPT_PRESENT[@]}"; do
    _AIRLINE_OPT_BASE_PRESENT["$key"]=1
    _AIRLINE_OPT_BASE_VALUE["$key"]="${_AIRLINE_OPT_VALUE[$key]}"
  done
  _AIRLINE_OPT_REDRAW=""
  case "$redraw" in
    all) _redraw_all_now ;;
    ?*)  tmux refresh-client -S 2>/dev/null || true ;;
  esac
}

# --- generic scope-first access (used by collections) ---
opt_get          () { _opt_read   "$@"; } # <scope> <target> <name>
opt_set          () { _opt_store  "$@"; } # <scope> <target> <name> <value>
opt_unset        () { _opt_remove "$@"; } # <scope> <target> <name>

# --- global scope ---
opt_get_global   () { _opt_read    global "" "$1"; }
opt_set_global   () { _opt_store   global "" "$1" "$2"; }
opt_unset_global () { _opt_remove  global "" "$1"; }
opt_has_global   () { _opt_present global "" "$1"; }

# --- session scope (explicit session id/name) ---
opt_get_session   () { _opt_read    session "$1" "$2"; }
opt_set_session   () { _opt_store   session "$1" "$2" "$3"; }
opt_unset_session () { _opt_remove  session "$1" "$2"; }
opt_has_session   () { _opt_present session "$1" "$2"; }

# --- window scope (explicit window id; "current" is resolved by the caller) ---
opt_get_window   () { _opt_read   window "$1" "$2"; }
opt_set_window   () { _opt_store  window "$1" "$2" "$3"; }
opt_unset_window () { _opt_remove window "$1" "$2"; }

# --- composed: set-if-needed (write only when the value changes) ---
# Mutations use ordinary success/failure status. The caller-selected destination is
# set to 1 when a write was needed and left empty for a successful no-op, keeping
# redraw gating out of the public exit-status contract.
_opt_setif () {   # <destination> <global|session|window> <target> <name> <value>
  local -n destination="$1"
  local scope="$2" target="$3" name="$4" value="$5" current
  destination=""
  # Load a non-owner table in this shell before the getter's command substitution;
  # otherwise Bash would discard the lazy snapshot with that subshell.
  _opt_snapshot_if_needed "$scope" "$target" || return
  current="$(_opt_read "$scope" "$target" "$name")" || return
  [[ "$current" != "$value" ]] || return 0
  _opt_store "$scope" "$target" "$name" "$value" || return
  destination=1
}
opt_setif_global  () { _opt_setif "$1" global  "" "$2" "$3"; }
opt_setif_session () { _opt_setif "$1" session "$2" "$3" "$4"; }
opt_setif_window  () { _opt_setif "$1" window  "$2" "$3" "$4"; }

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
#   * public values are user-configured global input; exact session values exist
#     only while palette/layout files are being captured.
#   * private state is airline-owned and scoped to its actual owner: session or
#     window. Stable badge names are embedded in tmux #{?…} selectors.

# --- public configuration: durable input exists at global scope only ---
pub_get   () { opt_get_global   "@airline-$1"; }        # <key>
pub_set   () { opt_set_global   "@airline-$1" "$2"; }   # <key> <value>
pub_has   () { opt_has_global   "@airline-$1"; }        # <key>

# Palette files retain their native tmux surface. Airline evaluates one in the
# target session, captures its public options, then removes them.
# These exact-scope accessors are staging mechanics, never durable configuration.
stage_get_session   () { opt_get_session   "$1" "@airline-$2"; }       # <session> <key>
stage_has_session   () { opt_has_session   "$1" "@airline-$2"; }       # <session> <key>
stage_unset_session () { opt_unset_session "$1" "@airline-$2"; }       # <session> <key>

# Committed configuration is private and session-owned. Render, adapters, and the
# CLI read this snapshot; only airline writes it.
cfg_get_session   () { prv_get_session   "$1" "config-$2"; }       # <session> <key>
cfg_set_session   () { prv_set_session   "$1" "config-$2" "$3"; } # <session> <key> <value>

# --- private: name builder (for composition / format embedding, not get/set) ---
# collections builds its <ns> / <ns>-<key> scheme on this; render embeds a badge
# option name in a live selector with it. The single home for the @airline-- prefix.
prv_name () { printf '@airline--%s' "$1"; }             # <key> → option name

# --- private accessors ---
# Global private state is deliberately narrow: only the server-wide problem
# ledger and its projected badge use it. Configuration remains public-global;
# all other managed state retains its native session/window owner.
prv_get_global   () { opt_get_global   "@airline--$1"; }       # <key>
prv_setif_global () { opt_setif_global "$1" "@airline--$2" "$3"; } # <dest> <key> <value>
prv_unset_global () { opt_unset_global "@airline--$1"; }       # <key>

prv_get_session   () { opt_get_session   "$1" "@airline--$2"; }       # <session> <key>
prv_set_session   () { opt_set_session   "$1" "@airline--$2" "$3"; } # <session> <key> <value>
prv_unset_session () { opt_unset_session "$1" "@airline--$2"; }       # <session> <key>
prv_get_window   () { opt_get_window   "$1" "@airline--$2"; }       # <win> <key>
prv_setif_window () { opt_setif_window "$1" "$2" "@airline--$3" "$4"; }  # <dest> <win> <key> <value>
prv_unset_window () { opt_unset_window "$1" "@airline--$2"; }       # <win> <key>

#-----------------------------------------------------------------------------#
# Standalone verbs — distinct tmux subcommands (not option get/set)
#-----------------------------------------------------------------------------#

# Force the status line to re-evaluate now. tmux only re-renders on
# status-interval or incidental events, so a live option change would otherwise
# lag; -S refreshes the status line. No attached client → harmless.
redraw () {
  if [[ -n "$_AIRLINE_OPT_WORKSPACE" ]]; then _AIRLINE_OPT_REDRAW=1
  else tmux refresh-client -S 2>/dev/null || true; fi
}

_redraw_all_now () {
  local clients client
  clients="$(tmux list-clients -F '#{client_name}' 2>/dev/null)" || return 0
  while IFS= read -r client; do
    [[ -n "$client" ]] || continue
    tmux refresh-client -S -t "$client" 2>/dev/null || true
  done <<< "$clients"
}

# A global projection is visible in every initialized session, so refresh every
# attached client rather than only the hook/command's current client.
redraw_all () {
  if [[ -n "$_AIRLINE_OPT_WORKSPACE" ]]; then _AIRLINE_OPT_REDRAW=all
  else _redraw_all_now; fi
}

# Load a palette file into one explicit session evaluation surface.
source_file_session () {
  _opt_workspace_flush || return
  tmux source-file -t "$1" "$2" || return
  _opt_workspace_reload
}

# The id (@n) of the window the caller is acting in — lets window-scoped callers
# resolve "current" to an explicit id before calling opt_*_window.
current_window () { tmux display-message -p '#{window_id}'; }
resolve_window () { tmux display-message -p -t "$1" '#{window_id}'; }

# Current pane identity and working directory for runner placement. Context remains
# tmux's responsibility; higher layers receive canonical values only.
current_pane () {
  if [[ -n "${TMUX_PANE:-}" ]]; then tmux display-message -p -t "$TMUX_PANE" '#{pane_id}'
  else tmux display-message -p '#{pane_id}'; fi
}
resolve_pane () { tmux display-message -p -t "$1" '#{pane_id}'; }
current_path () {
  if [[ -n "${TMUX_PANE:-}" ]]; then tmux display-message -p -t "$TMUX_PANE" '#{pane_current_path}'
  else tmux display-message -p '#{pane_current_path}'; fi
}

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

list_windows () { tmux list-windows -t "$1:" -F '#{window_id}'; }

# The id ($n) of the session the caller is acting in. A process launched from a
# pane receives TMUX_PANE from tmux, so give that native target back to tmux for an
# unambiguous resolution. Commands without a pane retain tmux's normal current/
# most-recent context rules.
current_session () {
  if [[ -n "${TMUX_PANE:-}" ]]; then resolve_session "$TMUX_PANE"
  else tmux display-message -p '#{session_id}'
  fi
}

# Runner topology. Commands are argv vectors, not shell strings: split/new-window
# pass every argument after the fixed placement fields directly to the new pane.
# Both creators print the new pane id so orchestration can identify its owner.
runner_open_pane () {   # <target-pane> <cwd> <-h|-v|empty> <command> [<arg>...]
  local target="$1" cwd="$2" orientation="$3"; shift 3
  local -a split_args=()
  [[ -n "$orientation" ]] && split_args+=("$orientation")
  tmux split-window "${split_args[@]}" -d -P -F '#{pane_id}' -c "$cwd" -t "$target" "$@"
}

runner_open_window () {   # <target-session> <cwd> <command> [<arg>...]
  local session="$1" cwd="$2"; shift 2
  tmux new-window -d -P -F '#{pane_id}' -c "$cwd" -t "$session:" "$@"
}

# Preserve a spawned command's pane after exit. remain-on-exit is pane-scoped, so
# another pane in the same window keeps its ordinary lifecycle.
runner_retain_pane () { tmux set-option -p -t "$1" remain-on-exit on; }

# Hooks (the pane-focus-out consume-on-view callback). <spec> is a full hook
# name, optionally indexed, e.g. "pane-focus-out[90]".
hook_set   () { tmux set-hook -g  "$1" "$2"; }

# A new window has no session-specific window-option defaults in tmux. Copy the
# owning session's committed palette roles into the three palette-derived window
# options immediately after creation. -F expands the private session options in
# the hook's native session/window context before storing concrete option values.
hook_set_airline_window_styles () {
  tmux set-hook -g "after-new-window[90]" \
    "set-option -qFw pane-border-style 'fg=#{@airline--config-primary}' ; set-option -qFw pane-active-border-style 'fg=#{@airline--config-active}' ; set-option -qFw clock-mode-colour '#{@airline--config-special}'"
}

# Run one callback while holding a lock scoped to an airline state owner and
# namespace. Higher layers declare the transaction boundary without knowing the
# wait-for mechanism, channel naming, or cleanup rules. Transactions deliberately
# do not nest: tmux locks are not reentrant, so nesting would deadlock.
_AIRLINE_TRANSACTION_CHANNEL=""
_AIRLINE_TRANSACTION_SCOPE=""
_AIRLINE_TRANSACTION_TARGET=""
_AIRLINE_TRANSACTION_NAMESPACE=""

_transaction_marker_name () { printf '@airline--transaction-%s' "$1"; }

_transaction_channel () {   # <global|session|window> <canonical-target> <namespace>
  local scope="$1" target="$2" namespace="$3"
  target="${target//[^a-zA-Z0-9_-]/_}"
  printf 'airline-%s-%s-%s' "$scope" "$target" "$namespace"
}

# Acquire/release update the owner marker in the SAME tmux command sequence as
# wait-for. If the shell disappears between commands, tmux still completes both,
# so every held Airline lock remains discoverable.
_transaction_acquire () {   # <scope> <target> <namespace> <channel> <metadata>
  local scope="$1" target="$2" namespace="$3" channel="$4" metadata="$5"
  local -a scope_args
  local marker; marker="$(_transaction_marker_name "$namespace")"
  _scope_option_args scope_args "$scope" "$target" || return
  tmux wait-for -L "$channel" \; set-option -q "${scope_args[@]}" "$marker" "$metadata" || {
    tmux wait-for -U "$channel" 2>/dev/null || true
    return 1
  }
}

_transaction_release () {   # <scope> <target> <namespace> <channel>
  local scope="$1" target="$2" namespace="$3" channel="$4"
  local -a scope_args
  local marker; marker="$(_transaction_marker_name "$namespace")"
  _scope_option_args scope_args "$scope" "$target" || return
  tmux set-option -qu "${scope_args[@]}" "$marker" \; wait-for -U "$channel"
}

_transaction_cleanup () {
  local channel="${_AIRLINE_TRANSACTION_CHANNEL:-}"
  [[ -n "$channel" ]] || return 0
  _opt_workspace_flush || true
  _opt_workspace_end
  _AIRLINE_TRANSACTION_CHANNEL=""
  _transaction_release \
    "$_AIRLINE_TRANSACTION_SCOPE" "$_AIRLINE_TRANSACTION_TARGET" \
    "$_AIRLINE_TRANSACTION_NAMESPACE" "$channel" || true
}

_transaction_abort () {   # <exit-status>
  local status="$1"
  _transaction_cleanup
  exit "$status"
}

_with_transaction () (   # <global|session|window> <target> <namespace> <callback> [<arg>...]
  local scope="$1" target="$2" namespace="$3" callback="$4" channel started metadata
  local rc=0 release_rc=0; shift 4
  [[ -z "${_AIRLINE_TRANSACTION_CHANNEL:-}" ]] || {
    printf 'airline: nested state transaction (%s)\n' "$_AIRLINE_TRANSACTION_CHANNEL" >&2
    return 2
  }
  [[ "$namespace" =~ ^[a-zA-Z0-9_-]+$ ]] || return 2
  channel="$(_transaction_channel "$scope" "$target" "$namespace")"
  printf -v started '%(%s)T' -1
  metadata="${BASHPID}:${started}"
  _transaction_acquire "$scope" "$target" "$namespace" "$channel" "$metadata" || return 1
  _AIRLINE_TRANSACTION_CHANNEL="$channel"
  _AIRLINE_TRANSACTION_SCOPE="$scope"
  _AIRLINE_TRANSACTION_TARGET="$target"
  _AIRLINE_TRANSACTION_NAMESPACE="$namespace"
  trap '_transaction_cleanup' EXIT
  trap '_transaction_abort 129' HUP
  trap '_transaction_abort 130' INT
  trap '_transaction_abort 143' TERM
  _opt_workspace_begin "$scope" "$target" || { _transaction_cleanup; return 1; }
  "$callback" "$@" || rc=$?
  _opt_workspace_flush || { [[ $rc -ne 0 ]] || rc=1; }
  _opt_workspace_end
  _transaction_release "$scope" "$target" "$namespace" "$channel" || release_rc=$?
  _AIRLINE_TRANSACTION_CHANNEL=""
  _AIRLINE_TRANSACTION_SCOPE=""
  _AIRLINE_TRANSACTION_TARGET=""
  _AIRLINE_TRANSACTION_NAMESPACE=""
  trap - EXIT HUP INT TERM
  [[ $rc -ne 0 || $release_rc -eq 0 ]] || rc=$release_rc
  return "$rc"
)

with_session_transaction () {   # <session> <namespace> <callback> [<arg>...]
  _with_transaction session "$@"
}

with_window_transaction () {    # <window> <namespace> <callback> [<arg>...]
  _with_transaction window "$@"
}

with_global_transaction () {    # <namespace> <callback> [<arg>...]
  _with_transaction global server "$@"
}

# Outstanding transaction markers are the observable lock registry. Output is
# tab-delimited: <scope> <owner> <namespace> <active|stale> <pid> <age-seconds>.
_transaction_list_owner () {   # <global|session|window> <target>
  local scope="$1" target="$2" raw name metadata namespace pid started now age state
  local -a scope_args
  _scope_option_args scope_args "$scope" "$target" || return
  raw="$(_opt_list "${scope_args[@]}")" || return
  printf -v now '%(%s)T' -1
  while read -r name metadata; do
    case "$name" in @airline--transaction-*) ;; *) continue ;; esac
    namespace="${name#@airline--transaction-}"
    pid="${metadata%%:*}"; started="${metadata#*:}"
    [[ "$pid" =~ ^[0-9]+$ && "$started" =~ ^[0-9]+$ ]] || continue
    if kill -0 "$pid" 2>/dev/null; then state=active; else state=stale; fi
    age=$(( now >= started ? now - started : 0 ))
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$scope" "$target" "$namespace" "$state" "$pid" "$age"
  done <<< "$raw"
}

transaction_list () {
  local target seen=" "
  _transaction_list_owner global server
  for target in $(list_sessions); do _transaction_list_owner session "$target"; done
  for target in $(tmux list-windows -a -F '#{window_id}'); do
    case "$seen" in *" $target "*) continue ;; esac
    seen+="$target "
    _transaction_list_owner window "$target"
  done
}

# Clear one STALE marker and its wait-for channel. A live owner is never forcibly
# unlocked: its later cleanup could otherwise release a successor's lock.
transaction_clear () {   # <global|session|window> <target> <namespace>
  local scope="$1" target="$2" namespace="$3" metadata pid channel marker
  [[ "$namespace" =~ ^[a-zA-Z0-9_-]+$ ]] || return 2
  case "$scope" in
    global)  [[ "$target" == server ]] || return 2 ;;
    session) target="$(resolve_session_target "$target")" || return 2 ;;
    window)  target="$(resolve_window "$target")" || return 2 ;;
    *) return 2 ;;
  esac
  marker="$(_transaction_marker_name "$namespace")"
  metadata="$(opt_get "$scope" "$target" "$marker")" || return
  [[ -n "$metadata" ]] || return 3
  pid="${metadata%%:*}"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 2
  kill -0 "$pid" 2>/dev/null && return 4
  channel="$(_transaction_channel "$scope" "$target" "$namespace")"
  _transaction_release "$scope" "$target" "$namespace" "$channel"
}

# vim: ft=bash
