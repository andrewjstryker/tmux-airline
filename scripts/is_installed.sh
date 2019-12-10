#! /usr/bin/env bash

# Functions that check if other plugins are installed

_is_installed () {
	local package="$1"

	[[ ! $( ls "$CURRENT_DIR/.." | grep -qs "$package" ) ]]
}

is_online_installed () {
	_is_installed "tmux-online"
}

is_cpu_installed () {
	_is_installed "tmux-cpu"
}

is_battery_installed () {
	_is_installed "tmux-battery"
}

is_prefix_installed () {
	_is_installed "tmux-prefix-highlight"
}
