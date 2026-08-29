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
  local scope="$1" target="$2" line raw
  case "$scope" in
    global)
      # Native global options occupy separate session and window tables. Load the
      # window table first so an identically named user option in the ordinary
      # global session table retains `set -g` / `show -g` precedence.
      raw="$(_opt_list -gw)" || return
      while IFS= read -r line; do _opt_snapshot_line global "" "$line"; done <<< "$raw"
      raw="$(_opt_list -g)" || return
      while IFS= read -r line; do _opt_snapshot_line global "" "$line"; done <<< "$raw"
      ;;
    session)
      raw="$(_opt_list -t "$target")" || return
      while IFS= read -r line; do _opt_snapshot_line session "$target" "$line"; done <<< "$raw"
      ;;
    window)
      raw="$(_opt_list -w -t "$target")" || return
      while IFS= read -r line; do _opt_snapshot_line window "$target" "$line"; done <<< "$raw"
      ;;
  esac
}

_opt_workspace_begin () {   # <session|window> <target>
  local scope="$1" target="$2"
  [[ -z "$_AIRLINE_OPT_WORKSPACE" ]] || return 2
  _AIRLINE_OPT_VALUE=(); _AIRLINE_OPT_PRESENT=()
  _AIRLINE_OPT_BASE_VALUE=(); _AIRLINE_OPT_BASE_PRESENT=()
  _AIRLINE_OPT_SCOPE=(); _AIRLINE_OPT_TARGET=(); _AIRLINE_OPT_NAME=()
  _AIRLINE_OPT_DIRTY=(); _AIRLINE_OPT_DIRTY_ORDER=()
  _AIRLINE_OPT_REDRAW=""
  _opt_snapshot global "" || return 1
  _opt_snapshot "$scope" "$target" || return 1
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
  _AIRLINE_OPT_DIRTY=(); _AIRLINE_OPT_DIRTY_ORDER=()
}

_opt_workspace_reload () {
  local scope="$_AIRLINE_OPT_OWNER_SCOPE" target="$_AIRLINE_OPT_OWNER_TARGET"
  [[ -n "$_AIRLINE_OPT_WORKSPACE" ]] || return 0
  _opt_workspace_end
  _opt_workspace_begin "$scope" "$target"
}

_opt_read () {   # <global|session|window> <target> <name>
  local scope="$1" target="$2" name="$3" key
  if [[ -n "$_AIRLINE_OPT_WORKSPACE" ]]; then
    _opt_key key "$scope" "$target" "$name"
    [[ -n "${_AIRLINE_OPT_PRESENT[$key]:-}" ]] && printf '%s' "${_AIRLINE_OPT_VALUE[$key]}"
    return 0
  fi
  case "$scope" in
    global)  _opt_show -g "$name" ;;
    session) _opt_show -t "$target" "$name" ;;
    window)  _opt_show -w -t "$target" "$name" ;;
  esac
}

_opt_present () {   # <global|session|window> <target> <name>
  local scope="$1" target="$2" name="$3" key
  if [[ -n "$_AIRLINE_OPT_WORKSPACE" ]]; then
    _opt_key key "$scope" "$target" "$name"
    [[ -n "${_AIRLINE_OPT_PRESENT[$key]:-}" ]]
    return
  fi
  case "$scope" in
    global)  [[ -n "$(_opt_list -g "$name")" ]] ;;
    session) [[ -n "$(_opt_list -t "$target" "$name")" ]] ;;
    window)  [[ -n "$(_opt_list -w -t "$target" "$name")" ]] ;;
  esac
}

_opt_mark_dirty () {   # <key>
  local key="$1"
  [[ -n "${_AIRLINE_OPT_DIRTY[$key]:-}" ]] || _AIRLINE_OPT_DIRTY_ORDER+=("$key")
  _AIRLINE_OPT_DIRTY["$key"]=1
}

_opt_store () {   # <global|session|window> <target> <name> <value>
  local scope="$1" target="$2" name="$3" value="$4" key
  if [[ -z "$_AIRLINE_OPT_WORKSPACE" ]]; then
    case "$scope" in
      global)  _opt_write -g "$name" "$value" ;;
      session) _opt_write -t "$target" "$name" "$value" ;;
      window)  _opt_write -w -t "$target" "$name" "$value" ;;
    esac
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
  if [[ -z "$_AIRLINE_OPT_WORKSPACE" ]]; then
    case "$scope" in
      global)  _opt_clear -g "$name" ;;
      session) _opt_clear -t "$target" "$name" ;;
      window)  _opt_clear -w -t "$target" "$name" ;;
    esac
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
  local -a commands=()
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
    [[ ${#commands[@]} -eq 0 ]] || commands+=(';')
    if [[ -n "${_AIRLINE_OPT_PRESENT[$key]:-}" ]]; then
      _opt_escape_sequence_arg "${_AIRLINE_OPT_VALUE[$key]}" value
      case "$scope" in
        global)  commands+=(set-option -q -g "$name" "$value") ;;
        session) commands+=(set-option -q -t "$target" "$name" "$value") ;;
        window)  commands+=(set-option -q -w -t "$target" "$name" "$value") ;;
      esac
    else
      case "$scope" in
        global)  commands+=(set-option -qu -g "$name") ;;
        session) commands+=(set-option -qu -t "$target" "$name") ;;
        window)  commands+=(set-option -qu -w -t "$target" "$name") ;;
      esac
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
  if [[ -n "$redraw" ]]; then tmux refresh-client -S 2>/dev/null || true; fi
}

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
#   * public values are user-configured global input; exact session values exist
#     only while palette/layout files are being captured.
#   * private state is airline-owned and scoped to its actual owner: session or
#     window. Stable badge names are embedded in tmux #{?…} selectors.

