#!/usr/bin/env bash
#
# layout.sh — palette, adapter, segment, and executable-layout behavior.
#
# Layouts remain trusted child programs. They write public segment options through
# AIRLINE_TMUX and delegate adapter composition through the installed airline shim.

# shellcheck shell=bash

if ! declare -F render >/dev/null; then
  printf 'layout.sh: load render.sh (and its layers) first\n' >&2
  return 1 2>/dev/null || exit 1
fi

_load_config () {   # <session> <kind> <name...>
  local session="$1" kind="$2"; shift 2
  [[ $# -gt 0 ]] || die "$kind use: need <name>"
  local name file
  for name in "$@"; do                    # multi-target: later files compose over earlier
    [[ "$name" != */* ]] || die "$kind use: '$name' — use a bare name (register a dir to add locations)"
    file="$(_path_resolve "$session" "$kind" "$name")"
    [[ -n "$file" ]] || die "$kind use: '$name' not found on the $kind path"
    source_file_session "$session" "$file"
    prv_set_session "$session" "$kind" "$name" # active selection (last wins)
  done
}

# adapter use <name>: DYNAMIC — an adapter is a bash snippet that sets a plugin's
# @<plugin>-* options from the current palette. Resolve it on the adapter path, load
# PALETTE, then `source` the snippet (bash, not source-file) so it can read PALETTE
# and call opt_set_session. Reached through a layout (piece C); the layout's stored
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
_source_adapter () {   # <session> <file>
  # AIRLINE_SESSION is consumed by the sourced adapter contract.
  # shellcheck disable=SC2034
  local AIRLINE_SESSION="$1" file="$2"
  _palette_load
  # shellcheck source=/dev/null
  source "$file"
}

# adapter use <name...>: resolve each bare name on the adapter path and run it, then
# record it in the active set (`adapters` collection) for `adapter show`.
_apply_adapter () {   # <session> <name...>
  local session="$1"; shift
  [[ $# -gt 0 ]] || die "adapter use: need <name>"
  local name file
  for name in "$@"; do
    [[ "$name" != */* ]] || die "adapter use: '$name' — bare name (or 'adapter load <path>')"
    file="$(_path_resolve "$session" adapter "$name")"
    [[ -n "$file" ]] || die "adapter use: '$name' not found on the adapter path"
    _source_adapter "$session" "$file"
    coll_register_session "$session" adapters "$name" # applied in this session
  done
}

# adapter load <path>: run a one-off adapter script by path (no path walk). Unlike
# `layout load`, the record is for DISCOVERY, not re-run: `apply` re-runs the layout,
# which re-invokes its adapters — so we keep only the applied name (the basename) for
# `adapter show`, not the path. A durable custom adapter lives in a layout that
# `adapter load`s it. The user owns the file (it sources arbitrary bash).
_load_adapter () {   # <session> <path>
  local session="$1" path="${2:-}"; [[ -n "$path" ]] || die "adapter load: need <path>"
  local abs; abs="$(_abspath "$path")"
  [[ -f "$abs" ]] || die "adapter load: no such file: $path"
  _source_adapter "$session" "$abs"
  coll_register_session "$session" adapters "${abs##*/}"
}

# Resolve a layout HANDLE to a file: a bare name (from `use`/default) → the search
# path; a path (from `load`, recorded absolute) → itself. The slash tells them apart —
# reusing the invariant that names never contain '/'.
_layout_file () {   # <session> <handle> → file (empty if unresolved)
  local session="$1" handle="$2"
  if [[ "$handle" == */* ]]; then [[ -f "$handle" ]] && printf '%s' "$handle"
  else _path_resolve "$session" layout "$handle"; fi
}

# A layout is a SHELL SCRIPT. Record <handle> as active, then EXECUTE the file with
# `airline` on PATH and AIRLINE_DIR in the env — so it composes by calling
# `airline adapter use …` (dynamic) and writing its segment options directly with
# `$AIRLINE_TMUX set -t "$AIRLINE_SESSION"` (segments are just options), and may
# `source` helpers (e.g.
# the TPM probe). `apply` re-runs the recorded handle — the re-apply engine.
#
# Orthogonality (a layout must not set the palette) is a CONVENTION, not enforced. The
# re-entrancy guard makes a violation benign: while a layout runs, @airline--applying is
# set, so a nested `apply`/`palette use` renders but does NOT re-enter the layout — no
# apply→layout→apply loop. A failed script is contained, surfaced as a session
# problem, and cleared automatically after a later successful application.
_apply_layout () {   # <session> <handle>  (bare name, or absolute path from load)
  local session="$1" handle="${2:-}" file rc=0
  local layout_dir="$AIRLINE_DIR" layout_cli="$AIRLINE_DIR/airline.sh" layout_path="$AIRLINE_DIR:$PATH"
  [[ "$(prv_get_session "$session" applying)" == 1 ]] && return 0
  file="$(_layout_file "$session" "$handle")"
  [[ -n "$file" ]] || die "layout: '$handle' not found"
  prv_set_session "$session" layout "$handle"
  prv_set_session "$session" applying 1
  _clear_segments "$session" # clean slate — the layout owns the arrangement
  _clear_adapters "$session" # …and owns its adapter set
  # AIRLINE_TMUX (the seam, defaulted to plain tmux) lets a layout set its segment
  # options directly and cheaply with an explicit session target — no airline subprocess.
  # _AIRLINE_DEFER=1 reaches the nested `airline …` calls via the env, so their renders
  # are suppressed (_render); the caller renders ONCE after this returns.
  AIRLINE_DIR="$layout_dir" AIRLINE_CLI="$layout_cli" \
    AIRLINE_SESSION="$session" AIRLINE_TMUX="${AIRLINE_TMUX:-tmux}" \
    _AIRLINE_DEFER=1 PATH="$layout_path" bash "$file" || rc=$?
  prv_set_session "$session" applying 0
  if (( rc == 0 )); then
    _problem_store "$session" airline-layout ok "" || true
  else
    _problem_store "$session" airline-layout fail "layout '$handle' exited with status $rc" || true
  fi
}

# Unset every segment slot. The clean slate a layout starts from, so it only sets what
# it wants and a switch leaves nothing stale. Safe because init applies a default layout
# ONLY when no segments are set — a "define the options yourself" user never runs a
# layout, so this never wipes their directly-set segment options.
_clear_segments () {   # <session>
  local session="$1" s; for s in "${AIRLINE_SEGMENT_SLOTS[@]}"; do
    pub_set_session "$session" "segment-$s" ""
  done
}

# Drop every recorded active adapter — the clean slate a layout starts from, so the
# active set reflects only what the current layout applied. Ad-hoc `adapter use` outside
# a layout just appends; only a layout switch clears (mirrors _clear_segments).
_clear_adapters () {   # <session>
  local session="$1" a
  for a in $(coll_members_session "$session" adapters); do
    coll_unregister_session "$session" adapters "$a"
  done
}

# layout use <name>: curated — a bare name on the layout path.
_layout_use () {   # <session> <name>
  local session="$1" name="${2:-}"; [[ -n "$name" ]] || die "layout use: need <name>"
  [[ "$name" != */* ]] || die "layout use: '$name' — bare name (or 'layout load <path>')"
  _apply_layout "$session" "$name"
}

# layout load <path>: one-off — run a layout script by path, recording the ABSOLUTE
# path so `apply` re-runs it from any cwd.
_layout_load () {   # <session> <path>
  local session="$1" path="${2:-}"; [[ -n "$path" ]] || die "layout load: need <path>"
  local abs; abs="$(_abspath "$path")"
  [[ -f "$abs" ]] || die "layout load: no such file: $path"
  _apply_layout "$session" "$abs"
}

# layout show: bare → the active layout summarized (its `name` and the resolved file
# `path`, labeled — human); `show name` → the recorded handle, raw; `show path` → the
# resolved file, raw (handy for a `load`ed layout, whose handle already IS a path).
_layout_show () {   # <session> [name|path]
  local session="$1" x="${2:-}" handle; handle="$(prv_get_session "$session" layout)"
  case "$x" in
    name) printf '%s\n' "$handle" ;;
    path) printf '%s\n' "$(_layout_file "$session" "$handle")" ;;
    "")   _show_row name "$handle"
          _show_row path "$(_layout_file "$session" "$handle")" ;;
    *)    die "layout show: unknown field '$x' (name | path)" ;;
  esac
}

