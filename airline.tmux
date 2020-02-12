#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source "$CURRENT_DIR/scripts/shared.sh"
source "$CURRENT_DIR/scripts/is_installed.sh"

#-----------------------------------------------------------------------------#
#
# Load color scheme
#
#-----------------------------------------------------------------------------#

load_color_scheme () {
  # use an associative array to hold the theme
  declare -A THEME
  local color_scheme=$(get_tmux_option airline_color_scheme solarized)

  tmux source-file "$CURRENT_DIR/themes/$color_scheme"

  # status line colors
  THEME[outer-bg]=$(get_tmux_option airline-outer-bg "green")
  THEME[middle-bg]=$(get_tmux_option airline-middle-bg "green")
  THEME[inner-bg]=$(get_tmux_option airline-inner-bg "green")

  # "normal" content colors
  THEME[secondary]=$(get_tmux_option airline-secondary "white")
  THEME[primary]=$(get_tmux_option airline-primary "white")
  THEME[emphasized]=$(get_tmux_option airline-emphasized "white")

  # highlight active elements
  THEME[active]=$(get_tmux_option airline-active "yellow")

  # highlight special conditions
  THEME[special]=$(get_tmux_option airline-special "purple")

  # highlight alert/active conditions
  THEME[alert]=$(get_tmux_option airline-alert "orange")

  # highlight high stress conditions
  THEME[stress]=$(get_tmux_option airline-stress "red")

  # tmux modes
  THEME[zoom]=$(get_tmux_option airline-zoom "cyan")
  THEME[copy]=$(get_tmux_option airline-copy "blue")
  THEME[monitor]=$(get_tmux_option airline-monitor "grey")

  export THEME
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
# Create widget template
#
# Build a template from installed popular widgets, if the user did not define
# a left middle template.
#
#-----------------------------------------------------------------------------#

make_right_middle_template () {
  local template=""

  if [[ $(is_cpu_installed) ]]
  then
    template="$template #{cpu_fg_color}#{cpu_icon}#[bg=${THEME[middle_bg]}"
    tmux set -g @cpu_low_fg_color "${THEME[primary_fg]}" # foreground color when cpu is low
    tmux set -g @cpu_medium_fg_color "${THEME[emphasized_fg]}" # foreground color when cpu is medium
    tmux set -g @cpu_high_fg_color "${THEME[stress]}" # foreground color when cpu is high


  fi

  if [[ $(is_online_installed) ]]
  then
    template="$template #{online_status}"
    tmux set -g @online_icon "#[fg=${THEME[color_level_ok]}]●#[default]"
    tmux set -g @offline_icon "#[fg=${THEME[color_level_stress]}]●#[default]"
    template="$template #{online_status}"
  fi

  if [[ $(is_battery_installed) ]]
  then
    tmux set -g @batt_color_full_charge "#[fg=${THEME[color_level_ok]}]"
    tmux set -g @batt_color_high_charge "#[fg=${THEME[color_level_ok]}]"
    tmux set -g @batt_color_medium_charge "#[fg=${THEME[color_level_warn]}]"
    tmux set -g @batt_color_low_charge "#[fg=${THEME[color_level_stress]}]"
    template="$template #{battery_status}"
  fi

  echo "$template"
}

make_right_inner_template () {
  if [[ $(is_prefix_installed) ]]
  then
    tmux set -g @prefix_highlight_output_prefix '['
    tmux set -g @prefix_highlight_output_suffix ']'
    tmux set -g @prefix_highlight_fg "${THEME[emphasized_fg]}"
    tmux set -g @prefix_highlight_bg "${THEME[special]}"
    tmux set -g @prefix_highlight_show_copy_mode 'on'
    tmux set -g @prefix_highlight_copy_mode_attr "fg=${THEME[emphasized_fg]},bg=${THEME[copy]}"
  fi

  echo " #{prefix_highlight} "
}

#-----------------------------------------------------------------------------#
#
# Build status line components
#
#-----------------------------------------------------------------------------#

left_outer () {
  local template
  local fg="${THEME[emphasized_fg]}"
  local bg="${THEME[outer_bg]}"
  local next_bg="${THEME[middle_bg]}"

  if [[ -z $template ]]
  then
    template="#{online_status}"
    tmux set -g @online_icon "#[fg=${THEME[emphasized_fg]}]●"
    tmux set -g @offline_icon "#[fg=${THEME[stress]}]●"
  fi

  #echo "#[fg=$fg,bg=$bg]${template}$(chev_right $bg $next_bg)"
  echo "#[fg=$fg,bg=$bg] ${template} $(chev_right $bg $next_bg)"
}

left_middle () {
  local template
  local fg="${THEME[emphasized_fg]}"
  local bg="${THEME[middle_bg]}"
  local next_bg="${THEME[inner_bg]}"

  if [[ -z $template ]]
  then
    template="$(hostname | cut -d '.' -f 1)"
  fi

  echo "#[fg=$fg,bg=$bg] ${template} $(chev_right $bg $next_bg) "
}

window_status () {
  local template="$(get_tmux_option @airline_tmpl_window '#I:#W')"

  echo "$template"
}

window_current () {
  local template="$(get_tmux_option @airline_tmpl_window_current '#I:#W')"
  local bg="${THEME[inner_bg]}"
  local hi="${THEME[highlight]}"

  echo "$(chev_right $bg $hi) $template $(chev_left $hi $bg)"
}

right_inner () {
  # explicitly check as we call a function to build the template
  local fg="${THEME[primary_fg]}"
  local bg="${THEME[inner_bg]}"
  local template

  template="$(tmux show-option -gqv @airline_tmpl_right_inner)"
  if [[ -z "$template" ]]
  then
    template="$(make_right_inner_template)"
  fi

  echo "#[fg=$fg,bg=$bg]${template}"
}

right_middle () {
  # explicitly check as we call a function to build the template
  local fg="${THEME[emphasized_fg]}"
  local bg="${THEME[middle_bg]}"
  local prev_bg="${THEME[inner_bg]}"
  local template

  tmux set -g @cpu_low_fg_color "${THEME[secondary_fg]}" # foreground color when cpu is low
  tmux set -g @cpu_medium_fg_color "${THEME[alert]}" # foreground color when cpu is medium
  tmux set -g @cpu_high_fg_color "${THEME[stress]}" # foreground color when cpu is high

  tmux set -g @cpu_low_bg_color "${THEME[middle_bg]}" # background color when cpu is low
  tmux set -g @cpu_medium_bg_color "${THEME[middle_bg]}" # background color when cpu is medium
  tmux set -g @cpu_high_bg_color "${THEME[middle_bg]}" # background color when cpu is high

  tmux set -g @gpu_low_fg_color "${THEME[secondary_fg]}" # foreground color when cpu is low
  tmux set -g @gpu_medium_fg_color "${THEME[alert]}" # foreground color when cpu is medium
  tmux set -g @gpu_high_fg_color "${THEME[stress]}" # foreground color when cpu is high

  tmux set -g @gpu_low_bg_color "${THEME[middle_bg]}" # background color when cpu is low
  tmux set -g @gpu_medium_bg_color "${THEME[middle_bg]}" # background color when cpu is medium
  tmux set -g @gpu_high_bg_color "${THEME[middle_bg]}" # background color when cpu is high

  #template="$(tmux show-option -gqv airline_right_middle_template)"
  template="#[fg=#{cpu_fg_color}]#{cpu_icon} #[fg=#{gpu_fg_color}]#{gpu_icon}"
  if [[ -z "$template" ]]
  then
    template="$(make_right_middle_template)"
  fi

  echo "$(chev_left $prev_bg $bg)#[fg=$fg,bg=$bg] $template"
}

right_middle () {
  # explicitly check as we call a function to build the template
  local fg="${THEME[emphasized_fg]}"
  local bg="${THEME[middle_bg]}"
  local prev_bg="${THEME[inner_bg]}"
  local template

  tmux set -g @cpu_low_fg_color "${THEME[secondary_fg]}" # foreground color when cpu is low
  tmux set -g @cpu_medium_fg_color "${THEME[alert]}" # foreground color when cpu is medium
  tmux set -g @cpu_high_fg_color "${THEME[stress]}" # foreground color when cpu is high

  tmux set -g @cpu_low_bg_color "${THEME[middle_bg]}" # background color when cpu is low
  tmux set -g @cpu_medium_bg_color "${THEME[middle_bg]}" # background color when cpu is medium
  tmux set -g @cpu_high_bg_color "${THEME[middle_bg]}" # background color when cpu is high

  #template="$(tmux show-option -gqv airline_right_middle_template)"
  template="#[fg=#{cpu_fg_color}]#{cpu_icon}"
  if [[ -z "$template" ]]
  then
    template="$(make_right_middle_template)"
  fi

  echo "$(chev_left $prev_bg $bg)#[fg=$fg,bg=$bg] $template"
}

right_outer () {
  local template
  local fg="${THEME[emphasized_fg]}"
  local bg="${THEME[outer_bg]}"
  local prev_bg="${THEME[middle_bg]}"

  template="%Y-%m-%d %H:%M #{battery_color_fg}#[bg=$bg]#{battery_icon}"

  tmux set -g @batt_color_full_charge "#[fg=${THEME[emphasized_fg]}]"
  tmux set -g @batt_color_high_charge "#[fg=${THEME[primary_fg]}]"
  tmux set -g @batt_color_medium_charge "#[fg=${THEME[alert]}]"
  tmux set -g @batt_color_low_charge "#[fg=${THEME[stress]}]"

  # over-riding defaults to match THEME
  tmux set -g @batt_color_charge_primary_tier8 "${THEME[emphasized_fg]}"
  tmux set -g @batt_color_charge_primary_tier7 "${THEME[emphasized_fg]}"
  tmux set -g @batt_color_charge_primary_tier6 "${THEME[emphasized_fg]}"
  tmux set -g @batt_color_charge_primary_tier5 "${THEME[emphasized_fg]}"
  tmux set -g @batt_color_charge_primary_tier4 "${THEME[altert]}"
  tmux set -g @batt_color_charge_primary_tier3 "${THEME[altert]}"
  tmux set -g @batt_color_charge_primary_tier2 "${THEME[stress]}"
  tmux set -g @batt_color_charge_primary_tier1 "${THEME[stress]}"

  tmux set -g @batt_icon_charge_tier8 '🌕'
  tmux set -g @batt_icon_charge_tier7 '🌖'
  tmux set -g @batt_icon_charge_tier6 '🌖'
  tmux set -g @batt_icon_charge_tier5 '🌗'
  tmux set -g @batt_icon_charge_tier4 '🌗'
  tmux set -g @batt_icon_charge_tier3 '🌘'
  tmux set -g @batt_icon_charge_tier2 '🌘'
  tmux set -g @batt_icon_charge_tier1 '🌑'
  tmux set -g @batt_icon_status_charged '🔋'
  tmux set -g @batt_icon_status_charging '⚡'

  tmux set -g @batt_color_status_primary_charged "${THEME[emphasized_fg]}"
  tmux set -g @batt_color_status_primary_charging "${THEME[monitor]}"
  tmux set -g @batt_color_status_primary_discharging "${THEME[alert]}"
  tmux set -g @batt_color_status_primary_attached "${THEME[secondary_fg]}"
  tmux set -g @batt_color_status_primary_unknown "${THEME[stress]}"

  echo "$(chev_left $prev_bg $bg)#[fg=$fg,bg=$bg] ${template}"
}

#-----------------------------------------------------------------------------#
#
# Set status elements
#
#-----------------------------------------------------------------------------#

main () {
  load_color_scheme

  # TODO: is this needed?
  # TODO: what is mode-style?
  #tmux set -gq mode-style "fg=${THEME[special]} bg=${THEME[alert]}"
  # tmux set -gq message-command-style
  #tmux set -gq window-last-style "fg=${THEME[primary_fg]} bg=${THEME[middle_bg]}"
  #tmux set -gq window-current-style "fg=${THEME[primary_fg]} bg=${THEME[highlight]}"
  # tmux set -gq window-style "fg=${THEME[primary_fg]} bg=${THEME[inner_bg]}"
  #tmux set -gq window-active-style "fg=${THEME[window_fg]} bg=${THEME[alert]}"

  # Configure panes, use highlight color for active panes
  tmux set -gq pane-border-style "fg=${THEME[primary_fg]}"
  tmux set -gq pane-active-border-style "fg=${THEME[highlight]}"
  tmux set -gq display-panes-color "${THEME[primary_fg]}"
  tmux set -gq display-panes-active-color "${THEME[highlight]}"

  # Build the status bar
  tmux set -gq status-style "fg=${THEME[secondary_fg]} bg=${THEME[inner_bg]}"

  # Configure window status
  tmux set -gq window-status-separator-string " "
  tmux set -gq window-status-format "$(window_status)"
  tmux set -gq window-status-style "fg=${THEME[primary_fg]} bg=${THEME[inner_bg]}"
  tmux set -gq window-status-last-style "fg=${THEME[emphasized_fg]} bg=${THEME[inner_bg]}"
  tmux set -gq window-status-current-format "$(window_current)"
  tmux set -gq window-status-activity-style "fg=${THEME[alert]} bg=${THEME[inner_bg]}"
  tmux set -gq window-status-bell-style "fg=${THEME[stress]} bg=${THEME[inner_bg]}"

  tmux set -gq status-left-style "fg=${THEME[primary_fg]} bg=${THEME[outer_bg]}"
  tmux set -gq status-left "$(left_outer) $(left_middle)"

  tmux set -gq status-right-style "fg=${THEME[primary_fg]} bg=${THEME[outer_bg]}"
  tmux set -gq status-right "$(right_inner) $(right_middle) $(right_outer)"

  tmux set -gq clock-mode-color "${THEME[special]}"

}

main
