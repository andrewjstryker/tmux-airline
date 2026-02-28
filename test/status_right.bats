#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load
load helper

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
  # Create a fake plugin directory so _is_installed finds it
  local fake_plugins
  fake_plugins="$(mktemp -d)"
  mkdir -p "$fake_plugins/tmux-prefix-highlight"
  CURRENT_DIR="$fake_plugins/tmux-airline"
  mkdir -p "$CURRENT_DIR"

  run right_inner
  assert_output --partial "prefix_highlight"

  rm -rf "$fake_plugins"
}

@test "right_inner without prefix-highlight plugin" {
  init_theme
  # Point CURRENT_DIR to an empty temp dir (no sibling plugins)
  local fake_plugins
  fake_plugins="$(mktemp -d)"
  CURRENT_DIR="$fake_plugins/tmux-airline"
  mkdir -p "$CURRENT_DIR"

  run right_inner
  refute_output --partial "prefix_highlight"

  rm -rf "$fake_plugins"
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
  local fake_plugins
  fake_plugins="$(mktemp -d)"
  mkdir -p "$fake_plugins/tmux-cpu"
  CURRENT_DIR="$fake_plugins/tmux-airline"
  mkdir -p "$CURRENT_DIR"

  run right_middle
  assert_output --partial "cpu_icon"

  rm -rf "$fake_plugins"
}

@test "right_middle without cpu plugin" {
  init_theme
  local fake_plugins
  fake_plugins="$(mktemp -d)"
  CURRENT_DIR="$fake_plugins/tmux-airline"
  mkdir -p "$CURRENT_DIR"

  run right_middle
  refute_output --partial "cpu_icon"

  rm -rf "$fake_plugins"
}

# --- right_outer ---

@test "right_outer includes date/time template by default" {
  init_theme
  # Point to empty dir so no battery plugin
  local fake_plugins
  fake_plugins="$(mktemp -d)"
  CURRENT_DIR="$fake_plugins/tmux-airline"
  mkdir -p "$CURRENT_DIR"

  run right_outer
  assert_output --partial "%Y-%m-%d %H:%M"

  rm -rf "$fake_plugins"
}

@test "right_outer uses custom template when set" {
  init_theme
  $TMUX -L "$_bats_socket" set -g @airline_tmpl_right_outer 'CUSTOM_OUTER'
  run right_outer
  assert_output --partial "CUSTOM_OUTER"
}

@test "right_outer with battery plugin installed" {
  init_theme
  local fake_plugins
  fake_plugins="$(mktemp -d)"
  mkdir -p "$fake_plugins/tmux-battery"
  CURRENT_DIR="$fake_plugins/tmux-airline"
  mkdir -p "$CURRENT_DIR"

  run right_outer
  assert_output --partial "battery_icon"

  rm -rf "$fake_plugins"
}

@test "right_outer without battery plugin" {
  init_theme
  local fake_plugins
  fake_plugins="$(mktemp -d)"
  CURRENT_DIR="$fake_plugins/tmux-airline"
  mkdir -p "$CURRENT_DIR"

  run right_outer
  refute_output --partial "battery_icon"

  rm -rf "$fake_plugins"
}
