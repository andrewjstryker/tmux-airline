#!/usr/bin/env bash
#
# compose.sh — composition.
#
# Builds the status bar from the stored @airline-* state: it loads the palette
# and composes the segment bar (and, later, the window formats and `apply`). It
# also owns airline's shared vocabulary — the segment slots and theme elements,
# plus the predicates the CLI validates against at the boundary. It reaches tmux
# only through the mechanical layer (tmux.sh's opt_*) and *trusts its inputs*;
# validation lives at the boundary (the `airline` CLI), not here.
#
# Assumes tmux.sh is already sourced — the CLI and the test harness load
# mechanical-then-logic, in that order. The guard below enforces it.

# shellcheck shell=bash

if ! declare -F opt_get_global >/dev/null; then
  printf 'compose.sh: load tmux.sh first\n' >&2
  return 1 2>/dev/null || exit 1
fi

#-----------------------------------------------------------------------------#
# Vocabulary — the names the bar is built from. The CLI validates input against
# these at the boundary; everything below trusts what it is handed.
#-----------------------------------------------------------------------------#

# Segment slots: a fixed set, side + tier baked into the name.
declare -ga AIRLINE_SEGMENT_SLOTS=(
  left-out left-mid left-in
  right-in right-mid right-out
)
declare -gA AIRLINE_SLOT_TIER=(
  [left-out]=outer  [left-mid]=middle  [left-in]=inner
  [right-in]=inner  [right-mid]=middle [right-out]=outer
)
# SC2034: read via nameref (`local -n`) in _active_slots, which shellcheck can't trace.
# shellcheck disable=SC2034
declare -ga AIRLINE_SLOTS_LEFT=(left-out left-mid left-in)
# shellcheck disable=SC2034
declare -ga AIRLINE_SLOTS_RIGHT=(right-in right-mid right-out)

# Theme elements: the palette roles.
declare -ga AIRLINE_THEME_ELEMENTS=(
  outer-bg middle-bg inner-bg
  secondary primary emphasized
  active special ok alert stress zoom copy monitor
)

# Boundary validators — pure predicates the CLI calls before it stores anything.
_segment_slot_valid () {
  local s; for s in "${AIRLINE_SEGMENT_SLOTS[@]}"; do [[ "$s" == "$1" ]] && return 0; done
  return 1
}
_theme_element_valid () {
  local e; for e in "${AIRLINE_THEME_ELEMENTS[@]}"; do [[ "$e" == "$1" ]] && return 0; done
  return 1
}

#-----------------------------------------------------------------------------#
# Palette — THEME, populated from the @airline-<element> options.
#-----------------------------------------------------------------------------#

# -gA so it survives being populated from inside a sourced function (the test
# harness sources compose.sh from within a helper).
declare -gA THEME

# Read every theme element into THEME, then apply the suspended dimming when
# @airline-suspended is 1 (flat, muted palette for nested sessions).
_palette_load () {
  local el
  for el in "${AIRLINE_THEME_ELEMENTS[@]}"; do
    THEME[$el]="$(opt_get_global "@airline-$el")"
  done
  if [[ "$(opt_get_global @airline-suspended)" == 1 ]]; then _palette_suspend; fi
}

_palette_suspend () {
  THEME[outer-bg]="${THEME[inner-bg]}"
  THEME[middle-bg]="${THEME[inner-bg]}"
  THEME[emphasized]="${THEME[secondary]}"
  THEME[primary]="${THEME[secondary]}"
  THEME[active]="${THEME[secondary]}"
  THEME[special]="${THEME[secondary]}"
  THEME[ok]="${THEME[secondary]}"
  THEME[zoom]="${THEME[secondary]}"
  THEME[copy]="${THEME[secondary]}"
  THEME[monitor]="${THEME[secondary]}"
}

#-----------------------------------------------------------------------------#
# Segment bar — compose status-left / status-right from the fixed slots.
#-----------------------------------------------------------------------------#
# A slot's tier (outer/middle/inner) is its background; the powerline chevrons
# step between consecutive non-empty slots. Empty slots are skipped entirely.

# Powerline chevron between two backgrounds. <left_bg> <right_bg>.
_chevron () { printf '#[fg=%s,bg=%s]%s' "$2" "$1" "$3"; }   # left_bg right_bg glyph
_chev_right () { _chevron "$2" "$1" ''; }
_chev_left  () { _chevron "$1" "$2" ''; }

# The non-empty slots on a side, in render order. <left|right>
_active_slots () {
  local slot
  local -n slots="AIRLINE_SLOTS_${1^^}"
  for slot in "${slots[@]}"; do
    [[ -n "$(opt_get_global "@airline-segment-$slot")" ]] && printf '%s\n' "$slot"
  done
}

