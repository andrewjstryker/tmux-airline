#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

#-----------------------------------------------------------------------------#
#
# Assign color palette
#
# The script inspects tmux for each of the options below. The options can be
# set in a user's `tmux.conf` file or via a plugin. The plugin needs to be run
# prior to this script.
#
# The default values are suitable for terminals with a black background.
#-----------------------------------------------------------------------------#

color_outer_fg="${$(tmux show-option color_outer_fg):-white}"
color_outer_bg="${$(tmux show-option color_outer_bg):-grey}"

color_middle_fg="${$(tmux show-option color_middle_fg):-white}"
color_middle_bg="${$(tmux show-option color_middle_bg):-cyan}"

color_inner_fg="${$(tmux show-option color_inner_fg):-white}"
color_inner_bg="${$(tmux show-option color_inner_bg):-blue}"

# highlight active elements
color_highlight="${$(tmux show-option color_highlight):-yellow}"

# accent previously active elements
color_accent="${$(tmux show-option color_accent):-green}"

# alert from program triggers
color_alert="${$(tmux show-option color_alert):-cyan}"

# widget colors
color_warn="${$(tmux show-option color_warn):-orange}"
color_stress="${$(tmux show-option color_stress):-red}"

color_prefix="${$(tmux show-option color_highlight):-magenta}"
color_zoom="${$(tmux show-option color_highlight):-violet}"

# tmux modes
color_copy="${$(tmux show-option color_highlight):-blue}"
color_monitor="${$(tmux show-option color_highlight):-orange}"

#-----------------------------------------------------------------------------#
#
# Assign templates
#
# The script inspects tmux for each of the options below
#
#-----------------------------------------------------------------------------#

tmpl_left_outer="${$(tmux show-option tmpl_left_outer):- $(hostname | cut -d . -f 1)}"
tmpl_left_middle="${$(tmux show-option tmpl_left_inner):-%S}"

# TODO: capture active zoom
tmpl_window="${$(tmux show-option tmpl_window_format):-#I:#W}"
tmpl_window_right_default="#{prefix}"
tmpl_window_right="${$(tmux show-option tmpl_window_right):-$tmpl_window_right_default}"

# replace with tmux plugin project alternative
tmpl_right_middle_default="#{online_icon} #{sysstat_cpu} #{sysstat_mem} #{sysstat_loadavg} #{battery_icon}"
tmpl_right_middle="${$(tmux show-option tmpl_right_middle):-$tmpl_right_middle_default}"
tmpl_right_outer="${$(tmux show-option tmpl_right_outer):-%Y-%m-%d %H:%M}"

#-----------------------------------------------------------------------------#
#
# Transition sections
#
#-----------------------------------------------------------------------------#

transition () {
  local left_bg="$1"
  local right_bg="$2"
  local right_fg="$3"
  local chevron="$4"

  echo "#[fg=$right_bg,bg=$left_bg]$chevron[bg=$right_bg]"
}

trans_in () {
  transition "$1 $2 $3 "
}

trans_in () {
  transition "$1 $2 $3 "
}

#-----------------------------------------------------------------------------#
#
# Define color bars
#
#-----------------------------------------------------------------------------#

color_outer="#[fg=$color_outer_fg,bg=$color_outer_bg]"
seperator_out_mid="#[fg=$color_outer_bg,bg=$color_middle_bg]"
seperator_mid_out="#[fg=$color_outer_bg,bg=$color_middle_bg]"

color_middle="#[fg=$color_middle_fg,bg=$color_middle_bg]"
seperator_mid_in="#[fg=$color_middle_bg,bg=$color_inner_bg]"
seperator_in_mid="#[fg=$color_middle_bg,bg=$color_inner_bg]"

#-----------------------------------------------------------------------------#
#
# Set status elements
#
#-----------------------------------------------------------------------------#

set -g status-left "$color_outer $tmpl_left_outer $seperator_out_mid $color_middle $tmpl_left_inner $seperator_mid_out"
set -g status-right "$seperator_in_mid $color_middle $tmpl_right_outer $seperator_mid_out $color_outer $tmpl_right_outer $seperator_mid_out"
