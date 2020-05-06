#!/usr/bin/env bash
#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-#
#
# airline.tmux
#
# Initialize tmux-airline
#
# This script does the following:
#
#   - Sets the following tmux user variables for building the status line,
#     if not already defined:
#       - @airline-status-left-outer
#       - @airline-status-left-middle
#       - @airline-status-left-inner
#       - @airline-status-right-inner
#       - @airline-status-right-middle
#       - @airline-status-right-outer
#
#   - Sets the following tmux user variables for theming, if not already
#     defined:
#       - @airline-theme-outer
#       - @airline-theme-middle
#       - @airline-theme-inner
#       - @airline-theme-secondary
#       - @airline-theme-primary
#       - @airline-theme-emphasized
#       - @airline-theme-current
#       - @airline-theme-alert
#       - @airline-theme-special
#       - @airline-theme-stress
#       - @airline-theme-copy
#       - @airline-theme-zoom
#       - @airline-theme-monitor
#
#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-#

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source "$CURRENT_DIR/airline-theme-api.sh"
source "$CURRENT_DIR/scripts/shared.sh"
source "$CURRENT_DIR/scripts/is_installed.sh"

#-----------------------------------------------------------------------------#
#
# Build default status lines
#
#-----------------------------------------------------------------------------#

# default: #(online_status) #S
set_left_outer () {
  local status

  status="$(get_tmux_option @airline-status-left-outer "")"

  # using existing value if defined
  if [[ -n "$status" ]]
  then
    return
  fi

  status="#($CURRENT_DIR/scripts/build_status/line)"

  if [[ $(is_online_installed) ]]
  then
    status="$status #(online_status)"
  fi

  status="$status #S"

  set_tmux_option @airline-status-left-out "$status"
}

# default: $(hostname | cut -d '.' -f 1)
set_left_middle () {
  local status

  status="$(tmux show-option -g @airline-status-left-middle)"

  # using existing value if defined
  if [[ -n "$status" ]]
  then
    return
  fi

  set_tmux_option @airline-status-left-middle "$status"
}

# empty is the default for left inner
set_left_inner () {
  local status

  status="$(tmux show-option -g @airline-status-left-inner)"

  # using existing value if defined
  if [[ -n "$status" ]]
  then
    return
  fi

  set_tmux_option @airline-status-left-inner "$status"
}

# default: copy widget
set_right_inner () {
  local status

  status="$(tmux show-option -g @airline-status-right-inner)"

  # using existing value if defined
  if [[ -n "$status" ]]
  then
    return
  fi

  if is_prefix_installed
  then
    status="#(prefix_highlight) "
  fi

  set_tmux_option @airline-status-right-inner "$status"
}

# default: usage widgets
set_right_middle () {
  local status

  status="$(tmux show-option -g @airline-status-right-middle)"

  # using existing value if defined
  if [[ -n "$status" ]]
  then
    return
  fi

  set_tmux_option @airline-status-right-middle "$status"
}

