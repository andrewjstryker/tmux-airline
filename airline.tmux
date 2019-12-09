#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source "$CURRENT_DIR/scripts/shared.sh"
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

installed () {
	local plugin=$1

	if [[ $(grep $(ls $CURRENT_DIR/..))

create_widget_template () {
	local template=""

	if [[ cpu_installed ]]
	then
		template="$template #{cpu_fg_color}#{cpu_icon}#[bg=${theme[middle_bg]}"
		template="$template #{gpu_fg_color}#{gpu_icon}#[bg=${theme[middle_bg]}"
	fi

	if [[ online_installed ]]
	then
		template=" #{online_status}"
	fi

	if [[ battery_install

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

main () {
	tmux set -gq status-style fg=${theme[secondary_fg]} bg=${theme[inner_bg]}
	tmux set -gq clock-mode-style  fg=${theme[special]} bg=${theme[inner_bg]}
	# tmux set -g mode-style  fg=${theme[special]} bg=${theme[inner_bg]}
	# tmux set -g window-status-activity-style  fg=${theme[special]} bg=${theme[inner_bg]}
	# tmux set -g window-status-bell-style  fg=${theme[special]} bg=${theme[inner_bg]}
	# tmux set -g window-status-format-string  fg=${theme[special]} bg=${theme[inner_bg]}
	# tmux set -g mode-style

	tmux set -gq status-left-style fg=${theme[primary_fg]} bg=${theme[outer_bg]}
	tmux set -gq status-left "$(left_outer) $(left_middle) $(left_inner)"

	tmux set -gq status-right-style fg=${theme[primary_fg]} bg=${theme[outer_bg]}
	tmux set -gq status-right "$(right_outer) $(right_middle) $(right_inner)"

	tmux set -gq window-style fg=${theme[secondary_fg]} bg=${theme[middle_bg]}
	tmux set -gq window-last-style fg=${theme[primary_fg]} bg=${theme[middle_bg]}
	tmux set -gq window-current-style fg=${theme[primary_fg]} bg=${theme[highlight]}
	tmux set -gq window-active-style fg=${theme[primary_fg]} bg=${theme[altert]}

	tmux set -gq pane-border-style fg=${theme[primary_fg]}
	tmux set -gq pane-active-border-style fg=${theme[highlight]}
}

main
