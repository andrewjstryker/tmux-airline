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
# order. Single source of truth for palette_token_expr, used by both per-window
# channels (color and badge). -ga for the same sourced-in-a-function reason as
# THEME above.
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
# Per-window color and badge
#
#-----------------------------------------------------------------------------#

# Build a tmux format expression that maps a window-scoped option holding a
# palette token (active, alert, stress, …) to its theme color, falling back to
# $fallback when the option is empty or holds an unknown token. Evaluated per
# window at render time. The token list (AIRLINE_PALETTE_TOKENS) lives in one
# place, so per-window color and badge resolve identically.
palette_token_expr () {
  local option="$1" fallback="$2"
  local expr="$fallback" tok
  for tok in "${AIRLINE_PALETTE_TOKENS[@]}"; do
    expr="#{?#{==:#{$option},$tok},${THEME[$tok]},$expr}"
  done
  printf '%s' "$expr"
}

# Resolve the per-window @airline-window-color override to a theme color.
# airline neither knows nor cares what sets the option — it just colors a window
# the requested palette color. Used as fg on inactive windows and as bg on the
# active window. This is the meter-style channel: a sustained condition shown by
# recoloring the entry (e.g. a resource — like a context window — under pressure).
window_color_expr () {
  palette_token_expr @airline-window-color "$1"
}

# Per-window badge (@airline-window-badge). Where window_color_expr repaints the
# whole entry, the badge appends a small colored glyph *after* the window name
# and leaves the entry's normal styling intact — the event-style channel (a
# discrete state worth a glance, e.g. an agent that's working/waiting/done). It
# carries the same palette tokens and is driven the same way: set the
# window-scoped option to a token, unset to clear. Returns a tmux format
# expression, evaluated per window at render time, that emits the glyph in the
# token's color when set (falling back to primary on an unknown token) and
# nothing when empty. The glyph is configurable via @airline-window-badge-glyph
# (default ●). Independent of the color channel — a window can carry either,
# both, or neither.
window_badge () {
  local glyph
  glyph=$(get_tmux_option @airline-window-badge-glyph "●")
  printf '%s' "#{?@airline-window-badge, #[fg=$(palette_token_expr @airline-window-badge "${THEME[primary]}")]$glyph,}"
}

# Fixed pane-focus-out hook indices for airline's two consume-on-view hooks.
# Assigning a hook to an explicit array index makes registration idempotent:
# main() re-runs on every config reload and on each F12 suspend/resume (both
# re-source this file), and `set-hook -ga` *appends*, so re-running would stack
# duplicate copies of these hooks and they'd fire N times per unfocus. Setting a
# specific index replaces in place instead. High indices keep airline clear of
# any hooks a user or other plugin appends with `-ga` (those auto-fill from 0).
AIRLINE_HOOK_IDX_COLOR=90
AIRLINE_HOOK_IDX_BADGE=91

# Clear a window's color when it loses focus — but only if the setter marked it
# transient via @airline-window-color-transient. This is the "consume-on-view"
# lifecycle: a setter that cannot observe when its color has been seen (e.g. an
# agent's finished state) marks it transient, and airline clears it once you've
# viewed the window and moved on. Colors without the flag are left alone — their
# setter owns clearing. Registered once, here, so plugins don't each add a focus
# hook (which would collide on the shared option). Pinned to a fixed index so
# re-running main() replaces rather than stacks (see AIRLINE_HOOK_IDX_COLOR).
# Requires `focus-events on`.
register_window_color_clear () {
  tmux set-hook -g "pane-focus-out[$AIRLINE_HOOK_IDX_COLOR]" \
    "if-shell -F '#{@airline-window-color-transient}' 'set -wu @airline-window-color ; set -wu @airline-window-color-transient ; refresh-client -S'"
}

# Same consume-on-view lifecycle as register_window_color_clear, for the badge:
# clear @airline-window-badge on unfocus when @airline-window-badge-transient is
# set. A separate hook (its own fixed index) so the badge and color lifecycles
# stay independent (a window's badge can be transient while its color isn't, or
# vice versa). Idempotent for the same reason as the color hook. Like it,
# requires `focus-events on`.
register_window_badge_clear () {
  tmux set-hook -g "pane-focus-out[$AIRLINE_HOOK_IDX_BADGE]" \
    "if-shell -F '#{@airline-window-badge-transient}' 'set -wu @airline-window-badge ; set -wu @airline-window-badge-transient ; refresh-client -S'"
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

  # Per-window color channel (see window_color_expr): when a window sets
  # @airline-window-color to a palette token, inactive windows take the color
  # as fg here; the active window takes it as bg below. Unset → unchanged, so
  # the normal/last/activity/bell styles still apply.
  local fg_override="#{?@airline-window-color,#[fg=$(window_color_expr "${THEME[primary]}")],}"

  # Per-window badge channel (see window_badge): a colored glyph appended after
  # the name when @airline-window-badge is set. Independent of the color channel
  # above — a window can carry either, both, or neither.
  local badge="$(window_badge)"

  # default window treatments
  tmux set -gq window-status-separator-string " "
  tmux set -gq window-status-format "${fg_override}${template}${badge}"

  # window styles
  tmux set -gq window-status-style "fg=${THEME[primary]} bg=$bg"
  tmux set -gq window-status-last-style "fg=${THEME[emphasized]} bg=$bg"
  tmux set -gq window-status-activity-style "fg=${THEME[alert]} bg=$bg"
  tmux set -gq window-status-bell-style "fg=${THEME[stress]} bg=$bg"

  # special case for current window: the highlight bg becomes the color-channel
  # token when set (chevrons follow it), else the normal active highlight.
  # The active window reads as one filled block — dark text on the highlight bg
  # — so both flanking chevrons take fg=inner-bg (their leading edge matches the
  # neighbouring window's bg, the trailing edge fills with the highlight).
  local hi_expr="$(window_color_expr "$hi")"
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
  register_window_color_clear
  register_window_badge_clear

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
