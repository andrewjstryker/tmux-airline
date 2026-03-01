#! /usr/bin/env bash

# Functions that check if other plugins are installed
#
# Checks two locations:
# 1. Sibling directory (standard TPM layout)
# 2. XDG tmux plugin directory (~/.config/tmux/plugins)

_is_installed () {
	local package="$1"

	[[ -d "$CURRENT_DIR/../$package" ]] ||
	[[ -d "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/plugins/$package" ]]
}

is_online_installed () {
	_is_installed "tmux-online-status"
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
