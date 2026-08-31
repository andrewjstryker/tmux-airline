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
  airline health set -t "$pane" example-agent/context warn "agent is degraded"

  run wopt @airline--badge-status -t "$window"
  assert_output "active"
  run wopt @airline--badge-health -t "$window"
  assert_output "warn"
  run airline health show -t "$pane" example-agent/context
  assert_output "$(printf 'warn\tagent is degraded')"
}

@test "health retains a diagnostic while projecting only its severity" {
  airline health set api fail "connection refused" "after retry"

  run airline health show api
  assert_success
  assert_output "$(printf 'fail\tconnection refused after retry')"
  run wopt @airline--badge-health
  assert_output fail
}

@test "global problem ledger is visible in every initialized session" {
  airline session init
  session="$($TMUX -L "$_bats_socket" display-message -p '#{session_id}')"
  airline problem set example-cpu/sensors warn "required program 'sensors' was not found"
  airline problem set example-battery/query fail "battery query timed out"
  run get_option @airline--badge-problem
  assert_output "fail"
  run $TMUX -L "$_bats_socket" display-message -p -t "$session" '#{E:status-right}'
  assert_output --partial "▲"

  $TMUX -L "$_bats_socket" new-session -d -s other
  other="$($TMUX -L "$_bats_socket" display-message -p -t other '#{session_id}')"
  airline_session other session init
  run $TMUX -L "$_bats_socket" display-message -p -t "$other" '#{E:status-right}'
  assert_output --partial "▲"

  run airline problem show
  assert_output --partial "example-cpu/sensors"
  assert_output --partial "sensors"
  assert_output --partial "example-battery/query"
  assert_output --partial "battery query timed out"

  airline problem set example-battery/query ok
  run get_option @airline--badge-problem
  assert_output "warn"
  airline problem clear example-cpu/sensors
  run get_option @airline--badge-problem
  assert_output ""
  run airline problem show --all example-cpu/sensors
  assert_output --partial "cleared"
  airline problem resolve example-cpu/sensors
  run airline problem show example-cpu/sensors
  assert_output ""
}

@test "pane lifecycle hooks close claims and retain a closed ledger" {
  local ready="problem-pane-ready-$BATS_TEST_NUMBER" release="problem-pane-release-$BATS_TEST_NUMBER"
  airline session init
  pane="$($TMUX -L "$_bats_socket" split-window -dP -F '#{pane_id}' -t bats \
    "tmux wait-for -S '$ready'; tmux wait-for '$release'")"
  $TMUX -L "$_bats_socket" wait-for "$ready"
  airline problem set --pane "$pane" example-cpu/sensors fail "sensor unavailable"
  run get_option @airline--badge-problem
  assert_output fail

  $TMUX -L "$_bats_socket" wait-for -S "$release"
  output=active
  for _ in {1..100}; do
    output="$(airline problem show --all example-cpu/sensors)"
    [[ "$output" == *closed* ]] && break
    sleep 0.01
  done
  [[ "$output" == *closed* ]]
  [[ "$output" != *"pane:$pane"* ]]
  run get_option @airline--badge-problem
  assert_output ""
}

@test "multiple pane claims close independently" {
  airline session init
  first="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{pane_id}')"
  second="$($TMUX -L "$_bats_socket" split-window -dP -F '#{pane_id}' -t bats)"
  airline problem set --pane "$first" example-cpu/sensors warn "first degraded"
  airline problem set --pane "$second" example-cpu/sensors fail "second failed"
  airline problem close --pane "$second" example-cpu/sensors

  run airline problem show example-cpu/sensors
  assert_output --partial "active  warn"
  assert_output --partial "pane:$first"
  refute_output --partial "pane:$second"
}

@test "a transient status arms the focus hook and clears through normal status clear" {
  airline session init
  win="$($TMUX -L "$_bats_socket" display-message -p '#{window_id}')"
  airline status set build active
  airline status set review attention --transient
  run get_option focus-events
  assert_output "on"
  airline status clear -t "$win"
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
  run airline_with_tmux_failure flush problem set cpu fail "sensor unavailable"
  assert_failure
}
