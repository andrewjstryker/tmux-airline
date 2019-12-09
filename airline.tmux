#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source "$CURRENT_DIR/scripts/shared.sh"
source "$CURRENT_DIR/scripts/installed.sh"

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
	chevron "$left_bg" "$right_bg" ""
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

create_widget_template () {
	local template=""

	if [[ is_cpu_installed ]]
	then
		template="$template #{cpu_fg_color}#{cpu_icon}#[bg=${theme[middle_bg]}"
		template="$template #{gpu_fg_color}#{gpu_icon}#[bg=${theme[middle_bg]}"
	fi

	if [[ is_online_installed ]]
	then
		template="$template #{online_status}"
	fi

	if [[ is_battery_install ]]
	then
		template="$template #{battery_status}"
	fi
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

	echo "#[fg=$fg,bg=$bg]${template}$(chev_right $bg $next_bg)"
}

left_middle () {
	local template="$(get_tmux_option airline_tmpl_left_middle %S)"
	local fg="${theme[middle_fg]}"
	local bg="${theme[middle_bg]}"
	local next_bg="${theme[inner_bg]}"

	echo "#[fg=$fg,bg=$bg]${template}$(chev_right $bg $next_bg)"
}

left_inner () {
	local template="$(get_tmux_option airline_tmpl_left_inner ' ')"
	local fg="${theme[primary_fg]}"
	local bg="${theme[inner_bg]}"

	echo "#[fg=$fg,bg=$bg]${template}"
}

right_inner () {
	local template="$(get_tmux_option airline_tmpl_right_inner ' ')"
	local fg="${theme[primary_fg]}"
	local bg="${theme[inner_bg]}"

	echo "#[fg=$fg,bg=$bg]${template}"
}

right_middle () {
	local template="$(get_tmux_option airline_tmpl_right_middle %S)"
	local fg="${theme[middle_fg]}"
	local bg="${theme[middle_bg]}"
	local prev_bg="${theme[inner_bg]}"

	echo "$(chev_left $prev_bg $bg)#[fg=$fg,bg=$bg]${template}"
}

right_outer () {
	local template="$(get_tmux_option airline_tmpl_right_outer %S)"
	local fg="${theme[outer_fg]}"
	local bg="${theme[outer_bg]}"
	local prev_bg="${theme[middle_bg]}"

	echo "$(chev_left $prev_bg $bg)#[fg=$fg,bg=$bg]${template}"
}

#-----------------------------------------------------------------------------#
#
# Set status elements
#
#-----------------------------------------------------------------------------#

set -g status-left "$color_outer $tmpl_left_outer $seperator_out_mid $color_middle $tmpl_left_inner $seperator_mid_out"
set -g status-right "$seperator_in_mid $color_middle $tmpl_right_outer $seperator_mid_out $color_outer $tmpl_right_outer $seperator_mid_out"
