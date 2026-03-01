#!/usr/bin/env bash

configure_online () {
  if ! is_online_installed; then
    return
  fi

  tmux set -g @online_icon "#[fg=${THEME[primary]}]●"
  tmux set -g @offline_icon "#[fg=${THEME[stress]}]●"

  echo "#{online_status}"
}
