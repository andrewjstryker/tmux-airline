#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load
load helper

# Helper: set CURRENT_DIR so _is_installed finds (or doesn't find) a plugin.
# Sets _fake_plugins to the temp dir root for cleanup.
fake_plugin_dir() {
  _fake_plugins="$(mktemp -d)"
  CURRENT_DIR="$_fake_plugins/tmux-airline"
  mkdir -p "$CURRENT_DIR"
  # Point XDG_CONFIG_HOME at the temp dir so is_installed doesn't find
  # real plugins in ~/.config/tmux/plugins/
  export XDG_CONFIG_HOME="$_fake_plugins"
  for plugin in "$@"; do
    mkdir -p "$_fake_plugins/$plugin"
  done
}

# --- configure_online ---

@test "configure_online returns template when plugin installed" {
  init_theme
  fake_plugin_dir tmux-online-status

  run configure_online
  assert_output "#{online_status}"

  rm -rf "$_fake_plugins"
}

@test "configure_online sets online/offline icons" {
  init_theme
  fake_plugin_dir tmux-online-status

  configure_online >/dev/null

  run get_option @online_icon
  assert_output --partial "${THEME[primary]}"

  run get_option @offline_icon
  assert_output --partial "${THEME[stress]}"

  rm -rf "$_fake_plugins"
}

@test "configure_online returns empty when plugin not installed" {
  init_theme
  fake_plugin_dir

  run configure_online
  assert_output ""

  rm -rf "$_fake_plugins"
}

# --- configure_prefix_highlight ---

@test "configure_prefix_highlight returns template when installed" {
  init_theme
  fake_plugin_dir tmux-prefix-highlight

  run configure_prefix_highlight
  assert_output "#{prefix_highlight} "

  rm -rf "$_fake_plugins"
}

@test "configure_prefix_highlight sets tmux options" {
  init_theme
  fake_plugin_dir tmux-prefix-highlight

  configure_prefix_highlight >/dev/null

  run get_option @prefix_highlight_output_prefix
  assert_output "["

  run get_option @prefix_highlight_show_copy_mode
  assert_output "on"

  run get_option @prefix_highlight_show_sync_mode
  assert_output "on"

  rm -rf "$_fake_plugins"
}

@test "configure_prefix_highlight returns empty when not installed" {
  init_theme
  fake_plugin_dir

  run configure_prefix_highlight
  assert_output ""

  rm -rf "$_fake_plugins"
}

# --- configure_cpu ---

@test "configure_cpu returns template when installed" {
  init_theme
  fake_plugin_dir tmux-cpu

  run configure_cpu
  assert_output --partial "cpu_icon"

  rm -rf "$_fake_plugins"
}

@test "configure_cpu sets color options" {
  init_theme
  fake_plugin_dir tmux-cpu

  configure_cpu >/dev/null

  run get_option @cpu_low_fg_color
  assert_output "${THEME[secondary]}"

  run get_option @cpu_medium_fg_color
  assert_output "${THEME[alert]}"

  run get_option @cpu_high_fg_color
  assert_output "${THEME[stress]}"

  rm -rf "$_fake_plugins"
}

@test "configure_cpu returns empty when not installed" {
  init_theme
  fake_plugin_dir

  run configure_cpu
  assert_output ""

  rm -rf "$_fake_plugins"
}

# --- configure_battery ---

@test "configure_battery returns template when installed" {
  init_theme
  fake_plugin_dir tmux-battery

  run configure_battery
  assert_output --partial "battery_icon"

  rm -rf "$_fake_plugins"
}

@test "configure_battery sets charge color options" {
  init_theme
  fake_plugin_dir tmux-battery

  configure_battery >/dev/null

  run get_option @batt_color_charge_primary_tier8
  assert_output "${THEME[primary]}"

  run get_option @batt_color_charge_primary_tier1
  assert_output "${THEME[stress]}"

  rm -rf "$_fake_plugins"
}

@test "configure_battery sets discharge icons" {
  init_theme
  fake_plugin_dir tmux-battery

  configure_battery >/dev/null

  run get_option @batt_icon_charge_tier8
  assert_output '█'

  run get_option @batt_icon_charge_tier1
  assert_output '▁'

  rm -rf "$_fake_plugins"
}

@test "configure_battery returns empty when not installed" {
  init_theme
  fake_plugin_dir

  run configure_battery
  assert_output ""

  rm -rf "$_fake_plugins"
}
