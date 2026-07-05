#!/usr/bin/env bash
#
# api.sh — the CLI command handlers (the logic behind every verb).
#
# `airline` is just the parser/dispatcher; the work lives here. Each handler owns
# input validation (the one place input is checked — against render.sh's predicates)
# and then drives the layers: opt_* / coll_* to mutate state, `render` to produce the
# bar. Sourced on top of tmux.sh + collections.sh + render.sh.
#
# The verb grammar splits on the state model. Dynamic nouns (status, health) are live
# and scriptable: `set X v` / `clear X` / `show [X]` — write + re-project a badge +
# redraw. Static config nouns (palette, segment) are read-only at the CLI: their values
# are public @airline-* options the user writes the idiomatic tmux way (`set -g`, a
# palette file, `.tmux.conf`) — no `set`/`clear`, only `show` for discovery; `apply`
# bakes whatever those options currently hold.

# shellcheck shell=bash

if ! declare -F render >/dev/null; then
  printf 'api.sh: load render.sh (and its layers) first\n' >&2
  return 1 2>/dev/null || exit 1
fi

die () { printf 'airline: %s\n' "$*" >&2; exit 2; }

# Self-documenting help. Each documented case arm carries its own one-line help as a
# trailing `#| <args> — note` marker (see the dispatcher and the cmd_* handlers). Help
# is extracted from the source with sed — no separate text to keep in sync — and, like
# `show`, iterates the top-level commands then recurses into each noun.

# Print a source range's #|-annotated arms as "  verb   help". <file> <start> <end>.
_help_arms () {
  sed -n "/$2/,/$3/{ s/^[[:space:]]*\([a-zA-Z_][a-zA-Z0-9_-]*\))[^#]*#|[[:space:]]*\(.*\)/\1\t\2/p; }" "$1" \
    | while IFS=$'\t' read -r v d; do printf '  %-9s %s\n' "$v" "$d"; done
}

# One noun's verbs — the recursion target (also `<noun> help`).
_help_noun () {   # <noun>
  printf '%s:\n' "$1"
  _help_arms "$AIRLINE_DIR/api.sh" "^cmd_$1 () {" '^}'
}

usage () {
  printf 'airline — tmux-airline CLI\n\n'
  printf 'Commands:\n'
  _help_arms "$AIRLINE_DIR/airline" '^case ' '^esac'
  local n
  for n in palette segment adapter layout state status health; do
    printf '\n'; _help_noun "$n"
  done
  printf '\n  use loads a bare name from a registered dir; register blesses a location.\n'
  printf '  --transient clears a signal when you focus away from its window.\n'
}

# One "label   value" row — the single home for the `show` column width, so every
# noun's show and the top-level summary align identically.
_show_row () { printf '%-12s %s\n' "$1" "$2"; }

#-----------------------------------------------------------------------------#
# Lifecycle
#-----------------------------------------------------------------------------#

# True when no segment slot is set yet (a fresh install) — gates default seeding.
_segments_unset () {
  local s
  for s in "${AIRLINE_SEGMENT_SLOTS[@]}"; do
    [[ -n "$(pub_get "segment-$s")" ]] && return 1
  done
  return 0
}

# Bootstrap. Publish the CLI path and, on first run, seed defaults behind a sentinel
# (without clobbering user config or runtime state on a reload); then render.
cmd_init () {
  # The CLI path is the ONE published (public) option — the bootstrap handle, since a
  # script can't call the API to discover where the API lives. Everything else about
  # airline's state is read through the CLI, never a private option. Airline binds no
  # keys — a user wires their own (e.g. `bind F12 run "#{@airline-cli} state toggle"`).
  pub_set "$AIRLINE_KEY_CLI" "$AIRLINE_DIR/airline"

  # Register airline's own shipped config dirs on each loadable kind's search path.
  # (segment is not loadable — it's public options a layout sets, or the user sets.)
  _path_register_self palette "$AIRLINE_DIR/palettes"
  _path_register_self adapter "$AIRLINE_DIR/adapters"
  _path_register_self layout  "$AIRLINE_DIR/layouts"

  # First run only (sentinel): apply the default of each axis the user hasn't set —
  # the default PALETTE if no palette is present, the default LAYOUT (which brings its
  # own segments) if no segments are. `default` is a name on the search path, so a
  # user's own `default` (registered earlier) wins. Renders deferred to the final one.
  if [[ "$(prv_get_global "$AIRLINE_KEY_DEFAULTS")" != 1 ]]; then
    [[ -z "$(pub_get inner-bg)" ]] && _load_config palette default
    _segments_unset && _apply_layout adaptive
    prv_set_global "$AIRLINE_KEY_DEFAULTS" 1
  fi
  render || true
}

