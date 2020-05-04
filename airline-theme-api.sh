#!/usr/bin/env bash
#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-#
# airline-api.sh
#
# Provide an API to status line elements.
#
# This API hides the implementation details of managing themes. The biggest
# benefit is that the API records when theme elements changed. This allows API
# users to update only when needed.
#
#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-#

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source "$CURRENT_DIR/scripts/shared.sh"

AIRLINE_PREFIX="@airline"
AIRLINE_REFRESH_FLAG="${AIRLINE_PREFIX}-refresh"

#-----------------------------------------------------------------------------#
#
# Internal functions
#
#-----------------------------------------------------------------------------#

_set_theme_element () {
  local element="$1"
  local value="$2"

  set_tmux_option "${AIRLINE_REFRESH_FLAG}" 1
  _set_airline "${AIRLINE_PREFIX}-theme-$element" "$value"
}

_get_theme_element () {
  local element="$1"
  local default="$2"

  get_tmux_option "${AIRLINE_PREFIX}-theme-$element" "$default"
}

_set_status_element () {
  local element="$1"
  local value="$2"

  set_tmux_option "${AIRLINE_REFRESH_FLAG}" 1
  _set_airline "${AIRLINE_PREFIX}-status-$element" "$value"
}

_get_status_element () {
  local element="$1"

  # clients need to test for empty strings
  tmux show-option -gqv "${AIRLINE_PREFIX}-status-$element"
}

#-----------------------------------------------------------------------------#
#
# User functions
#
#-----------------------------------------------------------------------------#

airline_refresh_needed () {
  # note numerical testing
  if (( "$(get_tmux_option "${AIRLINE_REFRESH_FLAG}" "1" )" ))
  then
    return 1
  fi

  return 0
}

airline_refresh_clear () {
  set_tmux_option "${AIRLINE_REFRESH_FLAG}" 0
}

airline_load () {
  local theme="$1"

  # theme a readable file?
  if [[ -r "$theme" && -f "$theme" ]]
  then
    source "$theme"
    return
  fi

  # theme part of airline's default themes?
  local target="$CURRENT_DIR/themes/$theme"
  if [[ -r "$target" && -f "$target" ]]
  then
    source "$target"
    return
  fi

  # could not load theme
  return 1
}

#-----------------------------------------------------------------------------#
#
# Theme elements
#
#-----------------------------------------------------------------------------#

# primary text color (foreground)
set_primary () {
  _set_theme_element primary "$1"
}

get_primary () {
  _get_theme_element primary white
}

# secondary text color (foreground)
set_secondary () {
  _set_theme_element secondary "$1"
}

get_secondary () {
  _get_theme_element secondary white
}

# emphasized text color (foreground)
set_emphasized () {
  _set_theme_element emphasized "$1"
}

get_emphasized () {
  _get_theme_element emphasized brightwhite
}

# outer background
set_outer () {
  _set_theme_element outer "$1"
}

get_outer () {
  _get_theme_element outer brightgreen
}

# middle background
set_middle () {
  _set_theme_element middle "$1"
}

get_middle () {
  _get_theme_element middle green
}

# inner background
set_inner () {
  _set_theme_element inner "$1"
}

get_inner () {
  _get_theme_element inner black
}

# current/active elements (highlight)
set_current () {
  _set_theme_element current "$1"
}

get_current () {
  _get_theme_element current brightyellow
}

# alert to get user's attention
set_alert () {
  _set_theme_element alert "$1"
}

get_alert () {
  _get_theme_element alert yellow
}

# stress, draw attention to high loads/resources nearing limits
set_stress () {
  _set_theme_element stress "$1"
}

get_stress () {
  _get_theme_element stress red
}

# copy mode
set_copy () {
  _set_theme_element copy "$1"
}

get_copy () {
  _get_theme_element copy blue
}

# window zoomed
set_theme_zoom () {
  _set_theme_element zoom "$1"
}

get_theme_zoom () {
  _get_theme_element zoom blue
}

# window monitoring
set_theme_monitor () {
  _set_theme_element monitor "$1"
}

get_theme_monitor () {
  _get_theme_element monitor blue
}

# "special" state (e.g., prefix key active)
set_special () {
  _set_theme_element special "$1"
}

get_special () {
  _get_theme_element special magenta
}

#-----------------------------------------------------------------------------#
#
# Status line components
#
#-----------------------------------------------------------------------------#

set_status_left_outer () {
  _set_status_element "left-outer" "$1"
}

get_status_left_outer () {
  local status

  status=$(_get_status_element "left-outer")

  if [[ -z $status ]]
  then
    if [[ $(is_online_installed) ]]
    then
      status="$status #(online_status)"
    fi
    set_status_left_outer "$status"
  fi

  echo "$status"
}

set_status_left_middle () {
  _set_status_element "left-middle" "$1"
}

get_status_left_middle () {
  local status

  status=$(_get_status_element "left-middle")

  if [[ -z $status ]]
  then
    status="$(_get_status_element "left-inner") > #S"
    set_status_left_middle "$status"
  fi

  echo "$status"
}

set_status_left_inner () {
  _set_status_element "left-inner" "$1"
}

get_status_left_inner () {
  local status

  _get_status_element "left-inner"

  if [[ -z $status ]]
  then
    status=" "
    set_status_left_inner "$status"
  fi

  echo "$status"
}

set_status_right_inner () {
  _set_status_element "right-inner" "$1"
}

get_status_right_inner () {
  local status

  _get_status_element "right-inner"

  if [[ -z $status ]]
  then
    if [[ $(is_prefix_installed) ]]
    then
      status="#(prefix_highlight)"
    fi
  fi

  echo "$status"
}

set_status_right_middle () {
  _set_status_element "right-middle" "$1"
}

get_status_right_middle () {
  local status

  _get_status_element "right-middle"

  if [[ -z $status ]]
  then
    status=" "
    set_status_right_middle "$status"
  fi

  echo "$status"
}

set_status_right_outer () {
  _set_status_element "right-outer" "$1"
}

get_status_right_outer () {
  local status

  _get_status_element "right-outer"

  if [[ -z $status ]]
  then
    status=" "
    set_status_right_outer "$status"
  fi

  echo "$status"
}

# vim: sts=2 sw=2 et