# default: time and battery
set_right_outer () {
  local status

  status="$(tmux show-option -g @airline-status-right-outer)"

  # using existing value if defined
  if [[ -n "$status" ]]
  then
    return
  fi

  status="%Y-%m-%d %H:%M"

  if [[ $(is_battery_installed) ]]
  then
    status="$status #(battery_color_fg)#(battery_icon)"
  fi

  set_tmux_option @airline-status-right-middle "$status"
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
# Build status line components
#
#-----------------------------------------------------------------------------#

left_outer () {
  local template
  local fg
  local bg
  local next_bg

  fg="$(get_theme_emphasized)"
  bg="$(get_theme_outer)"
  next_bg="$(get_theme_middle)"

  if [[ -z $template ]]
  then
    template="#{online_status} %S"
    tmux set -g @online_icon "#[fg=$(get_theme_primary)]●"
    tmux set -g @offline_icon "#[fg=$(get_theme_stress)]●"
  fi

  echo "#[fg=$fg,bg=$bg] ${template} $(chev_right $bg $next_bg)"
}

left_middle () {
  local template
  local fg="$(get_theme_emphasized)"
  local bg="$(get_theme_middle)"
  local next_bg="$(get_theme_inner)"

  if [[ -z $template ]]
  then
    template="$(hostname | cut -d '.' -f 1)"
  fi

  echo "#[fg=$fg,bg=$bg] ${template} $(chev_right $bg $next_bg) "
}

set_window_formats () {
  local template="$(get_tmux_option @airline_tmpl_window '#I:#W')"
  local bg="$(get_theme_inner)"
  local hi="$(get_theme_current)"

  # default window treatments
  tmux set -gq window-status-separator-string " "
  tmux set -gq window-status-format "$template"

  # window styles
  tmux set -gq window-status-style "fg=$(get_theme_primary) bg=$bg"
  tmux set -gq window-status-last-style "fg=$(get_theme_emphasized) bg=$bg"
  tmux set -gq window-status-activity-style "fg=$(get_theme_alert) bg=$bg"
  tmux set -gq window-status-bell-style "fg=$(get_theme_stress) bg=$bg"

  # special case for current window
  tmux set -gq window-status-current-format "$(chev_right $bg $hi) $template $(chev_left $hi $bg)"
}

right_inner () {
  # explicitly check as we call a function to build the template
  local fg="$(get_theme_inner)"
  local bg="$(get_theme_inner)"
  local template

  template="$(tmux show-option -gqv @airline_tmpl_right_inner)"

  if [[ -z "$template" ]]
  then
    if [[ $(is_prefix_installed) ]]
    then
      tmux set -g @prefix_highlight_output_prefix '['
      tmux set -g @prefix_highlight_output_suffix ']'

      tmux set -g @prefix_highlight_fg "$fg"
      tmux set -g @prefix_highlight_bg "$(get_theme_current)"

      tmux set -g @prefix_highlight_show_copy_mode 'on'
      tmux set -g @prefix_highlight_copy_mode_attr "fg=$fg,bg=$(get_theme_copy)"

      template="$template #{prefix_highlight} "
    fi

  fi

  echo "#[fg=$fg,bg=$bg]${template}"
}

right_middle () {
  # explicitly check as we call a function to build the template
  local fg="$(get_theme_emphasized)"
  local bg="$(get_theme_middle)"
  local prev_bg="$(get_theme_inner)"
  local template="$(get_tmux_option @airline_tmpl_right_middle '')"

  if [[ -z $template ]]
  then

    if [[ $(is_cpu_installed) ]]
    then
      template="$template #{cpu_fg_color}#{cpu_icon}#[fg=$fg,bg=$bg]"

      # cpu low
      tmux set -g @cpu_low_fg_color "$(get_theme_secondary)"
      tmux set -g @cpu_low_bg_color "$bg"

      # cpu medium
      tmux set -g @cpu_medium_fg_color "$(get_theme_alert)"
      tmux set -g @cpu_medium_bg_color "$bg"

      # cpu high
      tmux set -g @cpu_high_fg_color "$(get_theme_stress)"
      tmux set -g @cpu_high_bg_color "$bg"
    fi

  fi

  echo "$(chev_left $prev_bg $bg)#[fg=$fg,bg=$bg] $template"
}

right_outer () {
  local fg="$(get_theme_emphasized)"
  local bg="$(get_theme_outer)"
  local prev_bg="$(get_theme_middle)"
  local template="$(get_tmux_option @airline_tmpl_right_outer '')"

  if [[ -z $template ]]
  then

    template="%Y-%m-%d %H:%M #{battery_color_fg}#[bg=$bg]#{battery_icon}"

    tmux set -g @batt_color_full_charge "#[fg=$(get_theme_emphasized)]"
    tmux set -g @batt_color_high_charge "#[fg=$(get_theme_primary)]"
    tmux set -g @batt_color_medium_charge "#[fg=$(get_theme_alert)]"
    tmux set -g @batt_color_low_charge "#[fg=$(get_theme_stress)]"

    # use theme colors
    tmux set -g @batt_color_charge_primary_tier8 "$(get_theme_primary)"
    tmux set -g @batt_color_charge_primary_tier7 "$(get_theme_primary)"
    tmux set -g @batt_color_charge_primary_tier6 "$(get_theme_emphasized)"
    tmux set -g @batt_color_charge_primary_tier5 "$(get_theme_emphasized)"
    tmux set -g @batt_color_charge_primary_tier4 "$(get_theme_alert)"
    tmux set -g @batt_color_charge_primary_tier3 "$(get_theme_alert)"
    tmux set -g @batt_color_charge_primary_tier2 "$(get_theme_stress)"
    tmux set -g @batt_color_charge_primary_tier1 "$(get_theme_stress)"

    # icons to show when discharging the battery
    tmux set -g @batt_icon_charge_tier8 '🌕'
    tmux set -g @batt_icon_charge_tier7 '🌖'
    tmux set -g @batt_icon_charge_tier6 '🌖'
    tmux set -g @batt_icon_charge_tier5 '🌗'
    tmux set -g @batt_icon_charge_tier4 '🌗'
    tmux set -g @batt_icon_charge_tier3 '🌘'
    tmux set -g @batt_icon_charge_tier2 '🌘'
    tmux set -g @batt_icon_charge_tier1 '🌑'

    # icons to show when charging the battery
    tmux set -g @batt_icon_status_charged '🔋'
    tmux set -g @batt_icon_status_charging '⚡'
    tmux set -g @batt_color_status_primary_charged "$(get_theme_primary)"
    tmux set -g @batt_color_status_primary_charging "$(get_theme_current)"
    tmux set -g @batt_color_status_primary_unknown "$(get_theme_stress)"

  fi

  echo "$(chev_left $prev_bg $bg)#[fg=$fg,bg=$bg] ${template}"
}

#-----------------------------------------------------------------------------#
#
# Set status elements
#
#-----------------------------------------------------------------------------#

main () {
  airline_load_theme solarized

  # TODO: is this needed?
  # TODO: what is mode-style?
  #tmux set -gq mode-style "fg=$(get_theme_special) bg=$(get_theme_alert)"
  # tmux set -gq message-command-style

  # Configure panes, use highlight color for current panes
  tmux set -gq pane-border-style "fg=$(get_theme_primary)"
  tmux set -gq pane-current-border-style "fg=$(get_theme_current)"
  tmux set -gq display-panes-color "$(get_theme_primary)"
  tmux set -gq display-panes-current-color "$(get_theme_current)"

  # Build the status bar
  tmux set -gq status-style "fg=$(get_theme_secondary) bg=$(get_theme_inner)"

  # Configure window status
  set_window_formats

  tmux set -gq status-left-style "fg=$(get_theme_primary) bg=$(get_theme_outer)"
  tmux set -gq status-left "$(left_outer) $(left_middle)"

  tmux set -gq status-right-style "fg=$(get_theme_primary) bg=$(get_theme_outer)"
  tmux set -gq status-right "$(right_inner) $(right_middle) $(right_outer)"

  tmux set -gq clock-mode-color "$(get_theme_special)"

  set_left_outer
  set_left_middle
  set_left_inner

  set_right_inner
  set_right_middle
  set_right_outer

}

main

# vim: sts=2 sw=2 et
