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
if ! declare -F coll_get_global >/dev/null; then
  printf 'compose.sh: load collections.sh first\n' >&2
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

# Palette tokens: the subset of roles a runtime signal may name — a status lane's
# lit color, a health severity, a window mode. The badge selectors map a stored
# token to its baked color through this list. (Not the positional backgrounds or
# text weights, which a signal never names.)
declare -ga AIRLINE_PALETTE_TOKENS=(active alert stress ok special monitor copy zoom)

# Health severities, low→high — handed to coll_reduce as the ranking, so the
# collection layer stays severity-agnostic.
declare -ga AIRLINE_SEVERITIES=(ok alert stress)

# The window-scoped scalar the health gutter renders: the reduced (max) severity,
# projected from the per-window "health" collection by health_project. Deliberately
# NOT in the "health" collection namespace (which owns @airline-health and
# @airline-health-<key>), so a contributor key can never collide with it.
AIRLINE_OPT_GUTTER='@airline-gutter'

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
# Badges — health gutter (left of the name) and status stack (right of it).
#-----------------------------------------------------------------------------#
# Two channels flank the window name, both driven by the runtime collections:
#   health : per-window contributors (ns "health") reduced to one max severity,
#            projected into AIRLINE_OPT_GUTTER; the gutter shows one glyph in that
#            severity's color, or nothing when healthy.
#   status : a global registry of lanes (ns "status": glyph + priority), each lit
#            per window by a token in its own option; the stack shows one glyph
#            per lit lane, ascending priority.
# The colors are baked here at compose time; WHICH color shows is a live #{?…}
# selector tmux re-evaluates per window — the selector leg of the freeze model.

# A live expression mapping a token-valued option to its baked theme color,
# falling back to <fallback> when the option is empty or holds an unknown token.
_palette_token_expr () {   # <option-name> <fallback-color>
  local option="$1" expr="$2" tok
  for tok in "${AIRLINE_PALETTE_TOKENS[@]}"; do
    expr="#{?#{==:#{$option},$tok},${THEME[$tok]},$expr}"
  done
  printf '%s' "$expr"
}

# Registered status lanes, ascending priority (stable). The global "status"
# collection stores each lane as a (glyph, priority) tuple; we sort on priority.
_status_lanes_sorted () {
  local lane glyph prio
  for lane in $(coll_members_global status); do
    IFS=$'\t' read -r glyph prio <<< "$(coll_get_global status "$lane")"
    printf '%s %s\n' "${prio:-50}" "$lane"
  done | sort -n -s -k1,1 | awk '{print $2}'
}

# Project the per-window reduced health severity into the gutter scalar. stress /
# alert → set it; ok / none → clear it (a clean gutter means healthy). Called by
# `health set`/`clear` at runtime; the window-status-format reads the scalar live.
# Returns 0 when the rendered value changed (so the caller can gate a redraw).
health_project () {   # <win>
  local win="$1" max
  max="$(coll_reduce_window "$win" health "${AIRLINE_SEVERITIES[*]}")"
  case "$max" in stress|alert) ;; *) max="" ;; esac
  if [[ -n "$max" ]]; then
    opt_setif_window "$win" "$AIRLINE_OPT_GUTTER" "$max"
  else
    [[ -n "$(opt_get_window "$win" "$AIRLINE_OPT_GUTTER")" ]] || return 1
    opt_unset_window "$win" "$AIRLINE_OPT_GUTTER"
  fi
}

#-----------------------------------------------------------------------------#
# Window formats — the window-list styling, with the health gutter + status stack
# woven in around the name.
#-----------------------------------------------------------------------------#
set_window_formats () {
  local bg="${THEME[inner-bg]}" template mode_fg hi_expr
  template="$(opt_getor_global @airline-tmpl-window '#I:#W')"
  mode_fg="$(window_mode_fg)"
  hi_expr="$(window_mode_hi)"

  # Health gutter: one glyph at the window's reduced severity, empty when healthy.
  local health_expr hglyph
  hglyph="$(opt_getor_global @airline-health-glyph '●')"
  health_expr="#{?$AIRLINE_OPT_GUTTER,#[fg=$(_palette_token_expr "$AIRLINE_OPT_GUTTER" "${THEME[primary]}")]$hglyph ,}"

  # Status stack: one glyph per lit lane, ascending priority, each colored by its
  # lit token. Each lane's option is referenced live, so lighting it is redraw-only.
  local status_expr="" lane glyph prio opt
  while IFS= read -r lane; do
    [[ -z "$lane" ]] && continue
    IFS=$'\t' read -r glyph prio <<< "$(coll_get_global status "$lane")"
    opt="$(coll_optname status "$lane")"
    status_expr+="#{?$opt, #[fg=$(_palette_token_expr "$opt" "${THEME[primary]}")]${glyph:-●},}"
  done < <(_status_lanes_sorted)

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
