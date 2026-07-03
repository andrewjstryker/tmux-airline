#!/usr/bin/env bash
#
# render.sh — composition: render the status bar.
#
# Builds the bar from the stored @airline-* state: it loads the palette and renders
# the segment bar, window formats, and chrome (the `render` function, driven by
# `apply`). It also owns airline's shared vocabulary — the segment slots, palette
# elements, and rendering constants — plus the predicates the CLI validates against
# at the boundary. It reaches tmux only through the mechanical layer (tmux.sh's
# opt_*) and *trusts its inputs*; validation lives at the boundary (api.sh), not here.
#
# Assumes tmux.sh is already sourced — the CLI and the test harness load
# mechanical-then-logic, in that order. The guard below enforces it.

# shellcheck shell=bash

if ! declare -F opt_get_global >/dev/null; then
  printf 'render.sh: load tmux.sh first\n' >&2
  return 1 2>/dev/null || exit 1
fi
if ! declare -F coll_get_global >/dev/null; then
  printf 'render.sh: load collections.sh first\n' >&2
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

# Palette elements: the palette roles.
declare -ga AIRLINE_PALETTE_ELEMENTS=(
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

# PRIVATE state — BARE keys into the private (@airline--) namespace; the prefix is
# tmux.sh's (prv_name / prv_*), so render never spells it. These name the window-
# scoped scalars the two badges render: each is a reduction airline projects from its
# collection at set/clear time (status_project / health_project), read live by the
# window format through a token→color selector. The private namespace keeps them
# clear of the collection keys (status*, health*) AND of any public element a user
# sets, so nothing can collide with a badge scalar.
AIRLINE_KEY_STATUS='badge-status'        # left badge:  reduced app-status level
AIRLINE_KEY_HEALTH='badge-health'        # right badge: reduced health severity
AIRLINE_KEY_SUSPENDED='suspended'        # private flag: dim palette for nested sessions
# SC2034: these two are consumed by the `airline` CLI (init), which sources this
# file — shellcheck can't trace the cross-file use.
# shellcheck disable=SC2034
AIRLINE_KEY_CLI='cli'                    # published CLI path (plugins discover airline)
# shellcheck disable=SC2034
AIRLINE_KEY_DEFAULTS='defaults-done'     # first-run sentinel: seed defaults once

# The status ladder — semantic levels, low→high precedence, each mapped to a palette
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
# to tune; a value only render reads is a constant, not an option. The glyph and
# chevron literals are set below where the byte injection is visible.
AIRLINE_TMPL_WINDOW='#I:#W'   # window-name template (index:name)

# Badge glyphs — a distinct SHAPE per state, redundant with the color so the badge is
# legible without color (color-blind users). Position separates the two lanes, so a
# shape may repeat across lanes but each lane is internally distinct. The bare
# AIRLINE_GLYPH_* are the fallback for an unknown token (never hit in practice).
AIRLINE_GLYPH_STATUS='●'      # status fallback
AIRLINE_GLYPH_HEALTH='▲'      # health fallback
# SC2034: read via nameref in _glyph_expr, which shellcheck can't trace.
# shellcheck disable=SC2034
declare -gA AIRLINE_STATUS_GLYPH=([active]='○' [result]='●' [attention]='◆')  # watch → done → needs-you
# shellcheck disable=SC2034
declare -gA AIRLINE_HEALTH_GLYPH=([alert]='△' [stress]='▲')                    # escalating warning

# Boundary validators — pure predicates the CLI calls before it stores anything.
_segment_slot_valid () {
  local s; for s in "${AIRLINE_SEGMENT_SLOTS[@]}"; do [[ "$s" == "$1" ]] && return 0; done
  return 1
}
_palette_element_valid () {
  local e; for e in "${AIRLINE_PALETTE_ELEMENTS[@]}"; do [[ "$e" == "$1" ]] && return 0; done
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
# Palette — PALETTE, populated from the @airline-<element> options.
#-----------------------------------------------------------------------------#

# -gA so it survives being populated from inside a sourced function (the test
# harness sources render.sh from within a helper).
declare -gA PALETTE

# Read every palette element into PALETTE, then apply the suspended dimming when the
# private suspended flag is 1 (flat, muted palette for nested sessions).
_palette_load () {
  local el
  for el in "${AIRLINE_PALETTE_ELEMENTS[@]}"; do
    PALETTE[$el]="$(pub_get "$el")"
  done
  if [[ "$(prv_get_global "$AIRLINE_KEY_SUSPENDED")" == 1 ]]; then _palette_suspend; fi
}

_palette_suspend () {
  PALETTE[outer-bg]="${PALETTE[inner-bg]}"
  PALETTE[middle-bg]="${PALETTE[inner-bg]}"
  PALETTE[emphasized]="${PALETTE[secondary]}"
  PALETTE[primary]="${PALETTE[secondary]}"
  PALETTE[active]="${PALETTE[secondary]}"
  PALETTE[special]="${PALETTE[secondary]}"
  PALETTE[ok]="${PALETTE[secondary]}"
  PALETTE[zoom]="${PALETTE[secondary]}"
  PALETTE[copy]="${PALETTE[secondary]}"
  PALETTE[monitor]="${PALETTE[secondary]}"
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
    [[ -n "$(pub_get "segment-$slot")" ]] && printf '%s\n' "$slot"
  done
}

# Compose status-left: blocks outer→inner, each followed by a chevron into the
# next slot's tier (or the inner-bg window list after the last).
_build_status_left () {
  local fg="${PALETTE[emphasized]}" out="" bg next_bg i s
  local -a active=(); while IFS= read -r s; do active+=("$s"); done < <(_active_slots left)
  local n=${#active[@]}
  for (( i=0; i<n; i++ )); do
    bg="${PALETTE[${AIRLINE_SLOT_TIER[${active[i]}]}-bg]}"
    if (( i+1 < n )); then next_bg="${PALETTE[${AIRLINE_SLOT_TIER[${active[i+1]}]}-bg]}"
    else                   next_bg="${PALETTE[inner-bg]}"; fi
    out+="#[fg=$fg,bg=$bg] $(pub_get "segment-${active[i]}") $(_chev_right "$bg" "$next_bg")"
  done
  printf '%s' "$out"
}

# Compose status-right: each block preceded by a chevron from the previous tier
# (the inner-bg window list before the first).
_build_status_right () {
  local fg="${PALETTE[emphasized]}" out="" bg prev_bg="${PALETTE[inner-bg]}" i s
  local -a active=(); while IFS= read -r s; do active+=("$s"); done < <(_active_slots right)
  local n=${#active[@]}
  for (( i=0; i<n; i++ )); do
    bg="${PALETTE[${AIRLINE_SLOT_TIER[${active[i]}]}-bg]}"
    out+="$(_chev_left "$prev_bg" "$bg")#[fg=$fg,bg=$bg] $(pub_get "segment-${active[i]}") "
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
    "$(printf "$fmt" "${PALETTE[zoom]}")" \
    "$(printf "$fmt" "${PALETTE[copy]}")" \
    "$(printf "$fmt" "${PALETTE[monitor]}")" \
    "$fallback"
}
# Bare mode color, or inner-bg when no mode — the inactive window's background fill
# AND the active window's name foreground (the one signal value, used on both sides).
window_mode_color () { _mode_expr '%s' "${PALETTE[inner-bg]}"; }
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
#            the AIRLINE_KEY_STATUS scalar; the left badge shows one glyph in that
#            level's color, or nothing when no contributor reports.
#   health : health contributors (ns "health") reduced to the max severity into the
#            AIRLINE_KEY_HEALTH scalar; the right badge shows one glyph in that
#            severity's color, or nothing when healthy.
# The colors are baked here at compose time; WHICH color shows is a live #{?…}
# selector tmux re-evaluates per window — the selector leg of the render model.
# The side (left vs right) tells the two badges apart, so their colors may overlap.

# A live expression mapping a token-valued option to its baked palette color, falling
# back to <fallback> when the option is empty or holds an unknown token. Used for
# health, whose tokens (severities) ARE palette role names — token maps to PALETTE[token].
_palette_token_expr () {   # <option-name> <fallback-color>
  local option="$1" expr="$2" tok
  for tok in "${AIRLINE_PALETTE_TOKENS[@]}"; do
    expr="#{?#{==:#{$option},$tok},${PALETTE[$tok]},$expr}"
  done
  printf '%s' "$expr"
}

# The same, for the status ladder, whose levels are NOT palette role names: each level
# maps through AIRLINE_STATUS_COLOR to its baked color (e.g. result → PALETTE[ok]).
_status_token_expr () {   # <option-name> <fallback-color>
  local option="$1" expr="$2" lvl
  for lvl in "${AIRLINE_STATUS_LEVELS[@]}"; do
    expr="#{?#{==:#{$option},$lvl},${PALETTE[${AIRLINE_STATUS_COLOR[$lvl]}]},$expr}"
  done
  printf '%s' "$expr"
}

# Live selector mapping <option>'s token to a GLYPH via the named assoc map; <fallback>
# when empty/unknown. One level (token → glyph) — the shape channel that runs
# alongside the color selectors so each badge state is distinct without color.
_glyph_expr () {   # <option-name> <fallback-glyph> <map-array-name>
  local option="$1" expr="$2" tok; local -n map="$3"
  for tok in "${!map[@]}"; do
    expr="#{?#{==:#{$option},$tok},${map[$tok]},$expr}"
  done
  printf '%s' "$expr"
}

# A `#[blink]` directive when <option> holds <token>, else nothing — the "watchable"
# cue (status `active`, health `stress`). Best-effort: tmux emits the attribute but
# terminals vary in honoring blink. Pair with a trailing `#[noblink]` so it can't leak.
_blink_when () { printf '#{?#{==:#{%s},%s},#[blink],}' "$1" "$2"; }   # <option> <token>

# Project a window's reduced collection value into its badge scalar: the highest-
# ranked entry among the window's contributors, or clear when none rank. Called by
# `status`/`health` `set`/`clear` at runtime; the window format reads the scalar
# live. Returns 0 when the rendered value changed (so the caller can gate a redraw).
_project () {   # <win> <ns> <ranking> <badge-key>
  local win="$1" ns="$2" ranking="$3" key="$4" top
  top="$(coll_reduce_window "$win" "$ns" "$ranking")"
  if [[ -n "$top" ]]; then
    prv_setif_window "$win" "$key" "$top"
  else
    [[ -n "$(prv_get_window "$win" "$key")" ]] || return 1
    prv_unset_window "$win" "$key"
  fi
}

# Status: every level shows (absence is the blank), so project the reduce verbatim.
status_project () {   # <win>
  _project "$1" status "${AIRLINE_STATUS_LEVELS[*]}" "$AIRLINE_KEY_STATUS"
}

# Health: a clean badge means healthy, so an `ok`/none reduce projects as blank.
health_project () {   # <win>
  local win="$1" max
  max="$(coll_reduce_window "$win" health "${AIRLINE_SEVERITIES[*]}")"
  case "$max" in stress|alert) ;; *) max="" ;; esac
  if [[ -n "$max" ]]; then
    prv_setif_window "$win" "$AIRLINE_KEY_HEALTH" "$max"
  else
    [[ -n "$(prv_get_window "$win" "$AIRLINE_KEY_HEALTH")" ]] || return 1
    prv_unset_window "$win" "$AIRLINE_KEY_HEALTH"
  fi
}

#-----------------------------------------------------------------------------#
# Window formats — the window-list styling, with the status and health badges
# woven in around the name (status left, health right).
#-----------------------------------------------------------------------------#
# Returns 0 when any rendered option actually changed (so render can gate one
# redraw across the whole bar), 1 when every value was already current.
set_window_formats () {
  local bg="${PALETTE[inner-bg]}" active_bg="${PALETTE[active]}" template changed=1
  template="$AIRLINE_TMPL_WINDOW"

  # Mode signal. inactive: fill the background; active: tint the name foreground.
  local mode_color inactive_fg
  mode_color="$(window_mode_color)"                                       # mode color, else inner-bg
  inactive_fg="$(_window_mode_pick "$bg" "${PALETTE[primary]}")"           # knock out over a fill, else primary

  # The two badges read their scalar live by NAME inside a #{?…} selector; resolve
  # the bare keys to private option names through the policy builder.
  local status_opt health_opt
  status_opt="$(prv_name "$AIRLINE_KEY_STATUS")"
  health_opt="$(prv_name "$AIRLINE_KEY_HEALTH")"

  # Status badge (left of the name): a per-level shape in the level's color, blinking
  # while `active` (watchable). #[noblink] closes the attr so it can't leak to the name.
  local status_expr
  status_expr="#{?$status_opt,#[fg=$(_status_token_expr "$status_opt" "${PALETTE[primary]}")]$(_blink_when "$status_opt" active)$(_glyph_expr "$status_opt" "$AIRLINE_GLYPH_STATUS" AIRLINE_STATUS_GLYPH)#[noblink] ,}"

  # Health badge (right of the name): a per-severity shape in the severity's color,
  # blinking while `stress` (critical).
  local health_expr
  health_expr="#{?$health_opt, #[fg=$(_palette_token_expr "$health_opt" "${PALETTE[primary]}")]$(_blink_when "$health_opt" stress)$(_glyph_expr "$health_opt" "$AIRLINE_GLYPH_HEALTH" AIRLINE_HEALTH_GLYPH)#[noblink],}"

  opt_setif_global window-status-separator " " && changed=0
  # inactive: the whole tab fills with the mode color (flat inner-bg when no mode).
  opt_setif_global window-status-format \
    "#[bg=${mode_color}]${status_expr}#[fg=${inactive_fg}]${template}${health_expr}" && changed=0
  opt_setif_global window-status-style          "fg=${PALETTE[primary]} bg=$bg"     && changed=0
  opt_setif_global window-status-last-style     "fg=${PALETTE[emphasized]} bg=$bg"  && changed=0
  opt_setif_global window-status-activity-style "fg=${PALETTE[alert]} bg=$bg"       && changed=0
  opt_setif_global window-status-bell-style     "fg=${PALETTE[stress]} bg=$bg"      && changed=0
  # active: a constant active-color highlight block, name foreground tinted by mode.
  opt_setif_global window-status-current-format \
    "$(_chev_right "$bg" "$active_bg") ${status_expr}#[fg=${mode_color}]${template}${health_expr} $(_chev_left "$active_bg" "$bg")" && changed=0
  return $changed
}

#-----------------------------------------------------------------------------#
# render — produce the whole bar from the stored @airline-* state.
#-----------------------------------------------------------------------------#
# The shared render step: load the palette and write every composed option — chrome
# styles, segment bars, window formats — baking PALETTE colors in as constants (live
# #{?…} selectors then decide which baked color shows). `apply` and `init` call this;
# it does NOT seed defaults, publish the CLI path, or bind keys — those are init's
# job. Idempotent and redraw-gated: it rewrites only options whose value changed
# (opt_setif_*) and redraws once iff any did. Returns 0 when something changed
# (a redraw happened), 1 when the bar was already current.
render () {
  _palette_load
  local changed=1
  opt_setif_global pane-border-style         "fg=${PALETTE[primary]}"                       && changed=0
  opt_setif_global pane-active-border-style   "fg=${PALETTE[active]}"                        && changed=0
  opt_setif_global display-panes-color        "${PALETTE[primary]}"                          && changed=0
  opt_setif_global display-panes-active-color "${PALETTE[active]}"                           && changed=0
  opt_setif_global status-style               "fg=${PALETTE[secondary]} bg=${PALETTE[inner-bg]}" && changed=0
  opt_setif_global status-left-style          "fg=${PALETTE[primary]} bg=${PALETTE[outer-bg]}"   && changed=0
  opt_setif_global status-right-style         "fg=${PALETTE[primary]} bg=${PALETTE[outer-bg]}"   && changed=0
  opt_setif_global status-left                "$(_build_status_left)"                      && changed=0
  opt_setif_global status-right               "$(_build_status_right)"                     && changed=0
  opt_setif_global clock-mode-color           "${PALETTE[special]}"                          && changed=0
  set_window_formats && changed=0
  [[ $changed -eq 0 ]] && redraw
  return $changed
}

# vim: ft=bash
