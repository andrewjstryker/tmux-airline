#!/usr/bin/env bats

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load
load ../support/helper

# Session behavior runs in-process over the mechanical fake. Signal behavior has
# its own module suite; this file covers session initialization and state.
setup() { load_session; }
teardown() { :; }

@test "targeted session init resolves that session and publishes a public hook" {
  layout_initialize () { _INITIALIZED_SESSION="$1"; }
  session_init -t s2

  assert_equal "$_INITIALIZED_SESSION" s2
  assert_equal "${_FAKE_HOOK[after-new-session[90]]}" \
    "run-shell -b \"'$AIRLINE_DIR/airline.sh' session init -t '#{session_id}'\""
  assert_equal "${_FAKE_HOOK[after-new-window[90]]}" airline-window-styles
  assert_equal "${_FAKE_HOOK[pane-exited[90]]}" \
    "run-shell -b \"'$AIRLINE_DIR/airline.sh' problem close --pane '#{hook_pane}'\""
  assert_equal "${_FAKE_HOOK[window-layout-changed[90]]}" \
    "run-shell -b \"'$AIRLINE_DIR/airline.sh' health project-all\""
  assert_equal "${_FAKE_HOOK[pane-died[90]]}" \
    "run-shell -b \"'$AIRLINE_DIR/airline.sh' problem close --pane '#{hook_pane}'\""
  assert_equal "${_FAKE_HOOK[session-closed[90]]}" \
    "run-shell -b \"'$AIRLINE_DIR/airline.sh' problem close --session '#{hook_session}'\""
}

@test "session suspend, resume, and toggle expose one session state" {
  run session_show state
  assert_output active

  session_suspend
  run session_show state
  assert_output suspended
  run opt_get_session "$_FAKE_SESSION" prefix
  assert_output None

  session_resume
  run session_show state
  assert_output active
  run opt_get_session "$_FAKE_SESSION" prefix
  assert_output ""

  session_toggle
  run session_show state
  assert_output suspended
}

@test "session state changes propagate render and option failures" {
  _opt_write () { return 72; }

  run session_suspend
  assert_failure 72
}

@test "session init target options validate at the boundary" {
  run session_init -t
  assert_failure
  assert_output --partial "-t requires <session-target>"
}