#-----------------------------------------------------------------------------#
# Static config nouns — palette & segment (public @airline-* options, read-only here)
#-----------------------------------------------------------------------------#
# Global defaults are written the idiomatic tmux way (`set -g @airline-…` in
# `.tmux.conf`); palette/layout runtime operations write session overrides. The CLI
# only *reads* individual values back for discovery. `apply` bakes the effective value.

# <key-prefix> is the bare-key prefix WITHIN the public namespace: "" for palette
# (the key is the element) or "segment-" for segments. pub_* applies the @airline-
# prefix; api never spells it.
_static_show () {   # <session> <key-prefix> <validator> <list-array-name> [<X>]
  local session="$1" keypfx="$2" valid="$3" listname="$4" x="${5:-}"
  if [[ -n "$x" ]]; then
    "$valid" "$x" || die "show: unknown target '$x'"
    pub_get_session "$session" "${keypfx}${x}"
    return 0
  fi
  local -n all="$listname"; local k
  for k in "${all[@]}"; do
    _show_row "$k" "$(pub_get_session "$session" "${keypfx}${k}")"
  done
}

# palette show: bare → the whole palette (its `name` field + every element, labeled —
# a human summary, don't parse it); `show name` → the active palette name, raw (the
# scripting read, replaces the old `current`); `show <element>` → one element, raw.
# `name` is a VIRTUAL field: it lives in the private selection, not a public option.
_palette_show () {   # <session> [name|<element>]
  local session="$1" x="${2:-}"
  [[ "$x" == name ]] && { prv_get_session "$session" palette; return 0; }
  [[ -z "$x" ]] && _show_row name "$(prv_get_session "$session" palette)"
  _static_show "$session" "" _palette_element_valid AIRLINE_PALETTE_ELEMENTS "$x"
}

