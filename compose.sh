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

# Palette tokens: roles whose NAME is also a valid runtime signal value — a health
# severity, a window mode. The health badge selector maps a stored token to its
# baked color through this list (token name == role name). The status badge does
# NOT use this — its levels are semantic and map through AIRLINE_STATUS_COLOR below.
# (Not the positional backgrounds or text weights, which a signal never names.)
declare -ga AIRLINE_PALETTE_TOKENS=(active alert stress ok special monitor copy zoom)

# Health severities, low→high — handed to coll_reduce as the ranking, so the
# collection layer stays severity-agnostic.
declare -ga AIRLINE_SEVERITIES=(ok alert stress)

# PRIVATE state options (@airline--*, double-dash; DESIGN.md §State model) — the
# window-scoped scalars the two badges render. Each is a reduction airline projects
# from its collection at set/clear time (status_project / health_project), read live
# by the window format through a token→color selector. The `--` keeps them clear of
# the collection namespaces (@airline--status*, @airline--health*) AND of any public
# @airline-<element> a user sets, so nothing can collide with a badge scalar.
AIRLINE_OPT_STATUS='@airline--badge-status'    # left badge:  reduced app-status level
AIRLINE_OPT_HEALTH='@airline--badge-health'    # right badge: reduced health severity
AIRLINE_OPT_SUSPENDED='@airline--suspended'    # private flag: dim palette for nested sessions
# SC2034: these two are consumed by the `airline` CLI (init), which sources this
# file — shellcheck can't trace the cross-file use.
# shellcheck disable=SC2034
AIRLINE_OPT_CLI='@airline--cli'                # published CLI path (plugins discover airline)
# shellcheck disable=SC2034
AIRLINE_OPT_DEFAULTS='@airline--defaults-done' # first-run sentinel: seed defaults once

# The status ladder — semantic levels, low→high precedence, each mapped to a theme
# color role. The order is handed to coll_reduce as the ranking (collections stays
# domain-free) and to the selector as the level→color map: `attention` outranks
# `result` outranks `active`; a window with no status contributor shows no badge.
# (`active` reusing the active-window highlight color is intentional — a badge only
# earns its place on inactive windows, which carry no highlight to clash with.)
declare -ga AIRLINE_STATUS_LEVELS=(active result attention)
declare -gA AIRLINE_STATUS_COLOR=([active]=active [result]=ok [attention]=alert)

# Private rendering vocabulary — airline-owned CONSTANTS, baked into the composed
# format strings at apply. Not configurable: no public option, no private option, no
# knob (DESIGN.md §Static config). They never change at runtime and aren't a user's
# to tune; a value only compose reads is a constant, not an option. The glyph and
# chevron literals are set below where the byte injection is visible.
AIRLINE_TMPL_WINDOW='#I:#W'   # window-name template (index:name)
AIRLINE_GLYPH_STATUS='●'      # left badge mark  (status)
AIRLINE_GLYPH_HEALTH='●'      # right badge mark (health)

# Boundary validators — pure predicates the CLI calls before it stores anything.
_segment_slot_valid () {
  local s; for s in "${AIRLINE_SEGMENT_SLOTS[@]}"; do [[ "$s" == "$1" ]] && return 0; done
  return 1
}
_theme_element_valid () {
  local e; for e in "${AIRLINE_THEME_ELEMENTS[@]}"; do [[ "$e" == "$1" ]] && return 0; done
  return 1
}
_status_level_valid () {
  local l; for l in "${AIRLINE_STATUS_LEVELS[@]}"; do [[ "$l" == "$1" ]] && return 0; done
  return 1
}
_health_severity_valid () {
  local s; for s in "${AIRLINE_SEVERITIES[@]}"; do [[ "$s" == "$1" ]] && return 0; done
  return 1
}

#-----------------------------------------------------------------------------#
# Palette — THEME, populated from the @airline-<element> options.
#-----------------------------------------------------------------------------#

# -gA so it survives being populated from inside a sourced function (the test
# harness sources compose.sh from within a helper).
declare -gA THEME

