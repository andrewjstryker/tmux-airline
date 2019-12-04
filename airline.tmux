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

	echo "#[fg=$fg,bg=$bg] $template $(chev_right $bg $next_bg)"
}

left_middle () {
	local template="$(get_tmux_option airline_tmpl_left_middle %S)"
	local fg="${theme[middle_fg]}"
	local bg="${theme[middle_bg]}"
	local next_bg="${theme[inner_bg]}"

	echo "#[fg=$fg,bg=$bg] $template $(chev_right $bg $next_bg)"
}

right_inner () {
	local template="$(get_tmux_option airline_tmpl_right_inner ' ')"
	local fg="${theme[primary_fg]}"
	local bg="${theme[inner_bg]}"

	echo "#[fg=$fg,bg=$bg] $template "
}

right_middle () {
	local template="$(get_tmux_option airline_tmpl_right_middle %S)"
	local fg="${theme[middle_fg]}"
	local bg="${theme[middle_bg]}"
	local prev_bg="${theme[inner_bg]}"

	echo "$(chev_left $prev_bg $bg)#[fg=$fg,bg=$bg] $template"
}

right_outer () {
	local template="$(get_tmux_option airline_tmpl_right_outer %S)"
	local fg="${theme[outer_fg]}"
	local bg="${theme[outer_bg]}"
	local prev_bg="${theme[middle_bg]}"

	echo "$(chev_left $prev_bg $bg)#[fg=$fg,bg=$bg] $template"
}

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