# Render, unless we're mid-layout (a layout defers to one redraw at the end via a
# local _AIRLINE_DEFER that dynamic scoping makes visible to the nested use handlers).
_render () { [[ -n "${_AIRLINE_DEFER:-}" ]] && return 0; render || true; }

# apply: re-run the active layout (re-applies its adapters against the current palette
# and re-sets its segments), then render. This is the re-apply engine — a palette swap is
# `palette use X` (or a raw set) followed by apply.
cmd_apply () {
  local lay; lay="$(prv_get_global layout)"
  [[ -n "$lay" && -n "$(_layout_file "$lay")" ]] && _apply_layout "$lay"
  render || true
}

# Top-level `airline show`: the active configuration. The non-noun globals first (the
# bootstrap handle, lifecycle state, and the search paths), then a recursion into each
# CONFIG noun's own `show` — the noun reports its own active state, so nothing is printed
# twice (a palette/layout name shows once, inside its section). The dynamic per-window
# nouns (status/health) are NOT global config, so they're excluded — inspect them with
# `status show` / `health show`.
cmd_show () {
  _show_row cli   "$(pub_get cli)"              # the one public (bootstrap) handle
  _show_row state "$(_state_word)"              # lifecycle (active | suspended)
  printf '\npaths:\n'                           # where `use` resolves, priority order
  local k
  for k in palette adapter layout; do
    _show_row "$k" "$(coll_members_global "$(_path_ns "$k")")"
  done
  printf '\npalette:\n'; cmd_palette show
  printf '\nsegment:\n'; cmd_segment show
  printf '\nadapter:\n'; cmd_adapter show
  printf '\nlayout:\n';  cmd_layout show
}

#-----------------------------------------------------------------------------#
# Search path — the `use` mechanism (notes.md §use)
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
_path_register_self () {   # <kind> <dir>
  [[ -d "$2" ]] && coll_register_global "$(_path_ns "$1")" "$2"
}

# Resolve a bare <name> to the first hit walking the kind's path. Names are simple
# (no '/'): `use` only reaches BLESSED locations — `register` a dir to add one; there
# is no literal-path escape hatch (we don't load/execute from arbitrary paths).
# Echoes the file path, empty when unresolved.
_path_resolve () {   # <kind> <name>
  local kind="$1" name="$2" dir
  [[ "$name" == */* ]] && return          # not a bare name → unresolvable here
  for dir in $(coll_members_global "$(_path_ns "$kind")"); do
    [[ -f "$dir/$name" ]] && { printf '%s' "$dir/$name"; return; }
  done
}

# List every bare name resolvable on the kind's path — the catalog `use` chooses from.
# One name per line, deduped in path order (a shadowing user dir collapses with the
# shipped name it overrides). The read-side counterpart to _path_resolve; the shared
# core of every noun's `available` verb (palette / adapter / layout).
_path_available () {   # <kind>
  local kind="$1" dir f name seen=" "
  for dir in $(coll_members_global "$(_path_ns "$kind")"); do
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
_register () {   # <kind> <dir>
  local kind="$1" dir="${2:-}"
  [[ -n "$dir" ]] || die "$kind register: need <dir>"
  [[ -d "$dir" ]] || die "$kind register: no such directory: $dir"
  coll_prepend_global "$(_path_ns "$kind")" "$dir"
}

# Resolve each bare name on the kind's path, source the tmux conf, record it active
# (@airline--<kind>). NO render — the caller renders: `palette use` re-applies via
# `apply`, so a palette swap re-runs the layout and re-colours its adapters. Only
# `palette` is loadable now (segment is set by layouts), but the mechanism stays generic.
_load_config () {   # <kind> <name...>
  local kind="$1"; shift
  [[ $# -gt 0 ]] || die "$kind use: need <name>"
  local name file
  for name in "$@"; do                    # multi-target: later files compose over earlier
    [[ "$name" != */* ]] || die "$kind use: '$name' — use a bare name (register a dir to add locations)"
    file="$(_path_resolve "$kind" "$name")"
    [[ -n "$file" ]] || die "$kind use: '$name' not found on the $kind path"
    source_file "$file"
    prv_set_global "$kind" "$name"        # record the active selection (last wins)
  done
}

