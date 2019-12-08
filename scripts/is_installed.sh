#! /usr/bin/env bash

# Functions that check if other plugins are installed

is_online_installed () {
	[[ ! $( ls $CURRENT_DIR/.. | grep -qs "tmux-online" ) ]]
}

is_cpu_installed () {
	[[ ! $( ls $CURRENT_DIR/.. | grep -qs "tmux-cpu" ) ]]
}

is_battery_installed () {
	[[ ! $( ls $CURRENT_DIR/.. | grep -qs "tmux-battery" ) ]]
}
