#!/usr/bin/env bash

CURRENT_DIR="${AIRLINE_DIR:-$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )}"

source "$CURRENT_DIR/scripts/shared.sh"
source "$CURRENT_DIR/scripts/is_installed.sh"
source "$CURRENT_DIR/scripts/plugins/online.sh"
source "$CURRENT_DIR/scripts/plugins/prefix_highlight.sh"
source "$CURRENT_DIR/scripts/plugins/cpu.sh"
source "$CURRENT_DIR/scripts/plugins/battery.sh"

# use an associative array to hold the theme
declare -A THEME

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

if [[ "${AIRLINE_TESTING:-}" != "1" ]]; then

local theme
theme=$(get_tmux_option @airline-theme "dark")
tmux source-file "$CURRENT_DIR/themes/$theme"

# Populate THEME from tmux options (set by the theme file above)
THEME[outer-bg]=$(get_tmux_option @airline-outer-bg)
THEME[middle-bg]=$(get_tmux_option @airline-middle-bg)
THEME[inner-bg]=$(get_tmux_option @airline-inner-bg)
THEME[secondary]=$(get_tmux_option @airline-secondary)
THEME[primary]=$(get_tmux_option @airline-primary)
THEME[emphasized]=$(get_tmux_option @airline-emphasized)
THEME[active]=$(get_tmux_option @airline-active)
THEME[special]=$(get_tmux_option @airline-special)
THEME[ok]=$(get_tmux_option @airline-ok)
THEME[alert]=$(get_tmux_option @airline-alert)
THEME[stress]=$(get_tmux_option @airline-stress)
THEME[zoom]=$(get_tmux_option @airline-zoom)
THEME[copy]=$(get_tmux_option @airline-copy)
THEME[monitor]=$(get_tmux_option @airline-monitor)

if [[ "$(get_tmux_option @airline-suspended 0)" == "1" ]]; then
  apply_suspended_overrides
fi

fi

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
# Per-window color override
#
#-----------------------------------------------------------------------------#

# Resolve the per-window @airline-window-color option to a theme color. The
# option holds one of airline's palette tokens (active, alert, stress, …); this
# returns a tmux format expression, evaluated per window at render time, that
# maps the token to its color and falls back to $1 when the option is empty or
# an unknown token. airline neither knows nor cares what sets the option — it
# just colors a window the requested palette color. Used as fg on inactive
# windows and as bg on the active window.
window_color_expr () {
  local fallback="$1"
  local expr="$fallback"
  local tok
  for tok in active alert stress ok special monitor copy zoom; do
    expr="#{?#{==:#{@airline-window-color},$tok},${THEME[$tok]},$expr}"
  done
  printf '%s' "$expr"
}

# Per-window notification badge (@airline-window-badge). Where window_color_expr
# repaints the whole entry, the badge appends a small colored glyph *after* the
# window name and leaves the entry's normal styling intact — a less intrusive
# "this window wants attention" marker. It carries the same palette tokens and
# is driven the same way: set the window-scoped option to a token, unset to
# clear. Returns a tmux format expression, evaluated per window at render time,
# that emits the glyph in the token's color when the option is set (falling back
# to the primary color on an unknown token) and nothing when it's empty. The
# glyph is configurable via @airline-window-badge-glyph (default ●).
window_badge () {
  local glyph expr tok
  glyph=$(get_tmux_option @airline-window-badge-glyph "●")
  expr="${THEME[primary]}"
  for tok in active alert stress ok special monitor copy zoom; do
    expr="#{?#{==:#{@airline-window-badge},$tok},${THEME[$tok]},$expr}"
  done
  printf '%s' "#{?@airline-window-badge, #[fg=$expr]$glyph,}"
}

# Clear a window's color when it loses focus — but only if the setter marked it
# transient via @airline-window-color-transient. This is the "consume-on-view"
# lifecycle: a setter that cannot observe when its color has been seen (e.g. an
# agent's finished state) marks it transient, and airline clears it once you've
# viewed the window and moved on. Colors without the flag are left alone — their
# setter owns clearing. Registered once, here, so plugins don't each add a focus
# hook (which would collide on the shared option). Requires `focus-events on`.
register_window_color_clear () {
  tmux set-hook -ga pane-focus-out \
    "if-shell -F '#{@airline-window-color-transient}' 'set -wu @airline-window-color ; set -wu @airline-window-color-transient ; refresh-client -S'"
}

# Same consume-on-view lifecycle as register_window_color_clear, for the badge:
# clear @airline-window-badge on unfocus when @airline-window-badge-transient is
# set. Appended as a separate hook so the badge and color lifecycles stay
# independent (a window's badge can be transient while its color isn't, or vice
# versa). Like the color hook, requires `focus-events on`.
register_window_badge_clear () {
  tmux set-hook -ga pane-focus-out \
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

  # Per-window color override (see window_color_expr): when a window sets
  # @airline-window-color to a palette token, inactive windows take the color
  # as fg here; the active window takes it as bg below. Unset → unchanged, so
  # the normal/last/activity/bell styles still apply.
  local fg_override="#{?@airline-window-color,#[fg=$(window_color_expr "${THEME[primary]}")],}"

  # Per-window notification badge (see window_badge): a colored glyph appended
  # after the name when @airline-window-badge is set. Independent of the color
  # override above — a window can carry either, both, or neither.
  local badge="$(window_badge)"

  # default window treatments
  tmux set -gq window-status-separator-string " "
  tmux set -gq window-status-format "${fg_override}${template}${badge}"

  # window styles
  tmux set -gq window-status-style "fg=${THEME[primary]} bg=$bg"
  tmux set -gq window-status-last-style "fg=${THEME[emphasized]} bg=$bg"
  tmux set -gq window-status-activity-style "fg=${THEME[alert]} bg=$bg"
  tmux set -gq window-status-bell-style "fg=${THEME[stress]} bg=$bg"

  # special case for current window: the highlight bg becomes the override
  # color when set (chevrons follow it), else the normal active highlight.
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
  main
fi
