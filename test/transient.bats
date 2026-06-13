#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load
load helper

# Consume-on-view: a signal set with --transient clears itself when you leave the
# window (pane-focus-out → `airline _unfocus`). Like the original tests, these
# drive the _unfocus handler directly rather than firing real focus events.

_winid() { $TMUX -L "$_bats_socket" display -p '#{window_id}'; }

# --- markers ----------------------------------------------------------------

@test "status set --transient marks the lane transient" {
  airline status register agent ⟳ 20
  airline status set agent active --transient
  run wopt @airline-status-agent-transient
  assert_output "1"
}

@test "status set without --transient clears a prior transient mark" {
  airline status register agent ⟳ 20
  airline status set agent active --transient
  airline status set agent active
  run wopt @airline-status-agent-transient
  assert_output ""
}

@test "health set --transient marks the contributor transient" {
  airline health set ctx stress --transient
  run wopt @airline-health-ctx-transient
  assert_output "1"
}

# --- consume-on-view clearing ------------------------------------------------

@test "_unfocus clears a transient lane but leaves a sticky one" {
  airline status register a ● 10
  airline status register b ● 20
  airline status set a active --transient
  airline status set b stress
  airline _unfocus "$(_winid)"
  run wopt @airline-status-a
  assert_output ""
  run wopt @airline-status-b
  assert_output "stress"
}

@test "_unfocus clears a transient health key and re-reduces" {
  airline health set ctx stress --transient
  airline health set build alert
  airline _unfocus "$(_winid)"
  run wopt @airline-health-ctx
  assert_output ""
  run wopt @airline-health-build
  assert_output "alert"
  run wopt @airline-health
  assert_output "alert"
}

@test "_unfocus leaves a window with no transient signals untouched" {
  airline status register a ● 10
  airline status set a active
  airline _unfocus "$(_winid)"
  run wopt @airline-status-a
  assert_output "active"
}

# --- plumbing ---------------------------------------------------------------

@test "--transient enables focus-events and registers the unfocus hook" {
  airline status register agent ⟳ 20
  airline status set agent active --transient
  run get_option focus-events
  assert_output "on"
  run $TMUX -L "$_bats_socket" show-hooks -g pane-focus-out
  assert_output --partial "_unfocus"
}

@test "the unfocus hook is idempotent across repeated --transient sets" {
  airline status register agent ⟳ 20
  airline status set agent active --transient
  airline status set agent alert --transient
  run $TMUX -L "$_bats_socket" show-hooks -g pane-focus-out
  assert_equal "$(echo "$output" | grep -c "_unfocus")" "1"
}

@test "health list ignores transient markers" {
  airline health set ctx stress --transient
  run airline health list
  refute_output --partial "ctx-transient"
  assert_output --partial "ctx	stress"
}