# Compose status-left: blocks outer→inner, each followed by a chevron into the
# next slot's tier (or the inner-bg window list after the last).
_build_status_left () {
  local fg="${THEME[emphasized]}" out="" bg next_bg i s
  local -a active=(); while IFS= read -r s; do active+=("$s"); done < <(_active_slots left)
  local n=${#active[@]}
  for (( i=0; i<n; i++ )); do
    bg="${THEME[${AIRLINE_SLOT_TIER[${active[i]}]}-bg]}"
    if (( i+1 < n )); then next_bg="${THEME[${AIRLINE_SLOT_TIER[${active[i+1]}]}-bg]}"
    else                   next_bg="${THEME[inner-bg]}"; fi
    out+="#[fg=$fg,bg=$bg] $(opt_get_global "@airline-segment-${active[i]}") $(_chev_right "$bg" "$next_bg")"
  done
  printf '%s' "$out"
}

# Compose status-right: each block preceded by a chevron from the previous tier
# (the inner-bg window list before the first).
_build_status_right () {
  local fg="${THEME[emphasized]}" out="" bg prev_bg="${THEME[inner-bg]}" i s
  local -a active=(); while IFS= read -r s; do active+=("$s"); done < <(_active_slots right)
  local n=${#active[@]}
  for (( i=0; i<n; i++ )); do
    bg="${THEME[${AIRLINE_SLOT_TIER[${active[i]}]}-bg]}"
    out+="$(_chev_left "$prev_bg" "$bg")#[fg=$fg,bg=$bg] $(opt_get_global "@airline-segment-${active[i]}") "
    prev_bg="$bg"
  done
  printf '%s' "$out"
}

#-----------------------------------------------------------------------------#
# Window entry — modes (zoom > copy > monitor) over the per-window signal slot.
#-----------------------------------------------------------------------------#
# A window has one "signal color" slot, drawn reverse-video on the focused window
# (its background is the highlight; the flat bg becomes the knockout foreground)
# and as the foreground on inactive windows. Only modes touch it here; badges
# (health gutter, status stack) are layered in with the collections slice.

# zoom > copy > monitor precedence, in one place. `fmt` is a printf template
# applied to each mode's color; `fallback` is emitted when no mode is active.
_mode_expr () {
  local fmt="$1" fallback="$2"
  # SC2059: $fmt is a caller-supplied printf template ('%s' or '#[fg=%s]'); using
  # it as the format string is the whole point.
  # shellcheck disable=SC2059
  printf '#{?#{window_zoomed_flag},%s,#{?#{pane_in_mode},%s,#{?monitor-activity,%s,%s}}}' \
    "$(printf "$fmt" "${THEME[zoom]}")" \
    "$(printf "$fmt" "${THEME[copy]}")" \
    "$(printf "$fmt" "${THEME[monitor]}")" \
    "$fallback"
}
# Highlight background for the focused window (bare color): the active mode, else active.
window_mode_hi () { _mode_expr '%s' "${THEME[active]}"; }
# Foreground override for inactive windows (#[fg=…]); empty when no mode is active.
window_mode_fg () { _mode_expr '#[fg=%s]' ''; }

#-----------------------------------------------------------------------------#
# Window formats — the window-list styling. The badge expressions (health gutter
# + status stack) are added with the collections slice; empty placeholders now.
#-----------------------------------------------------------------------------#
set_window_formats () {
  local bg="${THEME[inner-bg]}" template mode_fg hi_expr
  template="$(opt_getor_global @airline-tmpl-window '#I:#W')"
  mode_fg="$(window_mode_fg)"
  hi_expr="$(window_mode_hi)"

  local health_expr="" status_expr=""   # filled in by the status/health slice

  opt_set_global window-status-separator-string " "
  opt_set_global window-status-format \
    "${health_expr}#[default]${mode_fg}${template}${status_expr}"
  opt_set_global window-status-style          "fg=${THEME[primary]} bg=$bg"
  opt_set_global window-status-last-style     "fg=${THEME[emphasized]} bg=$bg"
  opt_set_global window-status-activity-style "fg=${THEME[alert]} bg=$bg"
  opt_set_global window-status-bell-style     "fg=${THEME[stress]} bg=$bg"
  opt_set_global window-status-current-format \
    "$(_chev_right "$bg" "$hi_expr") ${health_expr}#[fg=$bg]${template}${status_expr} $(_chev_left "$hi_expr" "$bg")"
}

# vim: ft=bash
