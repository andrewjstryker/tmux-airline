#-----------------------------------------------------------------------------#
#
# Initialize status lines
#
#-----------------------------------------------------------------------------#

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source "$CURRENT_DIR/api.sh"
source "$CURRENT_DIR/tpm-integration.sh"

#-----------------------------------------------------------------------------#
#
# Set the default theme
#
#-----------------------------------------------------------------------------#

default_theme () {
  local element="$1"

  case "$element" in
    primary )
      airline set theme primary black
      ;;
    secondary )
      airline set theme primary grey
      ;;
    emphasized )
      airline set theme emphasized grey
      ;;
    outer )
      airline set theme outer grey
      ;;
    middle )
      airline set theme middle grey
      ;;
    inner )
      airline set theme inner grey
      ;;
    current )
      airline set theme current yellow
      ;;
    alert )
      airline set theme alert red
      ;;
    stress )
      airline set theme stress orange
      ;;
    copy )
      airline set theme copy cyan
      ;;
    zoom )
      airline set theme zoom green
      ;;
    monitor )
      airline set theme monitor blue
      ;;
    special )
      airline set theme special green
      ;;
    * )
      # handle error
      ;;
  esac
}

#-----------------------------------------------------------------------------#
#
# Set the default status elements
#
#-----------------------------------------------------------------------------#

default_status () {
  local element="$1"

  case "$element" in
    left-outer )
      airline set status left-outer "$(default_status_left_outer)"
      ;;
    left-middle )
      airline set status left-middle "$(default_status_left_middle)"
      ;;
    left-inner )
      airline set status left-inner "$(default_status_left_inner)"
      ;;
    right-outer )
      airline set status right-outer "$(default_status_right_outer)"
      ;;
    right-middle )
      airline set status right-middle "$(default_status_right_middle)"
      ;;
    right-inner )
      airline set status right-inner "$(default_status_right_inner)"
      ;;
    * )
      # handle error
      ;;
  esac
}

default_status_left_outer () {
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
    tmux set -g @cpu_low_fg_color "$(get_theme_secondary)"
    tmux set -g @cpu_low_bg_color "$(get_theme_middle)"

    # cpu medium
    tmux set -g @cpu_medium_fg_color "$(get_theme_alert)"
    tmux set -g @cpu_medium_bg_color "$(get_theme_middle)"

    # cpu high
    tmux set -g @cpu_high_fg_color "$(get_theme_stress)"
    tmux set -g @cpu_high_bg_color "$(get_theme_middle)"
  fi

  echo "$status"
}

default_status_right_outer () {
  if is_battery_installed
  then
    status=" #{battery_color_fg}#{battery_icon}"

    tmux set -g @batt_color_full_charge "#[fg=$(get_theme_primary)]"
    tmux set -g @batt_color_high_charge "#[fg=$(get_theme_emphasized)]"
    tmux set -g @batt_color_medium_charge "#[fg=$(get_theme_alert)]"
    tmux set -g @batt_color_low_charge "#[fg=$(get_theme_stress)]"

    tmux set -g @batt_color_charge_primary_tier8 "$(get_theme_primary)"
    tmux set -g @batt_color_charge_primary_tier7 "$(get_theme_primary)"
    tmux set -g @batt_color_charge_primary_tier6 "$(get_theme_emphasized)"
    tmux set -g @batt_color_charge_primary_tier5 "$(get_theme_emphasized)"
    tmux set -g @batt_color_charge_primary_tier4 "$(get_theme_alert)"
    tmux set -g @batt_color_charge_primary_tier3 "$(get_theme_alert)"
    tmux set -g @batt_color_charge_primary_tier2 "$(get_theme_stress)"
    tmux set -g @batt_color_charge_primary_tier1 "$(get_theme_stress)"

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
    tmux set -g @batt_color_status_primary_charged "$(get_theme_primary)"
    tmux set -g @batt_color_status_primary_charging "$(get_theme_current)"
    tmux set -g @batt_color_status_primary_unknown "$(get_theme_stress)"
  fi

  echo "%b %d %H:%M $status"
}

#-----------------------------------------------------------------------------#
#
# Helper functions
#
#-----------------------------------------------------------------------------#

check_status_element () {
  local element="$1"
  local override="$2"

  verify_status_element "$element" &&
    [[ -n "$(airline show status "$element")" ||
       -n "$override" ]]
}

#-----------------------------------------------------------------------------#
#
# CLI/API entry point
#
#-----------------------------------------------------------------------------#

init () {
  local override
  local subcmd
  local element

  # process global options
  if [[ $1 == "--force" || $1 == "-f" ]]
  then
    echo "Forcing override"
    override="--force"
    shift
  fi

  subcmd="${1:-all}"
  shift

  case "$subcmd" in
    theme )
      element="$1"
      check theme "$element" "$override" &&
        default_theme "$override" "$element"
      ;;
    status )
      element="$1"
      check status "$element" "$override" &&
        default_status "$override" "$element"
      ;;
    all )
      for element in "${!AIRLINE_THEME_ELEMENTS[@]}"
      do
        init "$override" theme "$element" &
      done
      for element in "${!AIRLINE_STATUS_ELEMENTS[@]}"
      do
        init "$override" status "$element" &
      done
      wait
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

init "$@"

# vim: sts=2 sw=2 et
