#!/usr/bin/env bats

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load
load ../support/helper

# Public signal commands through the real CLI and an isolated tmux server.
setup() {
  $TMUX -L "$_bats_socket" -f /dev/null new-session -d -s bats
}

@test "status and health accept a pane target and store on its containing window" {
  airline session init
  pane="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{pane_id}')"
  window="$($TMUX -L "$_bats_socket" display-message -p -t "$pane" '#{window_id}')"

  airline status set agent active -t "$pane"
  airline health set -t "$pane" agent warn "agent is degraded"

  run wopt @airline--badge-status -t "$window"
  assert_output "active"
  run wopt @airline--badge-health -t "$window"
  assert_output "warn"
}

@test "health retains a diagnostic while projecting only its severity" {
  airline health set api fail "connection refused" "after retry"

  run airline health show api
  assert_success
  assert_output "$(printf 'fail\tconnection refused after retry')"
  run wopt @airline--badge-health
  assert_output fail
}

@test "problem contributors reduce to one session badge and recover independently" {
  airline session init
  session="$($TMUX -L "$_bats_socket" display-message -p '#{session_id}')"
  airline problem set "$session" cpu warn "required program 'sensors' was not found"
  airline problem set "$session" battery fail "battery query timed out"
  run sopt @airline--badge-problem -t "$session"
  assert_output "fail"
  run $TMUX -L "$_bats_socket" display-message -p -t "$session" '#{E:status-right}'
  assert_output --partial "▲"

  $TMUX -L "$_bats_socket" new-session -d -s other
  other="$($TMUX -L "$_bats_socket" display-message -p -t other '#{session_id}')"
  run sopt @airline--badge-problem -t "$other"
  assert_output ""
  run $TMUX -L "$_bats_socket" display-message -p -t "$other" '#{E:status-right}'
  refute_output --partial "▲"

  run airline problem show "$session"
  assert_output --partial "cpu"
  assert_output --partial "sensors"
  assert_output --partial "battery"
  assert_output --partial "battery query timed out"

  airline problem clear "$session" battery
  run sopt @airline--badge-problem -t "$session"
  assert_output "warn"
  airline problem clear "$session" cpu
  run sopt @airline--badge-problem -t "$session"
  assert_output ""
}

@test "bare problem show lists problems across sessions" {
  airline session init
  session="$($TMUX -L "$_bats_socket" display-message -p '#{session_id}')"
  $TMUX -L "$_bats_socket" new-session -d -s other
  other="$($TMUX -L "$_bats_socket" display-message -p -t other '#{session_id}')"
  airline problem set "$session" cpu warn "sensors missing"
  airline problem set "$other" battery fail "battery unavailable"

  run airline problem show
  assert_success
  assert_output --partial "$session:"
  assert_output --partial "cpu"
  assert_output --partial "$other:"
  assert_output --partial "battery"
}

@test "a --transient signal arms the focus hook and clears publicly" {
  airline session init
  win="$($TMUX -L "$_bats_socket" display-message -p '#{window_id}')"
  airline status set build active
  airline status set review attention --transient
  run get_option focus-events
  assert_output "on"
  airline signal clear-transient -t "$win"
  run wopt @airline--badge-status
  assert_output "active"
}

@test "invalid signal argv and unresolved targets fail without mutation" {
  run airline status set build active extra
  assert_failure
  run airline health set api fail
  assert_failure
  run airline status set build active -t missing-window
  assert_failure
  assert_output --partial "cannot resolve window 'missing-window'"

  run wopt @airline--status
  assert_output ""
  run wopt @airline--health
  assert_output ""
}

@test "process CLI propagates transaction acquisition failure" {
  run airline_with_tmux_failure acquire status set build active
  assert_failure
}

@test "process CLI propagates mutation flush failure" {
  run airline_with_tmux_failure flush health set api fail "connection refused"
  assert_failure
}

@test "process CLI propagates transaction release failure" {
  run airline_with_tmux_failure release status set build active
  assert_failure
}

@test "process CLI propagates failed problem reporting" {
  session="$($TMUX -L "$_bats_socket" display-message -p '#{session_id}')"
  run airline_with_tmux_failure flush problem set "$session" cpu fail "sensor unavailable"
  assert_failure
}
