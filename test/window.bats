#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load
load helper

# --- structure --------------------------------------------------------------

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
  assert_output --partial "${THEME[active]}"
  assert_output --partial "#I:#W"
}

@test "set_window_formats uses custom template when set" {
  init_theme
  $TMUX -L "$_bats_socket" set -g @airline-tmpl-window '#W'
  set_window_formats
  run get_option window-status-format
  assert_output --partial "#W"
}

# --- entry color: tmux modes on inactive windows (foreground) ---------------

@test "inactive: a monitored window name takes the monitor color" {
  init_theme
  set_window_formats
  tmux set -w monitor-activity on
  run resolve "$(get_option window-status-format)"
  assert_output --partial "fg=${THEME[monitor]}"
}

@test "inactive: a zoomed window name takes the zoom color" {
  init_theme
  set_window_formats
  tmux split-window -d
  tmux resize-pane -Z
  run resolve "$(get_option window-status-format)"
  assert_output --partial "fg=${THEME[zoom]}"
}

@test "inactive: no mode leaves the name to the base style" {
  init_theme
  set_window_formats
  run resolve "$(get_option window-status-format)"
  refute_output --partial "fg=${THEME[zoom]}"
  refute_output --partial "fg=${THEME[monitor]}"
  refute_output --partial "fg=${THEME[copy]}"
}

@test "inactive: zoom takes precedence over monitor" {
  init_theme
  set_window_formats
  tmux set -w monitor-activity on
  tmux split-window -d
  tmux resize-pane -Z
  run resolve "$(get_option window-status-format)"
  assert_output --partial "fg=${THEME[zoom]}"
  refute_output --partial "fg=${THEME[monitor]}"
}

# --- entry color: tmux modes on the focused window (highlight background) ----

@test "active: a zoomed window highlight becomes the zoom color" {
  init_theme
  set_window_formats
  tmux split-window -d
  tmux resize-pane -Z
  run resolve "$(get_option window-status-current-format)"
  assert_output --partial "bg=${THEME[zoom]}"
}

@test "active: a monitored window highlight becomes the monitor color" {
  init_theme
  set_window_formats
  tmux set -w monitor-activity on
  run resolve "$(get_option window-status-current-format)"
  assert_output --partial "bg=${THEME[monitor]}"
}

@test "active: no mode uses the normal active highlight" {
  init_theme
  set_window_formats
  run resolve "$(get_option window-status-current-format)"
  assert_output --partial "bg=${THEME[active]}"
  refute_output --partial "bg=${THEME[zoom]}"
}

@test "active: the name stays knocked out in inner-bg over the highlight" {
  init_theme
  set_window_formats
  tmux split-window -d
  tmux resize-pane -Z
  run resolve "$(get_option window-status-current-format)"
  # highlight in zoom, but the name text is still inner-bg (reverse video)
  assert_output --partial "bg=${THEME[zoom]}"
  assert_output --partial "fg=${THEME[inner-bg]}"
}

# --- health gutter (left) ---------------------------------------------------

@test "window-status-format embeds the health expression" {
  init_theme
  set_window_formats
  run get_option window-status-format
  assert_output --partial "@airline-health"
}

@test "health: a severity renders the gutter glyph in that color" {
  init_theme
  set_window_formats
  tmux set -w @airline-health stress
  run resolve "$(get_option window-status-format)"
  assert_output --partial "fg=${THEME[stress]}"
  assert_output --partial "●"
}

@test "health: no severity leaves the gutter empty" {
  init_theme
  set_window_formats
  run resolve "$(get_option window-status-format)"
  refute_output --partial "●"
}

@test "health: the gutter glyph is configurable" {
  init_theme
  $TMUX -L "$_bats_socket" set -g @airline-health-glyph "◆"
  set_window_formats
  tmux set -w @airline-health alert
  run resolve "$(get_option window-status-format)"
  assert_output --partial "◆"
  assert_output --partial "fg=${THEME[alert]}"
}
