#!/usr/bin/env bash
#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-#
# theme-api.sh
#
# Provide an API to setting and getting themes elements.
#
# This API hides the implementation details of managing themes. The biggest
# benefit is that the API records when theme elements changed. This allows API
# users to update only when needed.
#
#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-#

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source "$CURRENT_DIR/shared.sh"

THEME_PREFIX="@_airline-theme"
REFRESH_FLAG="${THEME_PREFIX}-refresh"

#-----------------------------------------------------------------------------#
#
# Internal set functions
#
#-----------------------------------------------------------------------------#

_set_theme_element () {
  local element="$1"
  local value="$2"

  set_tmux_option "${REFRESH_FLAG}" 1
  set_tmux_option "${THEME_PREFIX}-$element" "$value"
}

_get_theme_element () {
  local element="$1"
  local default="$2"

  get_tmux_option "${THEME_PREFIX}-$element" "$default"
}

#-----------------------------------------------------------------------------#
#
# User functions
#
#-----------------------------------------------------------------------------#

theme_refresh_needed () {
  # note numerical testing
  if (( "$(get_tmux_option "${REFRESH_FLAG}" "1" )" ))
  then
    return 1
  fi

  return 0
}

theme_refresh_clear () {
  set_tmux_option "${REFRESH_FLAG}" 0
}

theme_load () {
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

# "special" state (e.g., prefix key active)
set_special () {
  _set_theme_element special "$1"
}

get_special () {
  _get_theme_element special magenta
}


# vim: sts=2 sw=2 et