# adapter use <name>: DYNAMIC — an adapter is a bash snippet that sets a plugin's
# @<plugin>-* options from the current palette. Resolve it on the adapter path, load
# PALETTE, then `source` the snippet (bash, not source-file) so it can read PALETTE
# and call opt_set_global. Reached through a layout (piece C); the layout's stored
# path is re-run on a palette change, which re-runs this and re-applies the colours.
# Resolve <path> to an absolute path (dir resolved via cd+pwd; the file itself is
# checked by the caller). `load` records this so a later `apply`, running from another
# cwd, still finds it.
_abspath () {   # <path> → absolute
  local dir base
  dir="$(dirname -- "$1")"; base="$(basename -- "$1")"
  printf '%s/%s' "$(cd -- "$dir" 2>/dev/null && pwd)" "$base"
}

# Run one adapter file: load PALETTE, then source the snippet so it can set the
# plugin's @<plugin>-* options from PALETTE. The shared core of `use` and `load`.
_source_adapter () {   # <file>
  _palette_load
  # shellcheck source=/dev/null
  source "$1"
}

# adapter use <name...>: resolve each bare name on the adapter path and run it, then
# record it in the active set (`adapters` collection) for `adapter show`.
_apply_adapter () {   # <name...>
  [[ $# -gt 0 ]] || die "adapter use: need <name>"
  local name file
  for name in "$@"; do
    [[ "$name" != */* ]] || die "adapter use: '$name' — bare name (or 'adapter load <path>')"
    file="$(_path_resolve adapter "$name")"
    [[ -n "$file" ]] || die "adapter use: '$name' not found on the adapter path"
    _source_adapter "$file"
    coll_register_global adapters "$name"   # record as applied (idempotent)
  done
}

# adapter load <path>: run a one-off adapter script by path (no path walk). Unlike
# `layout load`, the record is for DISCOVERY, not re-run: `apply` re-runs the layout,
# which re-invokes its adapters — so we keep only the applied name (the basename) for
# `adapter show`, not the path. A durable custom adapter lives in a layout that
# `adapter load`s it. The user owns the file (it sources arbitrary bash).
_load_adapter () {   # <path>
  local path="${1:-}"; [[ -n "$path" ]] || die "adapter load: need <path>"
  local abs; abs="$(_abspath "$path")"
  [[ -f "$abs" ]] || die "adapter load: no such file: $path"
  _source_adapter "$abs"
  coll_register_global adapters "${abs##*/}"   # record the applied name (idempotent)
}

# Resolve a layout HANDLE to a file: a bare name (from `use`/default) → the search
# path; a path (from `load`, recorded absolute) → itself. The slash tells them apart —
# reusing the invariant that names never contain '/'.
_layout_file () {   # <handle> → file (empty if unresolved)
  if [[ "$1" == */* ]]; then [[ -f "$1" ]] && printf '%s' "$1"
  else _path_resolve layout "$1"; fi
}

# A layout is a SHELL SCRIPT. Record <handle> as active, then EXECUTE the file with
# `airline` on PATH and AIRLINE_DIR in the env — so it composes by calling
# `airline adapter use …` (dynamic) and writing its segment options directly with
# `$AIRLINE_TMUX set -g` (segments are just options), and may `source` helpers (e.g.
# the TPM probe). `apply` re-runs the recorded handle — the re-apply engine.
#
# Orthogonality (a layout must not set the palette) is a CONVENTION, not enforced. The
# re-entrancy guard makes a violation benign: while a layout runs, @airline--applying is
# set, so a nested `apply`/`palette use` renders but does NOT re-enter the layout — no
# apply→layout→apply loop. Cleared even if the script fails (|| true).
_apply_layout () {   # <handle>  (bare name, or absolute path from load)
  [[ "$(prv_get_global applying)" == 1 ]] && return 0
  local handle="${1:-}" file
  file="$(_layout_file "$handle")"
  [[ -n "$file" ]] || die "layout: '$handle' not found"
  prv_set_global layout "$handle"
  prv_set_global applying 1
  _clear_segments        # clean slate — the layout owns the arrangement, sets what it wants
  _clear_adapters        # …and owns its adapter set — repopulated by its `adapter use` calls
  export AIRLINE_DIR AIRLINE_CLI="$AIRLINE_DIR/airline"   # the script sources helpers / calls airline
  # AIRLINE_TMUX (the seam, defaulted to plain tmux) lets a layout set its segment
  # options directly and cheaply with `$AIRLINE_TMUX set -g` — no airline subprocess.
  # _AIRLINE_DEFER=1 reaches the nested `airline …` calls via the env, so their renders
  # are suppressed (_render); the caller renders ONCE after this returns.
  AIRLINE_TMUX="${AIRLINE_TMUX:-tmux}" _AIRLINE_DEFER=1 PATH="$AIRLINE_DIR:$PATH" bash "$file" || true
  prv_set_global applying 0
}

# Unset every segment slot. The clean slate a layout starts from, so it only sets what
# it wants and a switch leaves nothing stale. Safe because init applies a default layout
# ONLY when no segments are set — a "define the options yourself" user never runs a
# layout, so this never wipes their directly-set segment options.
_clear_segments () {
  local s; for s in "${AIRLINE_SEGMENT_SLOTS[@]}"; do pub_unset "segment-$s"; done
}

# Drop every recorded active adapter — the clean slate a layout starts from, so the
# active set reflects only what the current layout applied. Ad-hoc `adapter use` outside
# a layout just appends; only a layout switch clears (mirrors _clear_segments).
_clear_adapters () {
  local a; for a in $(coll_members_global adapters); do coll_unregister_global adapters "$a"; done
}

# layout use <name>: curated — a bare name on the layout path.
_layout_use () {   # <name>
  local name="${1:-}"; [[ -n "$name" ]] || die "layout use: need <name>"
  [[ "$name" != */* ]] || die "layout use: '$name' — bare name (or 'layout load <path>')"
  _apply_layout "$name"
}

# layout load <path>: one-off — run a layout script by path, recording the ABSOLUTE
# path so `apply` re-runs it from any cwd.
_layout_load () {   # <path>
  local path="${1:-}"; [[ -n "$path" ]] || die "layout load: need <path>"
  local abs; abs="$(_abspath "$path")"
  [[ -f "$abs" ]] || die "layout load: no such file: $path"
  _apply_layout "$abs"
}

# layout show: bare → the active layout summarized (its `name` and the resolved file
# `path`, labeled — human); `show name` → the recorded handle, raw; `show path` → the
# resolved file, raw (handy for a `load`ed layout, whose handle already IS a path).
_layout_show () {   # [name|path]
  local x="${1:-}" handle; handle="$(prv_get_global layout)"
  case "$x" in
    name) printf '%s\n' "$handle" ;;
    path) printf '%s\n' "$(_layout_file "$handle")" ;;
    "")   _show_row name "$handle"
          _show_row path "$(_layout_file "$handle")" ;;
    *)    die "layout show: unknown field '$x' (name | path)" ;;
  esac
}

