#!/usr/bin/env bats

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load
load ../support/helper

# Lifecycle behavior runs in-process over the mechanical fake. Signal behavior has
# its own module suite; this file covers session initialization and state.
setup() { load_lifecycle; }
teardown() { :; }

@test "targeted session init resolves that session and publishes a public hook" {
  _init_unlocked () { _INITIALIZED_SESSION="$1"; }
  lifecycle_init -t s2

  assert_equal "$_INITIALIZED_SESSION" s2
  assert_equal "${_FAKE_HOOK[after-new-session[90]]}" \
    "run-shell -b \"'$AIRLINE_DIR/airline.sh' session init -t '#{session_id}'\""
}

@test "session suspend, resume, and toggle expose one session state" {
  run lifecycle_show state
  assert_output active

  lifecycle_session_suspend
  run lifecycle_show state
  assert_output suspended
  run opt_get_session "$_FAKE_SESSION" prefix
  assert_output None

  lifecycle_session_resume
  run lifecycle_show state
  assert_output active
  run opt_get_session "$_FAKE_SESSION" prefix
  assert_output ""

  lifecycle_session_toggle
  run lifecycle_show state
  assert_output suspended
}

@test "session init target options validate at the boundary" {
  run lifecycle_init -t
  assert_failure
  assert_output --partial "-t requires <session>"
}