# --- public configuration: durable input exists at global scope only ---
pub_get   () { opt_get_global   "@airline-$1"; }        # <key>
pub_set   () { opt_set_global   "@airline-$1" "$2"; }   # <key> <value>
pub_unset () { opt_unset_global "@airline-$1"; }        # <key>
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
cfg_unset_session () { prv_unset_session "$1" "config-$2"; }       # <session> <key>

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
redraw () {
  if [[ -n "$_AIRLINE_OPT_WORKSPACE" ]]; then _AIRLINE_OPT_REDRAW=1
  else tmux refresh-client -S 2>/dev/null || true; fi
}

# Load a tmux source file (used for palette files).
source_file () {
  _opt_workspace_flush || return
  tmux source-file "$1" || return
  _opt_workspace_reload
}
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
hook_unset () { tmux set-hook -gu "$1"; }

# Run one callback while holding a lock scoped to an airline state owner and
# namespace. Higher layers declare the transaction boundary without knowing the
# wait-for mechanism, channel naming, or cleanup rules. Transactions deliberately
# do not nest: tmux locks are not reentrant, so nesting would deadlock.
_AIRLINE_TRANSACTION_CHANNEL=""
_AIRLINE_TRANSACTION_SCOPE=""
_AIRLINE_TRANSACTION_TARGET=""
_AIRLINE_TRANSACTION_NAMESPACE=""

_transaction_marker_name () { printf '@airline--transaction-%s' "$1"; }

_transaction_channel () {   # <session|window> <canonical-target> <namespace>
  local scope="$1" target="$2" namespace="$3"
  target="${target//[^a-zA-Z0-9_-]/_}"
  printf 'airline-%s-%s-%s' "$scope" "$target" "$namespace"
}

# Acquire/release update the owner marker in the SAME tmux command sequence as
# wait-for. If the shell disappears between commands, tmux still completes both,
# so every held Airline lock remains discoverable.
_transaction_acquire () {   # <scope> <target> <namespace> <channel> <metadata>
  local scope="$1" target="$2" namespace="$3" channel="$4" metadata="$5"
  local marker; marker="$(_transaction_marker_name "$namespace")"
  case "$scope" in
    session) tmux wait-for -L "$channel" \; set-option -q    -t "$target" "$marker" "$metadata" ;;
    window)  tmux wait-for -L "$channel" \; set-option -q -w -t "$target" "$marker" "$metadata" ;;
  esac || { tmux wait-for -U "$channel" 2>/dev/null || true; return 1; }
}

_transaction_release () {   # <scope> <target> <namespace> <channel>
  local scope="$1" target="$2" namespace="$3" channel="$4"
  local marker; marker="$(_transaction_marker_name "$namespace")"
  case "$scope" in
    session) tmux set-option -qu    -t "$target" "$marker" \; wait-for -U "$channel" ;;
    window)  tmux set-option -qu -w -t "$target" "$marker" \; wait-for -U "$channel" ;;
  esac
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

_with_transaction () (   # <session|window> <target> <namespace> <callback> [<arg>...]
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

# Outstanding transaction markers are the observable lock registry. Output is
# tab-delimited: <scope> <owner> <namespace> <active|stale> <pid> <age-seconds>.
_transaction_list_owner () {   # <session|window> <target>
  local scope="$1" target="$2" raw name metadata namespace pid started now age state
  case "$scope" in
    session) raw="$(_opt_list -t "$target")" ;;
    window)  raw="$(_opt_list -w -t "$target")" ;;
  esac
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
  for target in $(list_sessions); do _transaction_list_owner session "$target"; done
  for target in $(tmux list-windows -a -F '#{window_id}'); do
    case "$seen" in *" $target "*) continue ;; esac
    seen+="$target "
    _transaction_list_owner window "$target"
  done
}

# Clear one STALE marker and its wait-for channel. A live owner is never forcibly
# unlocked: its later cleanup could otherwise release a successor's lock.
transaction_clear () {   # <session|window> <target> <namespace>
  local scope="$1" target="$2" namespace="$3" metadata pid channel marker
  [[ "$namespace" =~ ^[a-zA-Z0-9_-]+$ ]] || return 2
  case "$scope" in
    session) target="$(resolve_session_target "$target")" || return 2 ;;
    window)  target="$(resolve_window "$target")" || return 2 ;;
    *) return 2 ;;
  esac
  marker="$(_transaction_marker_name "$namespace")"
  case "$scope" in
    session) metadata="$(opt_get_session "$target" "$marker")" ;;
    window)  metadata="$(opt_get_window "$target" "$marker")" ;;
  esac
  [[ -n "$metadata" ]] || return 3
  pid="${metadata%%:*}"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 2
  kill -0 "$pid" 2>/dev/null && return 4
  channel="$(_transaction_channel "$scope" "$target" "$namespace")"
  _transaction_release "$scope" "$target" "$namespace" "$channel"
}

# Key bindings — a primitive for callers; airline itself binds no keys (a user wires
# their own, e.g. `bind F12 run "#{@airline-cli} state toggle"`). <table> is a key-table.
key_bind   () { tmux bind-key   -T "$1" "$2" "$3"; }
key_unbind () { tmux unbind-key -T "$1" "$2"; }

# vim: ft=bash
