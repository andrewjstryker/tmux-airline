#!/usr/bin/env bash
#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-#
# update_status_line.sh
#
# Sets the status-{left,right} and window-status-* using the current theme.
#
# TODO:
#   - Discover the effects of
#     * mode-style
#     * message-style
#     * message-command-style
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
  local current="$(get_tmux_option @airline-theme-current)"
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
    "$(chev_right $bg $current) $format $(chev_left $current $bg)"
}

#-----------------------------------------------------------------------------#
#
# Left status line
#
#-----------------------------------------------------------------------------#

left_outer () {
  local fg="$(get_tmux_option @airline-theme-primary)"
  local bg="$(get_tmux_option @airline-theme-outer-bg)"
  local next_bg="$(get_tmux_option @airline-theme-middle-bg)"
  local format="$(get_tmux_option @airline-status-left-outer)"

  echo "#[fg=$fg,bg=$bg] $format $(chev_right $bg $next_bg)"
}

left_middle () {
  local fg="$(get_tmux_option @airline-theme-emphasized)"
  local bg="$(get_tmux_option @airline-theme-middle-bg)"
  local next_bg="$(get_tmux_option @airline-theme-inner-bg)"
  local format="$(get_tmux_option @airline-status-left-middle)"

  echo "#[fg=$fg,bg=$bg] $format $(chev_right $bg $next_bg)"
}

left_inner () {
  local fg="$(get_tmux_option @airline-theme-primary)"
  local bg="$(get_tmux_option @airline-theme-inner-bg)"
  local format="$(get_tmux_option @airline-status-left-inner)"

  echo "#[fg=$fg,bg=$bg] $format"
}

#-----------------------------------------------------------------------------#
#
# Right status line
#
#-----------------------------------------------------------------------------#

right_inner () {
  local fg="$(get_tmux_option @airline-theme-primary)"
  local bg="$(get_tmux_option @airline-theme-inner-bg)"
  local next_bg="$(get_tmux_option @airline-theme-middle-bg)"
  local format="$(get_tmux_option @airline-status-right-inner)"

  echo "#[fg=$fg,bg=$bg]$format $(chev_right $bg $next_bg)"
}

right_middle () {
  local fg="$(get_tmux_option @airline-theme-emphasized)"
  local bg="$(get_tmux_option @airline-theme-middle-bg)"
  local next_bg="$(get_tmux_option @airline-theme-outer-bg)"
  local format="$(get_tmux_option @airline-status-right-middle)"

  echo "#[fg=$fg,bg=$bg] $format $(chev_right $bg $next_bg)"
}

right_outer () {
  local fg="$(get_tmux_option @airline-theme-primary)"
  local bg="$(get_tmux_option @airline-theme-outer-bg)"
  local format="$(get_tmux_option @airline-status-right-outer)"

  echo "#[fg=$fg,bg=$bg] $format "
}

#-----------------------------------------------------------------------------#
#
# Panes
#
#-----------------------------------------------------------------------------#

set_panes () {
  local primary="$(get_tmux_option @airline-theme-primary)"
  local current="$(get_tmux_option @airline-theme-current)"

  # pane borders
  set_tmux_option pane-border-style "fg=$primary"
  set_tmux_option pane-current-border-style "fg=$current"

  # display-panes command
  set_tmux_option display-panes-color "$primary"
  set_tmux_option display-panes-active-color "$current"
}

#-----------------------------------------------------------------------------#
#
# Message
#
#-----------------------------------------------------------------------------#

set_messages () {
  local alert="$(get_tmux_option @airline-theme-alert)"
  local primary="$(get_tmux_option @airline-theme-primary)"

  set_tmux_option message-command-style "fg=$primary bg=$alert"
}

#-----------------------------------------------------------------------------#
#
# Clock
#
#-----------------------------------------------------------------------------#

set_clock () {
  local special="$(get_tmux_option @airline-theme-special)"

  set_tmux_option clock-mode-color "$special"
}

#-----------------------------------------------------------------------------#
#
# Script entry point
#
#-----------------------------------------------------------------------------#

main () {
  # only apply theme when needed
  if (( "$(get_tmux_option @airline-interal-theme-refresh 1)" ))
  then
    set_window_status
    set_tmux_option status-left "$(left_outer)$(left_middle)$(left_inner)"
    set_tmux_option status-right "$(right_inner)$(right_middle)$(right_outer)"
    set_panes
    set_messages
    set_clock

    set_tmux_option @airline-internal-theme-refresh 0
  fi
}

main

# vim: sts=2 sw=2 et
