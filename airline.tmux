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
# Build status line components
#
#-----------------------------------------------------------------------------#

left_outer () {
  local fg="${THEME[emphasized]}"
  local bg="${THEME[outer-bg]}"
  local next_bg="${THEME[middle-bg]}"
  local template="$(get_tmux_option @airline_tmpl_left_outer '')"
  [[ -z "$template" ]] && template="$(configure_online)"

  echo "#[fg=$fg,bg=$bg] ${template} $(chev_right "$bg" "$next_bg")"
}

left_middle () {
  local fg="${THEME[emphasized]}"
  local bg="${THEME[middle-bg]}"
  local next_bg="${THEME[inner-bg]}"
  local template="$(get_tmux_option @airline_tmpl_left_middle '')"

  if [[ -z "$template" ]]
  then
    template="$(hostname | cut -d '.' -f 1)"
  fi

  echo "#[fg=$fg,bg=$bg] ${template} $(chev_right "$bg" "$next_bg") "
}

set_window_formats () {
  local template="$(get_tmux_option @airline_tmpl_window '#I:#W')"
  local bg="${THEME[inner-bg]}"
  local hi="${THEME[active]}"

  # default window treatments
  tmux set -gq window-status-separator-string " "
  tmux set -gq window-status-format "$template"

  # window styles
  tmux set -gq window-status-style "fg=${THEME[primary]} bg=$bg"
  tmux set -gq window-status-last-style "fg=${THEME[emphasized]} bg=$bg"
  tmux set -gq window-status-activity-style "fg=${THEME[alert]} bg=$bg"
  tmux set -gq window-status-bell-style "fg=${THEME[stress]} bg=$bg"

  # special case for current window
  tmux set -gq window-status-current-format "$(chev_right $bg $hi) $template $(chev_left $hi $bg)"
}

right_inner () {
  local fg="${THEME[inner-bg]}"
  local bg="${THEME[inner-bg]}"
  local template="$(tmux show-option -gqv @airline_tmpl_right_inner)"
  [[ -z "$template" ]] && template="$(configure_prefix_highlight)"

  echo "#[fg=$fg,bg=$bg]${template}"
}

right_middle () {
  local fg="${THEME[emphasized]}"
  local bg="${THEME[middle-bg]}"
  local prev_bg="${THEME[inner-bg]}"
  local template="$(get_tmux_option @airline_tmpl_right_middle '')"
  [[ -z "$template" ]] && template="$(configure_cpu)"

  echo "$(chev_left $prev_bg $bg)#[fg=$fg,bg=$bg] $template"
}

right_outer () {
  local fg="${THEME[emphasized]}"
  local bg="${THEME[outer-bg]}"
  local prev_bg="${THEME[middle-bg]}"
  local template="$(get_tmux_option @airline_tmpl_right_outer '')"

  if [[ -z "$template" ]]; then
    template="%Y-%m-%d %H:%M"
    local battery="$(configure_battery)"
    [[ -n "$battery" ]] && template="$template $battery"
  fi

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
