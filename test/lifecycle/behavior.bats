#!/usr/bin/env bats

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load
load ../support/helper

# Lifecycle behavior runs in-process over the mechanical fake. Real tmux semantics
# (target resolution, hooks, rendered formats, and locking) stay in lifecycle.bats
# and tmux.bats; these tests exercise the command behavior above that boundary.
setup() { load_lifecycle; }
teardown() { :; }

@test "status stores contributors, shows them, and clears them" {
  lifecycle_status_set build active
  lifecycle_status_set review attention

  run lifecycle_status_show
  assert_output --partial "build"
  assert_output --partial "review"
  run lifecycle_status_show build
  assert_output active
  lifecycle_status_clear review
  lifecycle_status_clear build
  run lifecycle_status_show
  assert_output ""
}

@test "status validates levels and target options at the command boundary" {
  run lifecycle_status_set build bogus
  assert_failure
  assert_output --partial "invalid value"

  run lifecycle_status_set build active -t
  assert_failure
  assert_output --partial "-t requires <window>"
  run lifecycle_status_clear build -t
  assert_failure
  run lifecycle_status_show -t
  assert_failure
}

@test "health recovery clears its contributor" {
  lifecycle_health_set cpu fail
  run lifecycle_health_show cpu
  assert_output fail
  lifecycle_health_set cpu ok
  run lifecycle_health_show cpu
  assert_output ""
}

@test "health validates levels at the command boundary" {
  run lifecycle_health_set disk warpspeed
  assert_failure
  assert_output --partial "invalid value"
}

@test "problem behavior reduces contributors and records recovery" {
  lifecycle_problem_set s1 cpu warn "sensors missing"
  lifecycle_problem_set s1 battery fail "query timed out"

  run lifecycle_problem_show s1 cpu
  assert_output "$(printf 'warn\tsensors missing')"
  lifecycle_problem_clear s1 battery
  lifecycle_problem_set s1 cpu ok
  run lifecycle_problem_show s1 cpu
  assert_output ""
}

@test "problem validates its public tuple contract" {
  run lifecycle_problem_set
  assert_failure
  assert_output --partial "need <session>"
  run lifecycle_problem_set s1 cpu bogus message
  assert_failure
  run lifecycle_problem_set s1 cpu warn
  assert_failure
  assert_output --partial "need <message>"
  run lifecycle_problem_clear s1
  assert_failure
  assert_output --partial "need <key>"
}

@test "transient unfocus removes only transient contributors" {
  lifecycle_status_set build active
  lifecycle_status_set review attention --transient
  lifecycle_unfocus "$_FAKE_WIN"

  run lifecycle_status_show build
  assert_output active
  run lifecycle_status_show review
  assert_output ""
}

@test "state suspend, resume, and toggle expose one lifecycle state" {
  run lifecycle_state_show
  assert_output active

  lifecycle_state_suspend
  run lifecycle_state_show
  assert_output suspended
  run opt_get_session "$_FAKE_SESSION" prefix
  assert_output None

  lifecycle_state_resume
  run lifecycle_state_show
  assert_output active
  run opt_get_session "$_FAKE_SESSION" prefix
  assert_output ""

  lifecycle_state_toggle
  run lifecycle_state_show
  assert_output suspended
}

@test "identical problem reports and absent clears do not redraw" {
  lifecycle_problem_set s1 cpu warn "sensors missing"
  assert_equal "$_FAKE_REDRAWS" 1
  lifecycle_problem_set s1 cpu warn "sensors missing"
  assert_equal "$_FAKE_REDRAWS" 1
  lifecycle_problem_clear s1 cpu
  assert_equal "$_FAKE_REDRAWS" 2
  lifecycle_problem_clear s1 cpu
  assert_equal "$_FAKE_REDRAWS" 2
}

@test "internal configuration problems use the same redraw-gated problem path" {
  _config_problem s1 airline-layout fail "layout failed"
  assert_equal "$_FAKE_REDRAWS" 1
  _config_problem s1 airline-layout fail "layout failed"
  assert_equal "$_FAKE_REDRAWS" 1
  _config_problem s1 airline-layout ok ""
  assert_equal "$_FAKE_REDRAWS" 2
}
