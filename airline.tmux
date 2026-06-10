#!/usr/bin/env bash

CURRENT_DIR="${AIRLINE_DIR:-$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )}"

source "$CURRENT_DIR/scripts/shared.sh"
source "$CURRENT_DIR/scripts/is_installed.sh"
source "$CURRENT_DIR/scripts/plugins/online.sh"
source "$CURRENT_DIR/scripts/plugins/prefix_highlight.sh"
source "$CURRENT_DIR/scripts/plugins/cpu.sh"
source "$CURRENT_DIR/scripts/plugins/battery.sh"

# Theme palette, keyed by role (primary, alert, ok, …). -gA so it stays global
# even when airline.tmux is sourced from inside a function (the test harness),
# which would otherwise scope it locally.
declare -gA THEME

# The palette tokens a per-window signal option may hold, in render-precedence
# order. Single source of truth for palette_token_expr. -ga for the same
# sourced-in-a-function reason as THEME above.
declare -ga AIRLINE_PALETTE_TOKENS=(active alert stress ok special monitor copy zoom)

apply_suspended_overrides () {
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

# Source a theme file and populate THEME from the @airline-* options it sets.
# The single theme-population path: airline's startup and the test harness both
# call this, so the option list lives in exactly one place. Defaults to the
# @airline-theme option (or "dark") but accepts an explicit theme name, which
# the tests use. Applies the suspended dimming overrides when in that mode.
load_theme () {
  local theme="${1:-$(get_tmux_option @airline-theme "dark")}" key
  tmux source-file "$CURRENT_DIR/themes/$theme"

  for key in outer-bg middle-bg inner-bg secondary primary emphasized \
             active special ok alert stress zoom copy monitor; do
    THEME[$key]=$(get_tmux_option "@airline-$key")
  done

  if [[ "$(get_tmux_option @airline-suspended 0)" == "1" ]]; then
    apply_suspended_overrides
  fi
}

#-----------------------------------------------------------------------------#
#
# Chevrons
#
#-----------------------------------------------------------------------------#

chevron () {
  local left_bg="$1"
  local right_bg="$2"
  local chev="$3"

  echo "#[fg=$right_bg,bg=$left_bg]$chev"
}

chev_right () {
  local left_bg="$1"
  local right_bg="$2"
  chevron "$right_bg" "$left_bg" ""
}

chev_left () {
  local left_bg="$1"
  local right_bg="$2"
  chevron "$left_bg" "$right_bg" ""
}

#-----------------------------------------------------------------------------#
#
# Per-window signal
#
#-----------------------------------------------------------------------------#

# Build a tmux format expression that maps a window-scoped option holding a
# palette token (active, alert, stress, …) to its theme color, falling back to
# $fallback when the option is empty or holds an unknown token. Evaluated per
# window at render time. The token list (AIRLINE_PALETTE_TOKENS) lives in one
# place, so every presentation of the signal resolves the color identically.
palette_token_expr () {
  local option="$1" fallback="$2"
  local expr="$fallback" tok
  for tok in "${AIRLINE_PALETTE_TOKENS[@]}"; do
    expr="#{?#{==:#{$option},$tok},${THEME[$tok]},$expr}"
  done
  printf '%s' "$expr"
}

# Fixed pane-focus-out hook index for airline's consume-on-view hook. Assigning
# the hook to an explicit array index makes registration idempotent: main()
# re-runs on every config reload and on each F12 suspend/resume (both re-source
# this file), and `set-hook -ga` *appends*, so re-running would stack duplicate
# copies and they'd fire N times per unfocus. A specific index replaces in place
# instead. A high index keeps airline clear of any hooks a user or other plugin
# appends with `-ga` (those auto-fill from 0).
AIRLINE_HOOK_IDX_SIGNAL=90

# Clear a window's signal when it loses focus — but only if the setter marked it
# transient via @airline-window-signal-transient. This is the "consume-on-view"
# lifecycle: a setter that cannot observe when its signal has been seen (e.g. an
# agent's finished state) marks it transient, and airline clears it once you've
# viewed the window and moved on. Signals without the flag are left alone — their
# setter owns clearing. The lifecycle is about the signal, not its presentation,
# so one hook covers every style. Registered once, here, so plugins don't each
# add a focus hook (which would collide on the shared option). Pinned to a fixed
# index so re-running main() replaces rather than stacks. Requires
# `focus-events on`.
register_window_signal_clear () {
  tmux set-hook -g "pane-focus-out[$AIRLINE_HOOK_IDX_SIGNAL]" \
    "if-shell -F '#{@airline-window-signal-transient}' 'set -wu @airline-window-signal ; set -wu @airline-window-signal-transient ; refresh-client -S'"
}

#-----------------------------------------------------------------------------#
#
# Build status line components
#
#-----------------------------------------------------------------------------#

left_outer () {
  local fg="${THEME[emphasized]}"
  local bg="${THEME[outer-bg]}"
  local next_bg="${THEME[middle-bg]}"
  local template="$(tmpl_ref @airline_tmpl_left_outer "$(configure_online)")"

  echo "#[fg=$fg,bg=$bg] ${template} $(chev_right "$bg" "$next_bg")"
}

left_middle () {
  local fg="${THEME[emphasized]}"
  local bg="${THEME[middle-bg]}"
  local next_bg="${THEME[inner-bg]}"
  local template="$(tmpl_ref @airline_tmpl_left_middle "$(hostname | cut -d '.' -f 1)")"

  echo "#[fg=$fg,bg=$bg] ${template} $(chev_right "$bg" "$next_bg") "
}

set_window_formats () {
  local template="$(get_tmux_option @airline_tmpl_window '#I:#W')"
  local bg="${THEME[inner-bg]}"
  local hi="${THEME[active]}"
  local glyph="$(get_tmux_option @airline-window-signal-glyph "●")"

  # Per-window signal (@airline-window-signal): a palette token airline renders
  # on a window. How it renders is the per-window option @airline-window-style:
  #   color (default) recolors the entry; badge appends a glyph after the name;
  #   both does each. Resolved per window on every redraw, so changes show live.
  # airline neither knows nor cares what sets the signal — any tool can drive it.
  local sig="@airline-window-signal"
  local color="$(palette_token_expr "$sig" "${THEME[primary]}")"
  local is_badge="#{==:#{@airline-window-style},badge}"   # style suppresses recolor
  # glyph shown for style 'badge' OR 'both':
  local is_glyph="#{?#{==:#{@airline-window-style},badge},1,#{==:#{@airline-window-style},both}}"

  # color/both: recolor — fg on inactive windows, bg on the active one (below).
  # badge: no recolor. Unset signal → empty, so normal/last/activity/bell apply.
  local fg_override="#{?$sig,#{?$is_badge,,#[fg=$color]},}"
  # badge/both: a colored glyph appended after the name.
  local badge="#{?$sig,#{?$is_glyph, #[fg=$color]$glyph,},}"

  # default window treatments
  tmux set -gq window-status-separator-string " "
  tmux set -gq window-status-format "${fg_override}${template}${badge}"

  # window styles
  tmux set -gq window-status-style "fg=${THEME[primary]} bg=$bg"
  tmux set -gq window-status-last-style "fg=${THEME[emphasized]} bg=$bg"
  tmux set -gq window-status-activity-style "fg=${THEME[alert]} bg=$bg"
  tmux set -gq window-status-bell-style "fg=${THEME[stress]} bg=$bg"

  # current window: under color/both the highlight bg becomes the signal color
  # (chevrons follow it); under badge — or with no signal — it stays the normal
  # active highlight. Both flanking chevrons take fg=inner-bg so the active entry
  # reads as one filled block (dark text on the highlight bg).
  local hi_expr="#{?$is_badge,$hi,$(palette_token_expr "$sig" "$hi")}"
  tmux set -gq window-status-current-format "$(chev_right "$bg" "$hi_expr") $template${badge} $(chev_left "$hi_expr" "$bg")"
}

right_inner () {
  local fg="${THEME[inner-bg]}"
  local bg="${THEME[inner-bg]}"
  local template="$(tmpl_ref @airline_tmpl_right_inner "$(configure_prefix_highlight)")"

  echo "#[fg=$fg,bg=$bg]${template}"
}

right_middle () {
  local fg="${THEME[emphasized]}"
  local bg="${THEME[middle-bg]}"
  local prev_bg="${THEME[inner-bg]}"
  local template="$(tmpl_ref @airline_tmpl_right_middle "$(configure_cpu)")"

  echo "$(chev_left $prev_bg $bg)#[fg=$fg,bg=$bg] $template"
}

right_outer () {
  local fg="${THEME[emphasized]}"
  local bg="${THEME[outer-bg]}"
  local prev_bg="${THEME[middle-bg]}"
  local default="%Y-%m-%d %H:%M"
  local battery="$(configure_battery)"
  [[ -n "$battery" ]] && default="$default $battery"
  local template="$(tmpl_ref @airline_tmpl_right_outer "$default")"

  echo "$(chev_left $prev_bg $bg)#[fg=$fg,bg=$bg] ${template}"
}

#-----------------------------------------------------------------------------#
#
# Set status elements
#
#-----------------------------------------------------------------------------#

main () {
  # TODO: is this needed?
  # TODO: what is mode-style?
  #tmux set -gq mode-style "fg=${THEME[special]} bg=${THEME[alert]}"
  # tmux set -gq message-command-style

  # Configure panes, use highlight color for active panes
  tmux set -gq pane-border-style "fg=${THEME[primary]}"
  tmux set -gq pane-active-border-style "fg=${THEME[active]}"
  tmux set -gq display-panes-color "${THEME[primary]}"
  tmux set -gq display-panes-active-color "${THEME[active]}"

  # Build the status bar
  tmux set -gq status-style "fg=${THEME[secondary]} bg=${THEME[inner-bg]}"

  # Configure window status
  set_window_formats
  register_window_signal_clear

  tmux set -gq status-left-style "fg=${THEME[primary]} bg=${THEME[outer-bg]}"
  tmux set -gq status-left "$(left_outer) $(left_middle)"

  tmux set -gq status-right-style "fg=${THEME[primary]} bg=${THEME[outer-bg]}"
  tmux set -gq status-right "$(right_inner) $(right_middle) $(right_outer)"

  tmux set -gq clock-mode-color "${THEME[special]}"

  tmux bind -T root F12 run-shell "$CURRENT_DIR/scripts/suspend.sh"
  tmux bind -T off  F12 run-shell "$CURRENT_DIR/scripts/resume.sh"

}

if [[ "${AIRLINE_TESTING:-}" != "1" ]]; then
  load_theme
  main
fi
