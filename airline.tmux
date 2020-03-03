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
#       - @airline-theme-outer-bg
#       - @airline-theme-middle-bg
#       - @airline-theme-inner-bg
#       - @airline-theme-secondary
#       - @airline-theme-primary
#       - @airline-theme-emphasized
#       - @airline-theme-active
#       - @airline-theme-alert
#       - @airline-theme-special
#       - @airline-theme-stress
#       - @airline-theme-copy
#       - @airline-theme-zoom
#       - @airline-theme-monitor
#
#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-#

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source "$CURRENT_DIR/scripts/shared.sh"
source "$CURRENT_DIR/scripts/is_installed.sh"

# use an associative array to hold the theme
declare -A THEME

tmux source-file "$CURRENT_DIR/themes/solarized"

# status line "normal" background colors
THEME[outer-bg]=$(get_tmux_option @airline-outer-bg "green")
THEME[middle-bg]=$(get_tmux_option @airline-middle-bg "green")
THEME[inner-bg]=$(get_tmux_option @airline-inner-bg "green")

# "normal" content colors
THEME[secondary]=$(get_tmux_option @airline-secondary "white")
THEME[primary]=$(get_tmux_option @airline-primary "white")
THEME[emphasized]=$(get_tmux_option @airline-emphasized "white")

# highlight active elements
THEME[active]=$(get_tmux_option @airline-active "yellow")

# highlight special conditions
THEME[special]=$(get_tmux_option @airline-special "purple")

# highlight alert/active conditions
THEME[alert]=$(get_tmux_option @airline-alert "orange")

# highlight high stress conditions
THEME[stress]=$(get_tmux_option @airline-stress "red")

# tmux modes
THEME[zoom]=$(get_tmux_option @airline-zoom "cyan")
THEME[copy]=$(get_tmux_option @airline-copy "blue")
THEME[monitor]=$(get_tmux_option @airline-monitor "grey")

#-----------------------------------------------------------------------------#
#
# Load color scheme
#
#-----------------------------------------------------------------------------#

