#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load
load helper

setup() {
  $TMUX -L "$_bats_socket" -f /dev/null new-session -d -s bats
}

@test "PATH shim resolves and delegates to the initialized CLI" {
  airline init
  pane="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{pane_id}')"

  run env TMUX_PANE="$pane" AIRLINE_TMUX="$TMUX -L $_bats_socket" \
    "$PROJECT_ROOT/airline" state show

  assert_success
  assert_output "active"
}

@test "PATH shim explains when tmux-airline is not initialized" {
  run env AIRLINE_TMUX="$TMUX -L $_bats_socket" "$PROJECT_ROOT/airline" help

  assert_failure
  assert_output \
    "airline: tmux-airline is not initialized; start or reload tmux first"
}

@test "PATH shim rejects a stale configured CLI path" {
  $TMUX -L "$_bats_socket" set-option -g @airline-cli /does/not/exist

  run env AIRLINE_TMUX="$TMUX -L $_bats_socket" "$PROJECT_ROOT/airline" help

  assert_failure
  assert_output "airline: configured CLI is not executable: /does/not/exist"
}
