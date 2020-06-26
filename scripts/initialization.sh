#! /usr/bin/env bash
#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-#
#
# Initialize status lines
#
# TODO: Define current directory
#
#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-#

# TODO: be smart about loading api?

source "$CURRENT_DIR/scripts/tpm-integration.sh"

#-----------------------------------------------------------------------------#
#
# Set the default theme
#
#-----------------------------------------------------------------------------#

default_theme () {
  local element="$1"

  if [[ -z "$(_airline_get_theme "${element}")" ]]
  then
    airline set theme "${element}" "${AIRLINE_THEME_ELEMENTS[$element]}"
  else
    debug "Skipping theme element ${element}: ${value}"
  fi
}

#-----------------------------------------------------------------------------#
#
# Set the default status elements
#
#-----------------------------------------------------------------------------#

default_status () {
  local element="$1"
  local value

  debug "Setting defaults for element: $element"

  value="$(_airline_get_status_element "${element}")"

  if [[ -n ${value} ]]
  then
    debug "Skipping status element ${element}: ${value}"
    return
  fi

  case "$element" in
    left-outer )
      airline_set status left-outer "$(default_status_left_outer)"
      ;;
    left-middle )
      airline_set status left-middle "$(default_status_left_middle)"
      ;;
    left-inner )
      airline_set status left-inner "$(default_status_left_inner)"
      ;;
    right-outer )
      airline_set status right-outer "$(default_status_right_outer)"
      ;;
    right-middle )
      airline_set status right-middle "$(default_status_right_middle)"
      ;;
    right-inner )
      airline_set status right-inner "$(default_status_right_inner)"
      ;;
    * )
      # handle error
      ;;
  esac
}

default_status_left_outer () {
  local status=""

  if is_online_installed
  then
    status="$status #(online_status)"
  fi

  echo "$status"
}

default_status_left_middle () {
  hostname | cut -d . -f 1
}

default_status_left_inner () {
  echo "#S"
}

default_status_right_inner () {
  if is_prefix_installed
  then
    status="#(prefix_highlight)"
  fi

  echo "$status"
}

default_status_right_middle () {
  if is_cpu_installed
  then
    status="#{cpu_fg_color}#{cpu_icon}"

    # cpu low
    tmux set -g @cpu_low_fg_color "$(airline_show theme secondary)"
    tmux set -g @cpu_low_bg_color "$(airline_show theme middle)"

    # cpu medium
    tmux set -g @cpu_medium_fg_color "$(airline_show theme alert)"
    tmux set -g @cpu_medium_bg_color "$(airline_show theme middle)"

    # cpu high
    tmux set -g @cpu_high_fg_color "$(airline_show theme stress)"
    tmux set -g @cpu_high_bg_color "$(airline_show theme middle)"
  fi

  echo "$status"
}

default_status_right_outer () {
  if is_battery_installed
  then
    status=" #{battery_color_fg}#{battery_icon}"

    tmux set -g @batt_color_full_charge "#[fg=$(airline_show theme primary)]"
    tmux set -g @batt_color_high_charge "#[fg=$(airline_show theme emphasized)]"
    tmux set -g @batt_color_medium_charge "#[fg=$(airline_show theme alert)]"
    tmux set -g @batt_color_low_charge "#[fg=$(airline_show theme stress)]"

    tmux set -g @batt_color_charge_primary_tier8 "$(airline_show theme primary)"
    tmux set -g @batt_color_charge_primary_tier7 "$(airline_show theme primary)"
    tmux set -g @batt_color_charge_primary_tier6 "$(airline_show theme emphasized)"
    tmux set -g @batt_color_charge_primary_tier5 "$(airline_show theme emphasized)"
    tmux set -g @batt_color_charge_primary_tier4 "$(airline_show theme alert)"
    tmux set -g @batt_color_charge_primary_tier3 "$(airline_show theme alert)"
    tmux set -g @batt_color_charge_primary_tier2 "$(airline_show theme stress)"
    tmux set -g @batt_color_charge_primary_tier1 "$(airline_show theme stress)"

    # icons to show when discharging the battery
    tmux set -g @batt_icon_charge_tier8 '🌑'
    tmux set -g @batt_icon_charge_tier7 '🌘'
    tmux set -g @batt_icon_charge_tier6 '🌘'
    tmux set -g @batt_icon_charge_tier5 '🌗'
    tmux set -g @batt_icon_charge_tier4 '🌗'
    tmux set -g @batt_icon_charge_tier3 '🌖'
    tmux set -g @batt_icon_charge_tier2 '🌖'
    tmux set -g @batt_icon_charge_tier1 '🌕'

    # icons to show when charging the battery
    tmux set -g @batt_icon_status_charged '🔋'
    tmux set -g @batt_icon_status_charging '⚡'
    tmux set -g @batt_color_status_primary_charged "$(airline_show theme primary)"
    tmux set -g @batt_color_status_primary_charging "$(airline_show theme current)"
    tmux set -g @batt_color_status_primary_unknown "$(airline_show theme stress)"
  fi

  echo "%b %d %H:%M $status"
}

#-----------------------------------------------------------------------------#
#
# Improve Tmux defaults
#
# Airline does not manage these variables.
#
#-----------------------------------------------------------------------------#



#-----------------------------------------------------------------------------#
#
# Helper functions
#
#-----------------------------------------------------------------------------#

check_theme_element () {
  local override="$2"
  local element="$1"

  verify_theme_element "$element" &&
    [[ -n "$(airline_show theme "$element")" ||
       -n "$override" ]]
}

check_status_element () {
  local element="$1"
  local override="$2"

  verify_status_element "$element" &&
    [[ -n "$(airline_show status "$element")" ||
       -n "$override" ]]
}

#-----------------------------------------------------------------------------#
#
# CLI/API entry point
#
#-----------------------------------------------------------------------------#

init () {
  local group="${1:-all}"
  local element="${2:-}"

  debug "Call init for ${group}: $*"

  case "$group" in
    theme )
      if [[ -z "${element}" ]]
      then
        for element in "${!AIRLINE_THEME_ELEMENTS[@]}"
        do
          init theme "$element"
        done
      fi
      default_theme "${element}"
      ;;

    status )
      if [[ -z "${element}" ]]
      then 
        for element in "${!AIRLINE_STATUS_ELEMENTS[@]}"
        do
          init "status" "$element"
        done
      fi
      default_status "${element}"
      ;;

    all )
      init "theme"
      init "status"
      ;;

    help | --help | -h )
      echo "Help message"
      ;;

    * )
      init help
      exit 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" = "${0}" ]]
then
  echo "init: $*"
  init "$@"
  exit "$?"
fi

export -f init

# vim: sts=2 sw=2 et