load_color_theme () {
  # use an associative array to hold the theme
  declare -A THEME
  local color_theme=$(get_tmux_option airline_color_theme solarized)

  tmux source-file "$CURRENT_DIR/themes/$color_theme"

  # status line "normal" background colors
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
# Build default status lines
#
#-----------------------------------------------------------------------------#

# default: #(online_status) %S
set_left_outer () {
  local status

  status="$(tmux show-option -g @airline-status-left-outer)"

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

  status="$status %S"

  tmux set-options -g @airline-status-left-out "$status"
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

  tmux set-options -g @airline-status-left-middle "$status"
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

  tmux set-options -g @airline-status-left-inner ""
}

# default: copy widget
set_right_middle () {
  local status

  status="$(tmux show-option -g @airline-status-left-middle)"

  # using existing value if defined
  if [[ -n "$status" ]]
  then
    return
  fi

  tmux set-options -g @airline-status-left-out ""
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
    template="$template #{cpu_fg_color}#{cpu_icon}#[bg=${THEME[middle-bg]}"

    # foreground color when cpu is low
    tmux set -g @cpu_low_fg_color "${THEME[secondary]}"
    # foreground color when cpu is medium
    tmux set -g @cpu_medium_fg_color "${THEME[alert]}"
    # foreground color when cpu is high
    tmux set -g @cpu_high_fg_color "${THEME[stress]}"
  fi

  if [[ $(is_online_installed) ]]
  then
    template="$template #{online_status}"
    tmux set -g @online_icon "#[fg=${THEME[primary]}]●#[default]"
    tmux set -g @offline_icon "#[fg=${THEME[stress]}]●#[default]"
    template="$template #{online_status}"
  fi

  if [[ $(is_battery_installed) ]]
  then
    template="$template #{battery_status}"
    tmux set -g @batt_color_full_charge "#[fg=${THEME[secondary]}]"
    tmux set -g @batt_color_high_charge "#[fg=${THEME[primary]}]"
    tmux set -g @batt_color_medium_charge "#[fg=${THEME[alert]}]"
    tmux set -g @batt_color_low_charge "#[fg=${THEME[stress]}]"
  fi

  echo "$template"
}


#-----------------------------------------------------------------------------#
#
# Build status line components
#
#-----------------------------------------------------------------------------#

left_outer () {
  local template
  local fg="${THEME[emphasized]}"
  local bg="${THEME[outer-bg]}"
  local next_bg="${THEME[middle-bg]}"

  if [[ -z $template ]]
  then
    template="#{online_status}"
    tmux set -g @online_icon "#[fg=${THEME[primary]}]●"
    tmux set -g @offline_icon "#[fg=${THEME[stress]}]●"
  fi

  echo "#[fg=$fg,bg=$bg] ${template} $(chev_right $bg $next_bg)"
}

left_middle () {
  local template
  local fg="${THEME[emphasized]}"
  local bg="${THEME[middle-bg]}"
  local next_bg="${THEME[inner-bg]}"

  if [[ -z $template ]]
  then
    template="$(hostname | cut -d '.' -f 1)"
  fi

  echo "#[fg=$fg,bg=$bg] ${template} $(chev_right $bg $next_bg) "
}

set_window_formats () {
  local template="$(get_tmux_option @airline_tmpl_window '#I:#W')"
  local bg="${THEME[inner-bg]}"
  local hi="${THEME[active]}"

  # default window treatments
  tmux set -gq window-status-separator-string " "
  tmux set -gq window-status-format "$template"

  # window styles
  tmux set -gq window-status-style "fg=${THEME[primary]} bg=$bg"
  tmux set -gq window-status-last-style "fg=${THEME[emphasized]} bg=$bg"
  tmux set -gq window-status-activity-style "fg=${THEME[alert]} bg=$bg"
  tmux set -gq window-status-bell-style "fg=${THEME[stress]} bg=$bg"

  # special case for current window
  tmux set -gq window-status-current-format "$(chev_right $bg $hi) $template $(chev_left $hi $bg)"
}

right_inner () {
  # explicitly check as we call a function to build the template
  local fg="${THEME[inner-bg]}"
  local bg="${THEME[inner-bg]}"
  local template

  template="$(tmux show-option -gqv @airline_tmpl_right_inner)"

  if [[ -z "$template" ]]
  then
    if [[ $(is_prefix_installed) ]]
    then
      tmux set -g @prefix_highlight_output_prefix '['
      tmux set -g @prefix_highlight_output_suffix ']'

      tmux set -g @prefix_highlight_fg "$fg"
      tmux set -g @prefix_highlight_bg "${THEME[active]}"

      tmux set -g @prefix_highlight_show_copy_mode 'on'
      tmux set -g @prefix_highlight_copy_mode_attr "fg=$fg,bg=${THEME[copy]}"

      template="$template #{prefix_highlight} "
    fi

  fi

  echo "#[fg=$fg,bg=$bg]${template}"
}

right_middle () {
  # explicitly check as we call a function to build the template
  local fg="${THEME[emphasized]}"
  local bg="${THEME[middle-bg]}"
  local prev_bg="${THEME[inner-bg]}"
  local template="$(get_tmux_option @airline_tmpl_right_middle '')"

  if [[ -z $template ]]
  then

    if [[ $(is_cpu_installed) ]]
    then
      template="$template #{cpu_fg_color}#{cpu_icon}#[fg=$fg,bg=$bg]"

      # cpu low
      tmux set -g @cpu_low_fg_color "${THEME[secondary]}"
      tmux set -g @cpu_low_bg_color "$bg"

      # cpu medium
      tmux set -g @cpu_medium_fg_color "${THEME[alert]}"
      tmux set -g @cpu_medium_bg_color "$bg"

      # cpu high
      tmux set -g @cpu_high_fg_color "${THEME[stress]}"
      tmux set -g @cpu_high_bg_color "$bg"
    fi

  fi

  echo "$(chev_left $prev_bg $bg)#[fg=$fg,bg=$bg] $template"
}

right_outer () {
  local fg="${THEME[emphasized]}"
  local bg="${THEME[outer-bg]}"
  local prev_bg="${THEME[middle-bg]}"
  local template="$(get_tmux_option @airline_tmpl_right_outer '')"

  if [[ -z $template ]]
  then

    template="%Y-%m-%d %H:%M #{battery_color_fg}#[bg=$bg]#{battery_icon}"

    tmux set -g @batt_color_full_charge "#[fg=${THEME[emphasized]}]"
    tmux set -g @batt_color_high_charge "#[fg=${THEME[primary]}]"
    tmux set -g @batt_color_medium_charge "#[fg=${THEME[alert]}]"
    tmux set -g @batt_color_low_charge "#[fg=${THEME[stress]}]"

    # use theme colors
    tmux set -g @batt_color_charge_primary_tier8 "${THEME[primary]}"
    tmux set -g @batt_color_charge_primary_tier7 "${THEME[primary]}"
    tmux set -g @batt_color_charge_primary_tier6 "${THEME[emphasized]}"
    tmux set -g @batt_color_charge_primary_tier5 "${THEME[emphasized]}"
    tmux set -g @batt_color_charge_primary_tier4 "${THEME[altert]}"
    tmux set -g @batt_color_charge_primary_tier3 "${THEME[altert]}"
    tmux set -g @batt_color_charge_primary_tier2 "${THEME[stress]}"
    tmux set -g @batt_color_charge_primary_tier1 "${THEME[stress]}"

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
    tmux set -g @batt_color_status_primary_charged "${THEME[primary]}"
    tmux set -g @batt_color_status_primary_charging "${THEME[active]}"
    tmux set -g @batt_color_status_primary_unknown "${THEME[stress]}"

  fi

  echo "$(chev_left $prev_bg $bg)#[fg=$fg,bg=$bg] ${template}"
}

#-----------------------------------------------------------------------------#
#
# Set status elements
#
#-----------------------------------------------------------------------------#

main () {
  #load_color_theme

  # TODO: is this needed?
  # TODO: what is mode-style?
  #tmux set -gq mode-style "fg=${THEME[special]} bg=${THEME[alert]}"
  # tmux set -gq message-command-style

  # Configure panes, use highlight color for active panes
  tmux set -gq pane-border-style "fg=${THEME[primary]}"
  tmux set -gq pane-active-border-style "fg=${THEME[active]}"
  tmux set -gq display-panes-color "${THEME[primary]}"
  tmux set -gq display-panes-active-color "${THEME[active]}"

  # Build the status bar
  tmux set -gq status-style "fg=${THEME[secondary]} bg=${THEME[inner-bg]}"

  # Configure window status
  set_window_formats

  tmux set -gq status-left-style "fg=${THEME[primary]} bg=${THEME[outer-bg]}"
  tmux set -gq status-left "$(left_outer) $(left_middle)"

  tmux set -gq status-right-style "fg=${THEME[primary]} bg=${THEME[outer-bg]}"
  tmux set -gq status-right "$(right_inner) $(right_middle) $(right_outer)"

  tmux set -gq clock-mode-color "${THEME[special]}"

}

main
