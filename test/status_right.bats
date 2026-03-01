#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load
load helper

# Helper: create a fake plugin directory and isolate from real plugins
_fake_plugin_dir() {
  _sr_fake="$(mktemp -d)"
  CURRENT_DIR="$_sr_fake/tmux-airline"
  mkdir -p "$CURRENT_DIR"
  export XDG_CONFIG_HOME="$_sr_fake"
  for plugin in "$@"; do
    mkdir -p "$_sr_fake/$plugin"
  done
}

# --- right_inner ---

@test "right_inner outputs inner-bg colors" {
  init_theme
  run right_inner
  assert_output --partial "${THEME[inner-bg]}"
}

@test "right_inner uses custom template when set" {
  init_theme
  $TMUX -L "$_bats_socket" set -g @airline_tmpl_right_inner 'CUSTOM_INNER'
  run right_inner
  assert_output --partial "CUSTOM_INNER"
}

@test "right_inner with prefix-highlight plugin installed" {
  init_theme
  _fake_plugin_dir tmux-prefix-highlight

  run right_inner
  assert_output --partial "prefix_highlight"

  rm -rf "$_sr_fake"
}

@test "right_inner without prefix-highlight plugin" {
  init_theme
  _fake_plugin_dir

  run right_inner
  refute_output --partial "prefix_highlight"

  rm -rf "$_sr_fake"
}

# --- right_middle ---

@test "right_middle includes chevron from inner to middle" {
  init_theme
  run right_middle
  assert_output --partial "${THEME[inner-bg]}"
  assert_output --partial "${THEME[middle-bg]}"
}

@test "right_middle uses custom template when set" {
  init_theme
  $TMUX -L "$_bats_socket" set -g @airline_tmpl_right_middle 'CUSTOM_MID'
  run right_middle
  assert_output --partial "CUSTOM_MID"
}

@test "right_middle with cpu plugin installed" {
  init_theme
  _fake_plugin_dir tmux-cpu

  run right_middle
  assert_output --partial "cpu_icon"

  rm -rf "$_sr_fake"
}

@test "right_middle without cpu plugin" {
  init_theme
  _fake_plugin_dir

  run right_middle
  refute_output --partial "cpu_icon"

  rm -rf "$_sr_fake"
}

# --- right_outer ---

@test "right_outer includes date/time template by default" {
  init_theme
  _fake_plugin_dir

  run right_outer
  assert_output --partial "%Y-%m-%d %H:%M"

  rm -rf "$_sr_fake"
}

@test "right_outer uses custom template when set" {
  init_theme
  $TMUX -L "$_bats_socket" set -g @airline_tmpl_right_outer 'CUSTOM_OUTER'
  run right_outer
  assert_output --partial "CUSTOM_OUTER"
}

@test "right_outer with battery plugin installed" {
  init_theme
  _fake_plugin_dir tmux-battery

  run right_outer
  assert_output --partial "battery_icon"

  rm -rf "$_sr_fake"
}

@test "right_outer without battery plugin" {
  init_theme
  _fake_plugin_dir

  run right_outer
  refute_output --partial "battery_icon"

  rm -rf "$_sr_fake"
}