# The active/suspended state. `suspend` mutes the palette (the derived flat look, via
# _palette_load) and traps the prefix so keys pass through — the nested-session signal
# "this tmux is dormant." `resume` restores. The flat/vibrant colour is derived, not a
# second palette. State is private; read it through `state show`, not the option.
_state_word () { [[ "$(prv_get_global "$AIRLINE_KEY_SUSPENDED")" == 1 ]] && echo suspended || echo active; }

_state_set () {   # <1=suspended|0=active>
  prv_set_global "$AIRLINE_KEY_SUSPENDED" "$1"
  if [[ "$1" == 1 ]]; then
    opt_set_global prefix None
    opt_set_global key-table off
  else
    opt_unset_global prefix
    opt_unset_global key-table
  fi
  render || true
}

cmd_state () {
  local verb="${1:-}"; shift || true
  case "$verb" in
    suspend) _state_set 1 ;;   #| mute the palette + trap the prefix (session dormant)
    resume)  _state_set 0 ;;   #| restore vibrant colours + release the prefix
    toggle)  if [[ "$(prv_get_global "$AIRLINE_KEY_SUSPENDED")" == 1 ]]; then _state_set 0; else _state_set 1; fi ;;   #| flip active/suspended
    show)    _state_word ;;    #| print the current state (active | suspended)
    ""|-h|--help|help) _help_noun state ;;
    *) die "unknown state command: $verb" ;;
  esac
}

#-----------------------------------------------------------------------------#
# Transient (consume-on-view)
#-----------------------------------------------------------------------------#

