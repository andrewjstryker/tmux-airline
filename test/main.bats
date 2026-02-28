#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load
load helper

@test "main sets pane-border-style" {
  init_theme
  main
  run get_option pane-border-style
  assert_output "fg=${THEME[primary]}"
}

@test "main sets pane-active-border-style" {
  init_theme
  main
  run get_option pane-active-border-style
  assert_output "fg=${THEME[active]}"
}

@test "main sets display-panes-color" {
  init_theme
  main
  run get_option display-panes-color
  assert_output "${THEME[primary]}"
}

@test "main sets display-panes-active-color" {
  init_theme
  main
  run get_option display-panes-active-color
  assert_output "${THEME[active]}"
}

@test "main sets status-style" {
  init_theme
  main
  run get_option status-style
  assert_output "fg=${THEME[secondary]} bg=${THEME[inner-bg]}"
}

@test "main sets status-left" {
  init_theme
  main
  run get_option status-left
  assert_success
  # Should contain colors from the outer and middle sections
  assert_output --partial "${THEME[outer-bg]}"
  assert_output --partial "${THEME[middle-bg]}"
}

@test "main sets status-right" {
  init_theme
  main
  run get_option status-right
  assert_success
  assert_output --partial "${THEME[inner-bg]}"
}

@test "main sets clock-mode-color" {
  init_theme
  main
  run get_option clock-mode-color
  assert_output "${THEME[special]}"
}

@test "main sets status-left-style" {
  init_theme
  main
  run get_option status-left-style
  assert_output "fg=${THEME[primary]} bg=${THEME[outer-bg]}"
}

@test "main sets status-right-style" {
  init_theme
  main
  run get_option status-right-style
  assert_output "fg=${THEME[primary]} bg=${THEME[outer-bg]}"
}
