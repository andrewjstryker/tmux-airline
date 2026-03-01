#!/usr/bin/env bash

configure_prefix_highlight () {
  if ! is_prefix_installed; then
    return
  fi

  local bg="${THEME[inner-bg]}"

  tmux set -g @prefix_highlight_output_prefix '['
  tmux set -g @prefix_highlight_output_suffix ']'

  tmux set -g @prefix_highlight_fg "$bg"
  tmux set -g @prefix_highlight_bg "${THEME[active]}"

  tmux set -g @prefix_highlight_show_copy_mode 'on'
  tmux set -g @prefix_highlight_copy_mode_attr "fg=$bg,bg=${THEME[copy]}"

  tmux set -g @prefix_highlight_show_sync_mode 'on'
  tmux set -g @prefix_highlight_sync_mode_attr "fg=$bg,bg=${THEME[special]}"

  echo "#{prefix_highlight} "
}
