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

# --- per-window color override (@airline-window-color) ---

@test "window-status-format embeds the window-color override" {
  init_theme
  set_window_formats
  run get_option window-status-format
  assert_output --partial "@airline-window-color"
  assert_output --partial "${THEME[alert]}"   # token->color baked into the expr
}

@test "window-status-current-format embeds the override on the highlight" {
  init_theme
  set_window_formats
  run get_option window-status-current-format
  assert_output --partial "@airline-window-color"
  assert_output --partial "${THEME[active]}"   # fallback (normal) highlight
  assert_output --partial "${THEME[alert]}"    # an override token color
}

@test "inactive window: a token sets the foreground to that palette color" {
  init_theme
  set_window_formats
  $TMUX -L "$_bats_socket" set -w @airline-window-color alert
  run tmux display-message -p "$(get_option window-status-format)"
  assert_output --partial "fg=${THEME[alert]}"
}

@test "inactive window: unset leaves the base style alone" {
  init_theme
  set_window_formats
  run tmux display-message -p "$(get_option window-status-format)"
  refute_output --partial "fg=${THEME[alert]}"
}

@test "inactive window: the ok (success) token resolves to green" {
  init_theme
  set_window_formats
  tmux set -w @airline-window-color ok
  run tmux display-message -p "$(get_option window-status-format)"
  assert_output --partial "fg=${THEME[ok]}"
}

@test "inactive window: an unknown token falls back to primary" {
  init_theme
  set_window_formats
  $TMUX -L "$_bats_socket" set -w @airline-window-color bogus
  run tmux display-message -p "$(get_option window-status-format)"
  assert_output --partial "fg=${THEME[primary]}"
}

@test "active window: a token sets the background to that palette color" {
  init_theme
  set_window_formats
  $TMUX -L "$_bats_socket" set -w @airline-window-color alert
  run tmux display-message -p "$(get_option window-status-current-format)"
  assert_output --partial "bg=${THEME[alert]}"
}

@test "active window: unset uses the normal active highlight background" {
  init_theme
  set_window_formats
  run tmux display-message -p "$(get_option window-status-current-format)"
  assert_output --partial "bg=${THEME[active]}"
  refute_output --partial "bg=${THEME[alert]}"
}

# --- consume-on-view: clear a transient window color on unfocus ---

@test "register_window_color_clear adds a pane-focus-out hook keyed on the transient flag" {
  init_theme
  register_window_color_clear
  run tmux show-hooks -g pane-focus-out
  assert_output --partial "@airline-window-color-transient"
  assert_output --partial "@airline-window-color"
}

@test "focus-out logic clears a window marked transient" {
  init_theme
  tmux set -w @airline-window-color special
  tmux set -w @airline-window-color-transient 1
  # Run the same conditional the hook runs:
  tmux if-shell -F "#{@airline-window-color-transient}" \
    "set -wu @airline-window-color ; set -wu @airline-window-color-transient"
  run tmux show -wqv @airline-window-color
  assert_output ""
  run tmux show -wqv @airline-window-color-transient
  assert_output ""
}

@test "focus-out logic leaves a non-transient color alone" {
  init_theme
  tmux set -w @airline-window-color monitor          # working: no transient flag
  tmux if-shell -F "#{@airline-window-color-transient}" \
    "set -wu @airline-window-color ; set -wu @airline-window-color-transient"
  run tmux show -wqv @airline-window-color
  assert_output "monitor"
}
