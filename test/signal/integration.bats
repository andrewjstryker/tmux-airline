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

  airline status set -t "$pane" active
  airline health set -t "$pane" example-agent context warn "agent is degraded"

  run wopt @airline--badge-status -t "$window"
  assert_output "active"
  run airline status show -t "$pane"
  assert_output --partial "$pane"
  assert_output --partial "active  revision 1"
  run wopt @airline--badge-health -t "$window"
  assert_output "warn"
  run airline health show -t "$pane" example-agent context
  assert_output "$(printf 'warn\tagent is degraded')"
}

@test "health retains a diagnostic while projecting only its severity" {
  airline health set test api fail "connection refused" "after retry"

  run airline health show test api
  assert_success
  assert_output "$(printf 'fail\tconnection refused after retry')"
  run wopt @airline--badge-health
  assert_output fail
}

@test "global problem ledger is visible in every initialized session" {
  airline session init
  session="$($TMUX -L "$_bats_socket" display-message -p '#{session_id}')"
  airline problem set example-cpu sensors warn "required program 'sensors' was not found"
  airline problem set example-battery query fail "battery query timed out"
  run get_option @airline--badge-problem
  assert_output "fail"
  run $TMUX -L "$_bats_socket" display-message -p -t "$session" '#{E:status-right}'
  assert_output --partial "▲"

  $TMUX -L "$_bats_socket" new-session -d -s other
  other="$($TMUX -L "$_bats_socket" display-message -p -t other '#{session_id}')"
  airline_session other session init
  airline_session other problem set example-other capability warn "other session degraded"
  airline problem close --session other example-other capability
  run airline problem show --all example-other capability
  assert_output --partial "closed"
  run $TMUX -L "$_bats_socket" display-message -p -t "$other" '#{E:status-right}'
  assert_output --partial "▲"

  run airline problem show
  assert_output --partial "example-cpu"
  assert_output --partial "sensors"
  assert_output --partial "example-battery"
  assert_output --partial "battery query timed out"

  airline problem set example-battery query ok
  run get_option @airline--badge-problem
  assert_output "warn"
  airline problem ack example-cpu sensors
  run get_option @airline--badge-problem
  assert_output ""
  run airline problem show --all example-cpu sensors
  assert_output --partial "acknowledged"
  airline problem resolve example-cpu sensors
  run airline problem show example-cpu sensors
  assert_output ""
  run airline problem show --all example-cpu sensors
  assert_output --partial "resolved"
}

@test "pane lifecycle hooks close claims and retain a closed ledger" {
  local ready="problem-pane-ready-$BATS_TEST_NUMBER" release="problem-pane-release-$BATS_TEST_NUMBER"
  airline session init
  pane="$($TMUX -L "$_bats_socket" split-window -dP -F '#{pane_id}' -t bats \
    "tmux wait-for -S '$ready'; tmux wait-for '$release'")"
  $TMUX -L "$_bats_socket" wait-for "$ready"
  airline problem set --pane "$pane" example-cpu sensors fail "sensor unavailable"
  run get_option @airline--badge-problem
  assert_output fail

  $TMUX -L "$_bats_socket" wait-for -S "$release"
  output=active
  for _ in {1..100}; do
    output="$(airline problem show --all example-cpu sensors)"
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
  second_target="$($TMUX -L "$_bats_socket" display-message -p -t "$second" \
    '#{session_name}:#{window_index}.#{pane_index}')"
  airline problem set --pane "$first" example-cpu sensors warn "first degraded"
  airline problem set --pane "$second" example-cpu sensors fail "second failed"
  airline problem close --pane "$second_target" example-cpu sensors

  run airline problem show example-cpu sensors
  assert_output --partial "active  warn"
  assert_output --partial "pane:$first"
  refute_output --partial "pane:$second"
}

@test "tmux's pane-focus-out hook clears an observed result" {
  airline session init
  pane="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{pane_id}')"
  win="$($TMUX -L "$_bats_socket" display-message -p '#{window_id}')"

  airline status set -t "$pane" result
  run get_option focus-events
  assert_output "on"

  # A detached test server has no terminal focus to move. Ask tmux itself to run
  # the registered hook in the pane's context, preserving format expansion and
  # the asynchronous process boundary used by a real focus-out event.
  $TMUX -L "$_bats_socket" set-hook -R -t "$pane" pane-focus-out
  output="$pane"
  for _ in {1..100}; do
    output="$(airline status show -t "$win")"
    [[ "$output" != *"$pane"* ]] && break
    sleep 0.01
  done
  [[ "$output" != *"$pane"* ]]
}

@test "invalid signal argv and unresolved targets fail without mutation" {
  run airline status set active extra
  assert_failure
  run airline health set test api fail
  assert_failure
  run airline status set -t missing-pane active
  assert_failure
  assert_output --partial "cannot resolve pane 'missing-pane'"

  run wopt @airline--status
  assert_output ""
  run wopt @airline--health
  assert_output ""
}

@test "process CLI propagates transaction acquisition failure" {
  run airline_with_tmux_failure acquire status set active
  assert_failure
}

@test "process CLI propagates mutation flush failure" {
  run airline_with_tmux_failure flush health set test api fail "connection refused"
  assert_failure
}

@test "process CLI propagates transaction release failure" {
  run airline_with_tmux_failure release status set active
  assert_failure
}

@test "process CLI propagates failed problem reporting" {
  run airline_with_tmux_failure flush problem set test cpu fail "sensor unavailable"
  assert_failure
}
