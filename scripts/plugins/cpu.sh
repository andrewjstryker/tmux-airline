#!/usr/bin/env bash

configure_cpu () {
  if ! is_cpu_installed; then
    return
  fi

  local fg="${THEME[emphasized]}"
  local bg="${THEME[middle-bg]}"

  # cpu low
  tmux set -g @cpu_low_fg_color "${THEME[secondary]}"
  tmux set -g @cpu_low_bg_color "$bg"

  # cpu medium
  tmux set -g @cpu_medium_fg_color "${THEME[alert]}"
  tmux set -g @cpu_medium_bg_color "$bg"

  # cpu high
  tmux set -g @cpu_high_fg_color "${THEME[stress]}"
  tmux set -g @cpu_high_bg_color "$bg"

  echo "#{cpu_fg_color}#{cpu_icon}#[fg=$fg,bg=$bg]"
}