# Read every theme element into THEME, then apply the suspended dimming when the
# private suspended flag is 1 (flat, muted palette for nested sessions).
_palette_load () {
  local el
  for el in "${AIRLINE_THEME_ELEMENTS[@]}"; do
    THEME[$el]="$(opt_get_global "@airline-$el")"
  done
  if [[ "$(opt_get_global "$AIRLINE_OPT_SUSPENDED")" == 1 ]]; then _palette_suspend; fi
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

# Powerline chevron between two backgrounds. The glyph is structural — its fg is the
# left block's bg, its bg the right block's, so the separator carries the color
# gradient. The two glyphs (U+E0B0 / U+E0B2) are private rendering CONSTANTS
# (AIRLINE_CHEV_* below), never configurable: a bare-char knob would render against
# the wrong gradient. (A "no powerline font" mode, if wanted, is a separate switch —
# not a per-chevron option.)
AIRLINE_CHEV_RIGHT=""   # powerline separator, status-left
AIRLINE_CHEV_LEFT=""    # powerline separator, status-right
_chevron () { printf '#[fg=%s,bg=%s]%s' "$2" "$1" "$3"; }   # left_bg right_bg glyph
_chev_right () { _chevron "$2" "$1" "$AIRLINE_CHEV_RIGHT"; }
_chev_left  () { _chevron "$1" "$2" "$AIRLINE_CHEV_LEFT"; }

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
# Window entry — modes (zoom > copy > monitor).
#-----------------------------------------------------------------------------#
# A window can be in a tmux mode: zoomed, in copy/view mode, or flagged for
# monitor-activity. The loud signal goes where you're NOT looking (same rule as the
# badges): an *inactive* window in a mode fills its BACKGROUND with the mode color
# ("look — window 3 is zoomed"); the *active* window, which you can already see, only
# tints its name FOREGROUND. The active window keeps its active-color highlight block
# either way, so "which window is current" stays obvious.

# zoom > copy > monitor precedence, in one place. `fmt` is a printf template applied
# to each mode's color; `fallback` is emitted when no mode is active.
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
# Bare mode color, or inner-bg when no mode — the inactive window's background fill
# AND the active window's name foreground (the one signal value, used on both sides).
window_mode_color () { _mode_expr '%s' "${THEME[inner-bg]}"; }
# "<in-mode>" when the window is in any mode, else "<none>" — used to knock the
# inactive name out to inner-bg over a filled block, but keep primary on a flat one.
_window_mode_pick () {   # <in-mode> <none>
  printf '#{?#{window_zoomed_flag},%s,#{?#{pane_in_mode},%s,#{?monitor-activity,%s,%s}}}' \
    "$1" "$1" "$1" "$2"
}

#-----------------------------------------------------------------------------#
# Badges — status (left of the name) and health (right of it).
#-----------------------------------------------------------------------------#
# Two channels flank the window name. Each is a runtime collection reduced to ONE
# badge and projected to a per-window scalar (status_project / health_project):
#   status : app-status contributors (ns "status") reduced by the level ladder into
#            AIRLINE_OPT_STATUS; the left badge shows one glyph in that level's
#            color, or nothing when no contributor reports.
#   health : health contributors (ns "health") reduced to the max severity into
#            AIRLINE_OPT_HEALTH; the right badge shows one glyph in that severity's
#            color, or nothing when healthy.
# The colors are baked here at compose time; WHICH color shows is a live #{?…}
# selector tmux re-evaluates per window — the selector leg of the freeze model.
# The side (left vs right) tells the two badges apart, so their colors may overlap.

# A live expression mapping a token-valued option to its baked theme color, falling
# back to <fallback> when the option is empty or holds an unknown token. Used for
# health, whose tokens (severities) ARE theme role names — token maps to THEME[token].
_palette_token_expr () {   # <option-name> <fallback-color>
  local option="$1" expr="$2" tok
  for tok in "${AIRLINE_PALETTE_TOKENS[@]}"; do
    expr="#{?#{==:#{$option},$tok},${THEME[$tok]},$expr}"
  done
  printf '%s' "$expr"
}

# The same, for the status ladder, whose levels are NOT theme role names: each level
# maps through AIRLINE_STATUS_COLOR to its baked color (e.g. result → THEME[ok]).
_status_token_expr () {   # <option-name> <fallback-color>
  local option="$1" expr="$2" lvl
  for lvl in "${AIRLINE_STATUS_LEVELS[@]}"; do
    expr="#{?#{==:#{$option},$lvl},${THEME[${AIRLINE_STATUS_COLOR[$lvl]}]},$expr}"
  done
  printf '%s' "$expr"
}

# Project a window's reduced collection value into its badge scalar: the highest-
# ranked entry among the window's contributors, or clear when none rank. Called by
# `status`/`health` `set`/`clear` at runtime; the window format reads the scalar
# live. Returns 0 when the rendered value changed (so the caller can gate a redraw).
_project () {   # <win> <ns> <ranking> <badge-option>
  local win="$1" ns="$2" ranking="$3" opt="$4" top
  top="$(coll_reduce_window "$win" "$ns" "$ranking")"
  if [[ -n "$top" ]]; then
    opt_setif_window "$win" "$opt" "$top"
  else
    [[ -n "$(opt_get_window "$win" "$opt")" ]] || return 1
    opt_unset_window "$win" "$opt"
  fi
}

# Status: every level shows (absence is the blank), so project the reduce verbatim.
status_project () {   # <win>
  _project "$1" status "${AIRLINE_STATUS_LEVELS[*]}" "$AIRLINE_OPT_STATUS"
}

# Health: a clean badge means healthy, so an `ok`/none reduce projects as blank.
health_project () {   # <win>
  local win="$1" max
  max="$(coll_reduce_window "$win" health "${AIRLINE_SEVERITIES[*]}")"
  case "$max" in stress|alert) ;; *) max="" ;; esac
  if [[ -n "$max" ]]; then
    opt_setif_window "$win" "$AIRLINE_OPT_HEALTH" "$max"
  else
    [[ -n "$(opt_get_window "$win" "$AIRLINE_OPT_HEALTH")" ]] || return 1
    opt_unset_window "$win" "$AIRLINE_OPT_HEALTH"
  fi
}

