#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load
load helper

@test "set_window_formats sets window-status-format" {
  init_theme
  set_window_formats
  run get_option window-status-format
  assert_output --partial "#I:#W"
}

@test "set_window_formats sets window-status-style" {
  init_theme
  set_window_formats
  run get_option window-status-style
  assert_output "fg=${THEME[primary]} bg=${THEME[inner-bg]}"
}

@test "set_window_formats sets window-status-last-style" {
  init_theme
  set_window_formats
  run get_option window-status-last-style
  assert_output "fg=${THEME[emphasized]} bg=${THEME[inner-bg]}"
}

@test "set_window_formats sets window-status-activity-style" {
  init_theme
  set_window_formats
  run get_option window-status-activity-style
  assert_output "fg=${THEME[alert]} bg=${THEME[inner-bg]}"
}

@test "set_window_formats sets window-status-bell-style" {
  init_theme
  set_window_formats
  run get_option window-status-bell-style
  assert_output "fg=${THEME[stress]} bg=${THEME[inner-bg]}"
}

@test "set_window_formats sets window-status-current-format with chevrons" {
  init_theme
  set_window_formats
  run get_option window-status-current-format
  # Should contain the active highlight color and the window template
  assert_output --partial "${THEME[active]}"
  assert_output --partial "#I:#W"
}

@test "set_window_formats uses custom template when set" {
  init_theme
  $TMUX -L "$_bats_socket" set -g @airline_tmpl_window '#W'
  set_window_formats
  run get_option window-status-format
  assert_output --partial "#W"
}

# --- per-window signal (@airline-window-signal) ---

@test "window-status-format embeds the signal expression" {
  init_theme
  set_window_formats
  run get_option window-status-format
  assert_output --partial "@airline-window-signal"
  assert_output --partial "${THEME[alert]}"   # token->color baked into the expr
}

@test "window-status-current-format embeds the signal on the highlight" {
  init_theme
  set_window_formats
  run get_option window-status-current-format
  assert_output --partial "@airline-window-signal"
  assert_output --partial "${THEME[active]}"   # fallback (normal) highlight
  assert_output --partial "${THEME[alert]}"    # a signal token color
}

# default style: color (recolor the entry)

@test "color style (default): a token sets the inactive foreground to that color" {
  init_theme
  set_window_formats
  $TMUX -L "$_bats_socket" set -w @airline-window-signal alert
  run tmux display-message -p "$(get_option window-status-format)"
  assert_output --partial "fg=${THEME[alert]}"
  refute_output --partial "●"                  # color style: no glyph
}

@test "color style: unset signal leaves the base style alone" {
  init_theme
  set_window_formats
  run tmux display-message -p "$(get_option window-status-format)"
  refute_output --partial "fg=${THEME[alert]}"
}

@test "color style: the ok (success) token resolves to green" {
  init_theme
  set_window_formats
  tmux set -w @airline-window-signal ok
  run tmux display-message -p "$(get_option window-status-format)"
  assert_output --partial "fg=${THEME[ok]}"
}

@test "color style: an unknown token falls back to primary" {
  init_theme
  set_window_formats
  $TMUX -L "$_bats_socket" set -w @airline-window-signal bogus
  run tmux display-message -p "$(get_option window-status-format)"
  assert_output --partial "fg=${THEME[primary]}"
}

@test "color style: a token sets the active background to that color" {
  init_theme
  set_window_formats
  $TMUX -L "$_bats_socket" set -w @airline-window-signal alert
  run tmux display-message -p "$(get_option window-status-current-format)"
  assert_output --partial "bg=${THEME[alert]}"
}

@test "color style: unset signal uses the normal active highlight background" {
  init_theme
  set_window_formats
  run tmux display-message -p "$(get_option window-status-current-format)"
  assert_output --partial "bg=${THEME[active]}"
  refute_output --partial "bg=${THEME[alert]}"
}

# badge style: a glyph after the name, no recolor

