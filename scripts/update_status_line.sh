#!/usr/bin/env bash
#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-#
# update_status_line.sh
#
# Sets the status-{left,right} and window-status-* using the current theme.
#
#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-#

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source "$CURRENT_DIR/shared.sh"

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
# Window status
#
#-----------------------------------------------------------------------------#

set_window_status () {
  local bg="$(get_tmux_option @airline-theme-inner-bg)"
  local primary="$(get_tmux_option @airline-theme-primary)"
  local emphasized="$(get_tmux_option @airline-theme-emphasized)"
  local active="$(get_tmux_option @airline-theme-active)"
  local special="$(get_tmux_option @airline-theme-special)"
  local alert="$(get_tmux_option @airline-theme-alert)"
  local format="$(get_tmux_option @airline-window-format)"

  # default window treatments
  set_tmux_option window-status-separator-string " "
  set_tmux_option window-status-format "$format"

  # window styles
  set_tmux_option window-status-style "fg=$primary bg=$bg"
  set_tmux_option window-status-last-style "fg=$emphasized bg=$bg"
  set_tmux_option window-status-bell-style "fg=$alert bg=$bg"
  set_tmux_option window-status-activity-style "fg=$special bg=$bg"

  # special case for current window
  set_tmux_option window-status-current-format \
    "$(chev_right $bg $active) $format $(chev_left $active $bg)"
}


main () {
  set_window_status
}

# vim: sts=2 sw=2 et
