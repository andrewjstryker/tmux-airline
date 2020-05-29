#-----------------------------------------------------------------------------#
#
# Initialize status lines
#
#-----------------------------------------------------------------------------#

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source "$CURRENT_DIR/api.sh"
source "$CURRENT_DIR/is-installed.sh"

#-----------------------------------------------------------------------------#

init_left_outer () {
  if [[ is_online_installed ]]
  then
    status="$status #(online_status)"
  fi

  echo "$status"
}

init_left_middle () {
  echo "$(hostname | cut -d . -f 1)"
}

init_left_inner () {
  echo "#S"
}

init_right_inner () {
  if [[ is_prefix_installed ]]
  then
    status="#(prefix_highlight)"
  fi

  echo "$status"
}

init_right_middle () {
  if [[ is_cpu_installed ]]
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

init_right_outer () {
  if [[ is_battery_installed ]]
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

init () {
  airline_load_theme solarized

  set_status_left_outer $(init_status_left_outer)
  set_status_left_middle $(init_status_left_middle)
  set_status_left_inner $(init_status_left_inner)

  set_status_right_outer $(init_status_right_outer)
  set_status_right_middle $(init_status_right_middle)
  set_status_right_inner $(init_status_right_inner)

  # TODO: is this needed?
  # TODO: what is mode-style?
  #tmux set -gq mode-style "fg=$(get_theme_special) bg=$(get_theme_alert)"
  # tmux set -gq message-command-style

  # Configure panes, use highlight color for current panes
  tmux set -gq pane-border-style "fg=$(get_theme_primary)"
  tmux set -gq pane-current-border-style "fg=$(get_theme_current)"
  tmux set -gq display-panes-color "$(get_theme_primary)"
  tmux set -gq display-panes-current-color "$(get_theme_current)"

  # Configure window status
  
  tmux set -gq status-left "$(left_outer) $(left_middle) $(left_inner)"
  set_window_formats
  tmux set -gq status-right "$(right_inner) $(right_middle) $(right_outer)"

  tmux set -gq clock-mode-color "$(get_theme_special)"


}
 
init
