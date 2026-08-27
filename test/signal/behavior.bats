#!/usr/bin/env bats

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load
load ../support/helper

# Signal behavior runs in-process over the mechanical fake. Renderer tests cover
# projection details; these tests cover the public signal service boundary.
setup() { load_signal; }
teardown() { :; }

@test "status stores contributors, shows them, and clears them" {
  signal_status_set build active
  signal_status_set review attention
  run signal_status_show
  assert_output --partial "build"
  assert_output --partial "review"
  run signal_status_show build
  assert_output active
  signal_status_clear review
  signal_status_clear build
  run signal_status_show
  assert_output ""
}

@test "status validates levels and target options at the command boundary" {
  run signal_status_set build bogus
  assert_failure
  assert_output --partial "invalid value"
  run signal_status_set build active -t
  assert_failure
  assert_output --partial "-t requires <window>"
  run signal_status_clear build -t
  assert_failure
  run signal_status_show -t
  assert_failure
}

@test "health recovery clears its contributor" {
  signal_health_set cpu fail
  run signal_health_show cpu
  assert_output fail
  signal_health_set cpu ok
  run signal_health_show cpu
  assert_output ""
}

@test "health validates levels at the command boundary" {
  run signal_health_set disk warpspeed
  assert_failure
  assert_output --partial "invalid value"
}

@test "problem behavior reduces contributors and records recovery" {
  signal_problem_set s1 cpu warn "sensors missing"
  signal_problem_set s1 battery fail "query timed out"
  run signal_problem_show s1 cpu
  assert_output "$(printf 'warn\tsensors missing')"
  signal_problem_clear s1 battery
  signal_problem_set s1 cpu ok
  run signal_problem_show s1 cpu
  assert_output ""
}

@test "problem validates its public tuple contract" {
  run signal_problem_set
  assert_failure
  assert_output --partial "need <session>"
  run signal_problem_set s1 cpu bogus message
  assert_failure
  run signal_problem_set s1 cpu warn
  assert_failure
  assert_output --partial "need <message>"
  run signal_problem_clear s1
  assert_failure
  assert_output --partial "need <key>"
}

@test "clear-transient removes only transient contributors" {
  signal_status_set build active
  signal_status_set review attention --transient
  assert_equal "${_FAKE_HOOK[pane-focus-out[90]]}" \
    "run-shell -b \"'$AIRLINE_DIR/airline.sh' signal clear-transient -t #{window_id}\""
  signal_clear_transient -t "$_FAKE_WIN"
  run signal_status_show build
  assert_output active
  run signal_status_show review
  assert_output ""
}

@test "signal target options validate at the boundary" {
  run signal_clear_transient -t
  assert_failure
  assert_output --partial "-t requires <window>"
}

@test "identical problem reports and absent clears do not redraw" {
  signal_problem_set s1 cpu warn "sensors missing"
  assert_equal "$_FAKE_REDRAWS" 1
  signal_problem_set s1 cpu warn "sensors missing"
  assert_equal "$_FAKE_REDRAWS" 1
  signal_problem_clear s1 cpu
  assert_equal "$_FAKE_REDRAWS" 2
  signal_problem_clear s1 cpu
  assert_equal "$_FAKE_REDRAWS" 2
}

@test "identical status and health reports and absent clears do not redraw" {
  signal_status_set agent active
  signal_health_set context warn
  assert_equal "$_FAKE_REDRAWS" 2
  local writes="$_FAKE_WRITES"

  signal_status_set agent active
  signal_health_set context warn
  assert_equal "$_FAKE_REDRAWS" 2
  assert_equal "$_FAKE_WRITES" "$writes"

  signal_status_clear missing
  signal_health_clear missing
  assert_equal "$_FAKE_REDRAWS" 2
  assert_equal "$_FAKE_WRITES" "$writes"
}

@test "managed configuration problems use the same redraw-gated service" {
  signal_problem_report s1 airline-layout fail "layout failed"
  assert_equal "$_FAKE_REDRAWS" 1
  signal_problem_report s1 airline-layout fail "layout failed"
  assert_equal "$_FAKE_REDRAWS" 1
  signal_problem_report s1 airline-layout ok ""
  assert_equal "$_FAKE_REDRAWS" 2
}
