#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source "$CURRENT_DIR/themes/solarized"

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
	chevron "$left_bg $right_bg "
}

chev_left () {
	local left_bg="$1"
	local right_bg="$2"
	chevron "$left_bg $right_bg "
}

#-----------------------------------------------------------------------------#
#
# Build status line components
#
#-----------------------------------------------------------------------------#

left_outer () {
	local template="$(get_tmux_option airline_tmpl_left_out %H)"
	local fg="${theme[outer_fg]}"
	local bg="${theme[outer_bg]}"
	local next_bg="${theme[middle_bg]}"

	echo "#[fg=$fg,bg=$bg]$template$(chev_right $bg $next_bg)"
}

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