_ensure_unfocus_hook () {
  opt_set_global focus-events on
  hook_set "pane-focus-out[90]" "run-shell -b \"$AIRLINE_DIR/airline _unfocus #{window_id}\""
}

# Drop every transient contributor on <window>, then re-project both badges once.
cmd_unfocus () {
  local win="${1:-}"; [[ -n "$win" ]] || return 0
  local changed="" ns key f1 f2
  for ns in status health; do
    for key in $(coll_members_window "$win" "$ns"); do
      IFS=$'\t' read -r f1 f2 <<< "$(coll_get_window "$win" "$ns" "$key")"
      [[ "$f2" == 1 ]] && { coll_unregister_window "$win" "$ns" "$key"; changed=1; }
    done
  done
  [[ -n "$changed" ]] || return 0
  status_project "$win" || true
  health_project "$win" || true
  redraw
}

#-----------------------------------------------------------------------------#
# Dynamic nouns — status & health (live: write + re-project a badge + redraw)
#-----------------------------------------------------------------------------#

_signal_set () {   # <ns> <validator> <key> <value> [--transient] [-t <win>]
  local ns="$1" valid="$2"; shift 2
  local key="" value="" transient="" win="" ; local -a pos=()
  while (( $# )); do
    case "$1" in
      --transient) transient=1; shift ;;
      -t)          win="${2:-}"; shift 2 ;;
      *)           pos+=("$1"); shift ;;
    esac
  done
  key="${pos[0]:-}"; value="${pos[1]:-}"
  [[ -n "$key" ]] || die "$ns set: need <key>"
  "$valid" "$value" || die "$ns set: invalid value '$value'"
  [[ -n "$win" ]] || win="$(current_window)"
  coll_set_window "$win" "$ns" "$key" "$value" "$transient"
  [[ -n "$transient" ]] && _ensure_unfocus_hook
  "${ns}_project" "$win" && redraw
  return 0
}

_signal_clear () {   # <ns> <key> [-t <win>]
  local ns="$1"; shift
  local key="" win=""
  while (( $# )); do
    case "$1" in -t) win="${2:-}"; shift 2 ;; *) key="$1"; shift ;; esac
  done
  [[ -n "$key" ]] || die "$ns clear: need <key>"
  [[ -n "$win" ]] || win="$(current_window)"
  coll_unregister_window "$win" "$ns" "$key"
  "${ns}_project" "$win" && redraw
  return 0
}

_signal_show () {   # <ns> [<key>] [-t <win>]
  local ns="$1"; shift
  local key="" win="" f1 f2 k
  while (( $# )); do
    case "$1" in -t) win="${2:-}"; shift 2 ;; *) key="$1"; shift ;; esac
  done
  [[ -n "$win" ]] || win="$(current_window)"
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

cmd_status () {
  local verb="${1:-}"; shift || true
  case "$verb" in
    set)   _signal_set   status _status_level_valid "$@" ;;   #| <key> <active|result|attention> [--transient] [-t <win>]
    clear) _signal_clear status "$@" ;;                       #| <key> [-t <win>]
    show)  _signal_show  status "$@" ;;                       #| [<key>] [-t <win>] — a window's app-status
    ""|-h|--help|help) _help_noun status ;;
    *) die "unknown status command: $verb" ;;
  esac
}

cmd_health () {
  local verb="${1:-}"; shift || true
  case "$verb" in
    set)   _signal_set   health _health_severity_valid "$@" ;;   #| <key> <ok|alert|stress> [--transient] [-t <win>]
    clear) _signal_clear health "$@" ;;                          #| <key> [-t <win>]
    show)  _signal_show  health "$@" ;;                          #| [<key>] [-t <win>] — a window's health
    ""|-h|--help|help) _help_noun health ;;
    *) die "unknown health command: $verb" ;;
  esac
}

#-----------------------------------------------------------------------------#
# Static config nouns — palette & segment (public @airline-* options, read-only here)
#-----------------------------------------------------------------------------#
# Values are written the idiomatic tmux way (`set -g @airline-…`, a palette file, or
# `.tmux.conf`); the CLI only *reads* them back for discovery. `apply` bakes whatever
# the options currently hold, so the write path never has to route through here.

