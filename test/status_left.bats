#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load
load helper

@test "left_outer includes fg and bg colors" {
  init_theme
  run left_outer
  assert_output --partial "fg=${THEME[emphasized]}"
  assert_output --partial "bg=${THEME[outer-bg]}"
}

@test "left_outer includes chevron to middle section" {
  init_theme
  run left_outer
  # chevron transitions from outer-bg to middle-bg
  assert_output --partial "${THEME[outer-bg]}"
  assert_output --partial "${THEME[middle-bg]}"
}

@test "left_outer uses custom template when set" {
  init_theme
  $TMUX -L "$_bats_socket" set -g @airline_tmpl_left_outer 'CUSTOM'
  run left_outer
  assert_output --partial "CUSTOM"
}

@test "left_outer sets online/offline icons by default" {
  init_theme
  local fake_plugins
  fake_plugins="$(mktemp -d)"
  CURRENT_DIR="$fake_plugins/tmux-airline"
  mkdir -p "$fake_plugins/tmux-online-status" "$CURRENT_DIR"
  export XDG_CONFIG_HOME="$fake_plugins"

  left_outer >/dev/null
  run get_option @online_icon
  assert_output --partial "${THEME[primary]}"

  rm -rf "$fake_plugins"
}

@test "left_middle includes fg and bg colors" {
  init_theme
  run left_middle
  assert_output --partial "fg=${THEME[emphasized]}"
  assert_output --partial "bg=${THEME[middle-bg]}"
}

@test "left_middle includes chevron to inner section" {
  init_theme
  run left_middle
  assert_output --partial "${THEME[middle-bg]}"
  assert_output --partial "${THEME[inner-bg]}"
}

@test "left_middle uses custom template when set" {
  init_theme
  $TMUX -L "$_bats_socket" set -g @airline_tmpl_left_middle 'MY_HOST'
  run left_middle
  assert_output --partial "MY_HOST"
}