# adapter show: iterate the active set — the adapters currently applied (recorded by
# every `use`/`load`), one per line. Bare-only, unlike palette/status: an adapter is a
# valueless name, so there is no per-member `show <x>` value to return. This is the
# MULTI-active noun — its "what's on" answer is a LIST, not a scalar `name`. (What you
# *could* apply is a different axis — `adapter available`, over the search path.)
_adapter_show () {   # <session>
  local session="$1" a
  for a in $(coll_members_session "$session" adapters); do printf '%s\n' "$a"; done
}

# CLI delegation targets for layout and its primitives.
layout_palette_show () { local s; s="$(_require_current_session)"; _palette_show "$s" "$@"; }
layout_palette_use () {
  local s; s="$(_require_current_session)"
  _load_config "$s" palette "$@"
  _apply "$s"
}
layout_palette_available () { local s; s="$(_require_current_session)"; _path_available "$s" palette; }
layout_palette_register () { local s; s="$(_require_current_session)"; _register "$s" palette "$@"; }

layout_segment_show () {
  local s; s="$(_require_current_session)"
  _static_show "$s" "segment-" _segment_slot_valid AIRLINE_SEGMENT_SLOTS "$@"
}

layout_adapter_use () {
  local s; s="$(_require_current_session)"
  _apply_adapter "$s" "$@"
  _render "$s"
}
layout_adapter_load () {
  local s; s="$(_require_current_session)"
  _load_adapter "$s" "$@"
  _render "$s"
}
layout_adapter_show () { _adapter_show "$(_require_current_session)"; }
layout_adapter_available () { local s; s="$(_require_current_session)"; _path_available "$s" adapter; }
layout_adapter_register () { local s; s="$(_require_current_session)"; _register "$s" adapter "$@"; }

layout_use () {
  local s; s="$(_require_current_session)"
  _layout_use "$s" "$@"
  render "$s" || true
}
layout_load () {
  local s; s="$(_require_current_session)"
  _layout_load "$s" "$@"
  render "$s" || true
}
layout_show () { local s; s="$(_require_current_session)"; _layout_show "$s" "$@"; }
layout_available () { local s; s="$(_require_current_session)"; _path_available "$s" layout; }
layout_register () { local s; s="$(_require_current_session)"; _register "$s" layout "$@"; }

# vim: ft=bash