@test "badge style: a token renders the glyph in that color, no recolor" {
  init_theme
  set_window_formats
  $TMUX -L "$_bats_socket" set -w @airline-window-signal alert
  $TMUX -L "$_bats_socket" set -w @airline-window-style badge
  run tmux display-message -p "$(get_option window-status-format)"
  assert_output --partial "fg=${THEME[alert]}"
  assert_output --partial "●"
}

@test "badge style: unset signal renders no glyph" {
  init_theme
  set_window_formats
  $TMUX -L "$_bats_socket" set -w @airline-window-style badge
  run tmux display-message -p "$(get_option window-status-format)"
  refute_output --partial "●"
}

@test "badge style: the active window keeps the normal highlight, plus a glyph" {
  init_theme
  set_window_formats
  $TMUX -L "$_bats_socket" set -w @airline-window-signal monitor
  $TMUX -L "$_bats_socket" set -w @airline-window-style badge
  run tmux display-message -p "$(get_option window-status-current-format)"
  assert_output --partial "bg=${THEME[active]}"          # not recolored
  refute_output --partial "bg=${THEME[monitor]}"
  assert_output --partial "●"
}

@test "badge style: the glyph is configurable via @airline-window-signal-glyph" {
  init_theme
  $TMUX -L "$_bats_socket" set -g @airline-window-signal-glyph "◆"
  set_window_formats
  $TMUX -L "$_bats_socket" set -w @airline-window-signal ok
  $TMUX -L "$_bats_socket" set -w @airline-window-style badge
  run tmux display-message -p "$(get_option window-status-format)"
  assert_output --partial "◆"
}

# both style: recolor AND glyph

@test "both style: inactive window recolors AND shows a glyph" {
  init_theme
  set_window_formats
  $TMUX -L "$_bats_socket" set -w @airline-window-signal alert
  $TMUX -L "$_bats_socket" set -w @airline-window-style both
  run tmux display-message -p "$(get_option window-status-format)"
  assert_output --partial "fg=${THEME[alert]}"
  assert_output --partial "●"
}

@test "both style: active window recolors the background AND shows a glyph" {
  init_theme
  set_window_formats
  $TMUX -L "$_bats_socket" set -w @airline-window-signal alert
  $TMUX -L "$_bats_socket" set -w @airline-window-style both
  run tmux display-message -p "$(get_option window-status-current-format)"
  assert_output --partial "bg=${THEME[alert]}"
  assert_output --partial "●"
}

# --- consume-on-view: clear a transient signal on unfocus ---

@test "register_window_signal_clear adds a pane-focus-out hook keyed on the transient flag" {
  init_theme
  register_window_signal_clear
  run tmux show-hooks -g pane-focus-out
  assert_output --partial "@airline-window-signal-transient"
  assert_output --partial "@airline-window-signal"
}

@test "register_window_signal_clear is idempotent (re-running does not stack hooks)" {
  init_theme
  register_window_signal_clear
  register_window_signal_clear
  register_window_signal_clear
  run tmux show-hooks -g pane-focus-out
  # One entry regardless of how many times main() re-runs (config reload / F12
  # suspend-resume), not N accumulated duplicates.
  assert_equal "$(echo "$output" | grep -c "@airline-window-signal-transient")" "1"
}

@test "focus-out logic clears a window signal marked transient" {
  init_theme
  tmux set -w @airline-window-signal special
  tmux set -w @airline-window-signal-transient 1
  # Run the same conditional the hook runs:
  tmux if-shell -F "#{@airline-window-signal-transient}" \
    "set -wu @airline-window-signal ; set -wu @airline-window-signal-transient"
  run tmux show -wqv @airline-window-signal
  assert_output ""
  run tmux show -wqv @airline-window-signal-transient
  assert_output ""
}

@test "focus-out logic leaves a non-transient signal alone" {
  init_theme
  tmux set -w @airline-window-signal monitor          # working: no transient flag
  tmux if-shell -F "#{@airline-window-signal-transient}" \
    "set -wu @airline-window-signal ; set -wu @airline-window-signal-transient"
  run tmux show -wqv @airline-window-signal
  assert_output "monitor"
}