#-----------------------------------------------------------------------------#
# Window formats — the window-list styling, with the status and health badges
# woven in around the name (status left, health right).
#-----------------------------------------------------------------------------#
# Returns 0 when any rendered option actually changed (so recompose can gate one
# redraw across the whole bar), 1 when every value was already current.
set_window_formats () {
  local bg="${THEME[inner-bg]}" active_bg="${THEME[active]}" template changed=1
  template="$AIRLINE_TMPL_WINDOW"

  # Mode signal. inactive: fill the background; active: tint the name foreground.
  local mode_color inactive_fg
  mode_color="$(window_mode_color)"                                       # mode color, else inner-bg
  inactive_fg="$(_window_mode_pick "$bg" "${THEME[primary]}")"           # knock out over a fill, else primary

  # Status badge (left of the name): one glyph at the window's reduced level.
  local status_expr
  status_expr="#{?$AIRLINE_OPT_STATUS,#[fg=$(_status_token_expr "$AIRLINE_OPT_STATUS" "${THEME[primary]}")]$AIRLINE_GLYPH_STATUS ,}"

  # Health badge (right of the name): one glyph at the window's reduced severity.
  local health_expr
  health_expr="#{?$AIRLINE_OPT_HEALTH, #[fg=$(_palette_token_expr "$AIRLINE_OPT_HEALTH" "${THEME[primary]}")]$AIRLINE_GLYPH_HEALTH,}"

  opt_setif_global window-status-separator " " && changed=0
  # inactive: the whole tab fills with the mode color (flat inner-bg when no mode).
  opt_setif_global window-status-format \
    "#[bg=${mode_color}]${status_expr}#[fg=${inactive_fg}]${template}${health_expr}" && changed=0
  opt_setif_global window-status-style          "fg=${THEME[primary]} bg=$bg"     && changed=0
  opt_setif_global window-status-last-style     "fg=${THEME[emphasized]} bg=$bg"  && changed=0
  opt_setif_global window-status-activity-style "fg=${THEME[alert]} bg=$bg"       && changed=0
  opt_setif_global window-status-bell-style     "fg=${THEME[stress]} bg=$bg"      && changed=0
  # active: a constant active-color highlight block, name foreground tinted by mode.
  opt_setif_global window-status-current-format \
    "$(_chev_right "$bg" "$active_bg") ${status_expr}#[fg=${mode_color}]${template}${health_expr} $(_chev_left "$active_bg" "$bg")" && changed=0
  return $changed
}

#-----------------------------------------------------------------------------#
# Compose-all — bake the whole bar from stored @airline-* state.
#-----------------------------------------------------------------------------#
# The shared "freeze" step: load the palette and write every composed option —
# chrome styles, segment bars, window formats — baking THEME colors in as constants
# (the freeze leg of the model; live #{?…} selectors decide which baked color shows).
# init and each noun's `apply` call this; it does NOT seed defaults, publish the CLI
# path, or bind keys — those are init's job. Idempotent and redraw-gated: it rewrites
# only options whose value changed (opt_setif_*) and redraws once iff any did.
# Returns 0 when something changed (a redraw happened), 1 when the bar was current.
recompose () {
  _palette_load
  local changed=1
  opt_setif_global pane-border-style         "fg=${THEME[primary]}"                       && changed=0
  opt_setif_global pane-active-border-style   "fg=${THEME[active]}"                        && changed=0
  opt_setif_global display-panes-color        "${THEME[primary]}"                          && changed=0
  opt_setif_global display-panes-active-color "${THEME[active]}"                           && changed=0
  opt_setif_global status-style               "fg=${THEME[secondary]} bg=${THEME[inner-bg]}" && changed=0
  opt_setif_global status-left-style          "fg=${THEME[primary]} bg=${THEME[outer-bg]}"   && changed=0
  opt_setif_global status-right-style         "fg=${THEME[primary]} bg=${THEME[outer-bg]}"   && changed=0
  opt_setif_global status-left                "$(_build_status_left)"                      && changed=0
  opt_setif_global status-right               "$(_build_status_right)"                     && changed=0
  opt_setif_global clock-mode-color           "${THEME[special]}"                          && changed=0
  set_window_formats && changed=0
  [[ $changed -eq 0 ]] && redraw
  return $changed
}

# vim: ft=bash