# <key-prefix> is the bare-key prefix WITHIN the public namespace: "" for palette
# (the key is the element) or "segment-" for segments. pub_* applies the @airline-
# prefix; api never spells it.
_static_show () {   # <key-prefix> <validator> <list-array-name> [<X>]
  local keypfx="$1" valid="$2" listname="$3" x="${4:-}"
  if [[ -n "$x" ]]; then
    "$valid" "$x" || die "show: unknown target '$x'"
    pub_get "${keypfx}${x}"
    return 0
  fi
  local -n all="$listname"; local k
  for k in "${all[@]}"; do _show_row "$k" "$(pub_get "${keypfx}${k}")"; done
}

# palette show: bare → the whole palette (its `name` field + every element, labeled —
# a human summary, don't parse it); `show name` → the active palette name, raw (the
# scripting read, replaces the old `current`); `show <element>` → one element, raw.
# `name` is a VIRTUAL field: it lives in the private selection, not a public option.
_palette_show () {   # [name|<element>]
  local x="${1:-}"
  [[ "$x" == name ]] && { prv_get_global palette; return 0; }
  [[ -z "$x" ]] && _show_row name "$(prv_get_global palette)"
  _static_show "" _palette_element_valid AIRLINE_PALETTE_ELEMENTS "$x"
}

cmd_palette () {
  # A palette element is a public option (@airline-<element>); override one directly
  # with `set -g` or swap the whole set with `use`. Like segment, the per-element write
  # path is read-only here — `show` is the discovery surface (bare for humans,
  # `show <field>` a raw value for scripts; `show name` is the active-palette read).
  local verb="${1:-}"; shift || true
  case "$verb" in
    show)      _palette_show "$@" ;;                    #| [name|<element>] — summary, or one field raw (`show name` for scripts)
    use)       _load_config palette "$@"; cmd_apply ;;  #| <name> — load a palette (re-applies the layout)
    available) _path_available palette ;;               #| the palettes you can `use` (on the path)
    register)  _register palette "$@" ;;                #| <dir> — add a palette search dir
    ""|-h|--help|help) _help_noun palette ;;
    *) die "unknown palette command: $verb" ;;
  esac
}

cmd_segment () {
  # A segment is a public option; write it directly with `set -g` (from a layout or your
  # own config). This noun is read-only — `show` is the discovery surface (bare `show`
  # lists every slot).
  local verb="${1:-}"; shift || true
  case "$verb" in
    show)  _static_show  "segment-" _segment_slot_valid AIRLINE_SEGMENT_SLOTS "$@" ;;   #| [<slot>] — read one or all (segments are written with `set -g`, not here)
    ""|-h|--help|help) _help_noun segment ;;
    *) die "unknown segment command: $verb" ;;
  esac
}

# adapter show: iterate the active set — the adapters currently applied (recorded by
# every `use`/`load`), one per line. Bare-only, unlike palette/status: an adapter is a
# valueless name, so there is no per-member `show <x>` value to return. This is the
# MULTI-active noun — its "what's on" answer is a LIST, not a scalar `name`. (What you
# *could* apply is a different axis — `adapter available`, over the search path.)
_adapter_show () {
  local a; for a in $(coll_members_global adapters); do printf '%s\n' "$a"; done
}

cmd_adapter () {
  local verb="${1:-}"; shift || true
  case "$verb" in
    use)       _apply_adapter "$@"; _render ;;      #| <name> — apply the palette to a plugin
    load)      _load_adapter "$@"; _render ;;       #| <path> — apply a one-off adapter script
    show)      _adapter_show ;;                     #| the applied adapters, one per line
    available) _path_available adapter ;;           #| the adapters you can `use` (on the path)
    register)  _register adapter "$@" ;;            #| <dir> — add an adapter search dir
    ""|-h|--help|help) _help_noun adapter ;;
    *) die "unknown adapter command: $verb" ;;
  esac
}

cmd_layout () {
  local verb="${1:-}"; shift || true
  case "$verb" in
    use)       _layout_use "$@"; render || true ;;   #| <name> — run a composition (adapters + segments)
    load)      _layout_load "$@"; render || true ;;  #| <path> — run a one-off layout script (records it)
    show)      _layout_show "$@" ;;                   #| [name|path] — the active layout (summary, or one field raw)
    available) _path_available layout ;;              #| the layouts you can `use` (on the path)
    register)  _register layout "$@" ;;               #| <dir> — add a layout search dir
    ""|-h|--help|help) _help_noun layout ;;
    *) die "unknown layout command: $verb" ;;
  esac
}

# vim: ft=bash
