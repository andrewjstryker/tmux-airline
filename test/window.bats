#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load
load helper

@test "set_window_formats sets window-status-format" {
  init_theme
  set_window_formats
  run get_option window-status-format
  assert_output "#I:#W"
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
  assert_output "#W"
}
