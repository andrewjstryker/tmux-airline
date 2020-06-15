#!/usr/bin/env bash
#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-#
# update.sh
#
# Set the status-{left,right} and window-status-* from status and theme
# elements.
#
# TODO:
#   - Discover the effects of
#     * mode-style
#     * message-style
#     * message-command-style
#   - Make chevron characters parameters
#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-#

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source "$CURRENT_DIR/api.sh"

#-----------------------------------------------------------------------------#
#
# Chevrons
#
#-----------------------------------------------------------------------------#

chevron () {
  local left_bg="$1"
  local right_bg="$2"
  local right_fg="$3"
  local chev="$4"

  echo "#[fg=$right_bg,bg=$left_bg]$chev[fg=$right_fg,bg=$right_bg]"
}

chev_right () {
  local left_bg="$1"
  local right_bg="$2"
  local right_fg="$3"

  chevron "$left_bg" "$right_bg" "$right_fg" ""
}

chev_left () {
  local left_bg="$1"
  local right_bg="$2"
  local right_fg="$3"

  chevron "$left_bg" "$right_bg" "$right_fg" ""
}

#-----------------------------------------------------------------------------#
#
# Left status line
#
#-----------------------------------------------------------------------------#

left_outer () {
  local fg="$(airline_show theme emphasized)"
  local outer="$(airline_show theme outer)"
  local status="$(airline_show status left-outer)"
  local hook="#($CURRENT_DIR/../airline.tmux update)"

  echo "$hook#[fg=$fg,bg=$outer]$status"
}

left_middle () {
  local fg="$(airline_show theme emphasized)"
  local middle="$(airline_show theme middle)"
  local outer="$(airline_show theme outer)"
  local status="$(airline_show status left-middle)"

  echo "$(chev_right $outer $middle $fg)$status"
}

left_inner () {
  local fg="$(airline_show theme primary)"
  local inner="$(airline_show theme inner)"
  local middle="$(airline_show theme middle)"
  local status="$(airline_show status left-inner)"

  echo "$(chev_right $middle $inner $fg)$status"
}

#-----------------------------------------------------------------------------#
#
# Right status line
#
#-----------------------------------------------------------------------------#

right_inner () {
  local fg="$(airline_show theme primary)"
  local inner="$(airline_show theme inner)"
  local status="$(airline_show status right-inner)"

  echo "#[fg=$get_theme_primary),bg=$(get_theme_inner)]$status"
}

right_middle () {
  local fg="$(airline_show theme emphasized)"
  local inner="$(airline_show theme inner)"
  local middle="$(airline_show theme middle)"
  local status="$(airline_show status right-middle)"

  echo "$(chev_right $inner $middle $fg)$status"
}

right_outer () {
  local fg="$(airline_show theme emphasized)"
  local middle="$(airline_show theme middle)"
  local outer="$(airline_show theme outer)"
  local status="$(airline_show status right-outer)"

  echo "$(chev_right $middle $outer $fg)$status"
}

set_status () {
  local primary="$(airline_show theme primary)"
  local current="$(airline_show theme current)"
  local inner="$(airline_show theme inner)"

  set_tmux_option status-style "fg=$primary bg=$inner"
  set_tmux_option status-left "$(left_outer)$(left_middle)$(left_inner)"
  set_tmux_option status-right "$(right_inner)$(right_middle)$(right_outer)"
}

#-----------------------------------------------------------------------------#
#
# Windows
#
#-----------------------------------------------------------------------------#

set_window () {
  local inner="$(airline_show theme inner)"
  local current="$(airline_show theme current)"
  local primary="$(airline_show theme primary)"
  local emphasized="$(airline_show theme emphasized)"
  local alert="$(airline_show theme alert)"
  local special="$(airline_show theme special)"

  set_tmux_option window-status-format "$(get_status_window)"

  set_tmux_option window-status-current-format \
    "$(chev_right $inner $current $inner) $(get_status_window) $(chev_left $current $inner $inner)"

  set_tmux_option window-status-separator-string " "

  # window styles
  set_tmux_option window-status-style "fg=$primary bg=$inner"
  set_tmux_option window-status-last-style "fg=$emphasized bg=$inner"
  set_tmux_option window-status-bell-style "fg=$alert bg=$inner"
  set_tmux_option window-status-activity-style "fg=$special bg=$inner"
}

#-----------------------------------------------------------------------------#
#
# Panes
#
#-----------------------------------------------------------------------------#

set_panes () {
  local primary="$(airline_show theme primary)"
  local current="$(airline_show theme current)"

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
  local alert="$(airline_show theme alert)"
  local primary="$(airline_show theme primary)"

  set_tmux_option message-command-style "fg=$primary bg=$alert"
}

#-----------------------------------------------------------------------------#
#
# Clock
#
#-----------------------------------------------------------------------------#

set_clock () {
  local special="$(airline_show theme special)"

  set_tmux_option clock-mode-color "$special"
}

#-----------------------------------------------------------------------------#
#
# Script entry point
#
#-----------------------------------------------------------------------------#

update () {
  # only apply theme when needed
  if [[ ! _airline_refresh_needed ]]
  then
    exit 0
  fi

  set_status
  set_windows
  set_panes
  set_messages
  set_clock

  _airline_refresh_clear
}


if [[ "${BASH_SOURCE[0]}" = "${0}" ]]
then
  init "$@"
  exit "$?"
fi

export -f update

# vim: sts=2 sw=2 et
