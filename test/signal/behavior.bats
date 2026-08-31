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
  signal_health_set test cpu fail "sensor unavailable"
  run signal_health_show test cpu
  assert_output "$(printf 'fail\tsensor unavailable')"
  signal_health_set test cpu ok
  run signal_health_show test cpu
  assert_output ""
}

@test "health contributors may use the same claim key independently" {
  signal_health_set sensors cpu warn "temperature high"
  signal_health_set scheduler cpu fail "worker unavailable"

  run signal_health_show sensors cpu
  assert_output "$(printf 'warn\ttemperature high')"
  run signal_health_show scheduler cpu
  assert_output "$(printf 'fail\tworker unavailable')"

  signal_health_clear sensors cpu
  run signal_health_show scheduler cpu
  assert_output "$(printf 'fail\tworker unavailable')"
}

@test "health retains opaque diagnostics without redrawing an unchanged badge" {
  signal_health_set test api fail "connection refused" "after -t retry"
  run signal_health_show test api
  assert_output "$(printf 'fail\tconnection refused after -t retry')"
  run signal_health_show
  assert_output --partial "connection refused after -t retry"
  assert_equal "$_FAKE_REDRAWS" 1
  [[ -z "${_FAKE_HOOK[pane-focus-out[90]]:-}" ]]

  local writes="$_FAKE_WRITES"
  signal_health_set test api fail "request timed out"
  assert_equal "$_FAKE_REDRAWS" 1
  [[ "$_FAKE_WRITES" -gt "$writes" ]]
  run signal_health_show test api
  assert_output "$(printf 'fail\trequest timed out')"

  run signal_health_set test api fail $'bad\tmessage'
  assert_failure
  assert_output --partial "message must not contain a tab"
}

@test "health validates levels at the command boundary" {
  run signal_health_set test disk warpspeed message
  assert_failure
  assert_output --partial "invalid level"
}

@test "status health and problem mutations share one projection pipeline" {
  local calls=""
  _signal_project_and_redraw () { calls+="${calls:+ }$1:$2:$3"; }

  signal_status_set build active
  signal_health_set test api warn "slow"
  signal_problem_set test cpu fail "missing"

  assert_equal "$calls" "window:@1:status window:@1:health global:server:problem"
}

@test "global problems retain independent session and pane claims" {
  signal_problem_set test cpu warn "sensors missing"
  signal_problem_set --pane %2 test cpu fail "query timed out"
  run signal_problem_show --all test cpu
  assert_output --partial "active  fail"
  assert_output --partial "session:s1"
  assert_output --partial "pane:%2"
  run prv_get_global "$AIRLINE_KEY_PROBLEM"
  assert_output fail

  signal_problem_set --pane %2 test cpu ok
  run prv_get_global "$AIRLINE_KEY_PROBLEM"
  assert_output warn
  signal_problem_set test cpu ok
  run signal_problem_show --all test cpu
  assert_output ""
}

@test "problem contributors may use the same claim key independently" {
  signal_problem_set sensors unavailable warn "sensors missing"
  signal_problem_set battery unavailable fail "battery query failed"

  run signal_problem_show sensors unavailable
  assert_output --partial "warn"
  refute_output --partial "battery query failed"
  signal_problem_clear sensors unavailable

  run signal_problem_show battery unavailable
  assert_output --partial "active  fail"
}

@test "problem validates its public tuple contract" {
  run signal_problem_set
  assert_failure
  assert_output --partial "need <contributor>"
  run signal_problem_set test cpu bogus message
  assert_failure
  run signal_problem_set test cpu warn
  assert_failure
  assert_output --partial "need <message>"
  run signal_problem_set --pane
  assert_failure
  assert_output --partial "--pane requires <pane-id>"
  run signal_problem_clear
  assert_failure
  assert_output --partial "need exactly <contributor> <key>"
}

@test "clear stays cleared until explicit recovery removes the ledger" {
  signal_problem_set test cpu fail "sensors missing"
  signal_problem_clear test cpu
  run signal_problem_show test cpu
  assert_output ""
  run signal_problem_show --all test cpu
  assert_output --partial "cleared  fail"
  run prv_get_global "$AIRLINE_KEY_PROBLEM"
  assert_output ""

  signal_problem_set test cpu fail "still missing"
  run signal_problem_show --all test cpu
  assert_output --partial "cleared  fail  still missing"
  run prv_get_global "$AIRLINE_KEY_PROBLEM"
  assert_output ""

  signal_problem_set test cpu ok
  run signal_problem_show test cpu
  assert_output ""
}

@test "closing the final origin retains a closed ledger and resolve deletes it" {
  signal_problem_set --pane %2 test cpu warn "sensors missing"
  signal_problem_close --pane %2
  run signal_problem_show test cpu
  assert_output ""
  run signal_problem_show --all test cpu
  assert_output --partial "closed  warn  sensors missing"
  refute_output --partial "pane:%2"
  run prv_get_global "$AIRLINE_KEY_PROBLEM"
  assert_output ""

  # A contributor that never held this claim cannot resolve its closed history.
  _FAKE_SESSION=s2
  signal_problem_set test cpu ok
  run signal_problem_show --all test cpu
  assert_output --partial "closed"

  signal_problem_resolve test cpu
  run signal_problem_show test cpu
  assert_output ""
}

@test "keyless status clear removes only transient contributors" {
  signal_status_set build active
  signal_status_set review attention --transient
  signal_health_set test api fail "connection refused"
  assert_equal "${_FAKE_HOOK[pane-focus-out[90]]}" \
    "run-shell -b \"'$AIRLINE_DIR/airline.sh' status clear -t #{window_id}\""
  signal_status_clear -t "$_FAKE_WIN"
  run signal_status_show build
  assert_output active
  run signal_status_show review
  assert_output ""
  run signal_health_show test api
  assert_output "$(printf 'fail\tconnection refused')"

  local redraws="$_FAKE_REDRAWS" writes="$_FAKE_WRITES"
  signal_status_clear -t "$_FAKE_WIN"
  assert_equal "$_FAKE_REDRAWS" "$redraws"
  assert_equal "$_FAKE_WRITES" "$writes"

  signal_status_set deploy result --transient
  signal_status_clear deploy
  run signal_status_show deploy
  assert_output ""
}

@test "signal target options validate at the boundary" {
  run signal_status_clear -t
  assert_failure
  assert_output --partial "-t requires <window>"
}

@test "status and health enforce exact grammar before mutation" {
  local writes="$_FAKE_WRITES" argv
  while IFS= read -r argv; do
    run $argv
    assert_failure "$argv"
    assert_equal "$_FAKE_WRITES" "$writes" "$argv"
  done <<'CASES'
signal_status_set build active extra
signal_status_set build active -t @1 -t @1
signal_status_set build active --transient --transient
signal_status_clear build extra
signal_status_show build extra
signal_health_set test api fail
signal_health_set test api ok unexpected-message
signal_health_set --transient api fail message
signal_health_clear test api --transient
CASES

  run signal_status_set 'bad key' active
  assert_failure
  run signal_status_clear 'bad key'
  assert_failure
  run signal_health_show 'bad contributor'
  assert_failure
  assert_equal "$_FAKE_WRITES" "$writes"
}

@test "valid signal option orderings remain accepted" {
  signal_status_set --transient -t "$_FAKE_WIN" build result
  signal_health_set -t "$_FAKE_WIN" test api warn "slow response"
  run signal_health_show -t "$_FAKE_WIN" test api
  assert_output "$(printf 'warn\tslow response')"
}

@test "signal services propagate resolution, transaction, callback, and reporting failures" {
  resolve_window () { return 9; }
  run signal_status_set build active -t missing
  assert_failure 2
  assert_output --partial "cannot resolve window 'missing'"

  resolve_window () { printf '%s' "$1"; }
  with_window_transaction () { return 7; }
  run signal_health_clear test api
  assert_failure 7

  with_window_transaction () { local callback="$3"; shift 3; "$callback" "$@"; }
  _signal_status_set_unlocked () { return 6; }
  run signal_status_set build active
  assert_failure 6

  with_global_transaction () { return 5; }
  run signal_problem_report s1 airline airline-layout fail "layout failed"
  assert_failure 5
}

@test "problem keys are validated consistently before mutation" {
  local writes="$_FAKE_WRITES"
  run signal_problem_set test 'bad key' warn message
  assert_failure
  run signal_problem_clear test 'bad key'
  assert_failure
  run signal_problem_show test 'bad key'
  assert_failure
  assert_equal "$_FAKE_WRITES" "$writes"
}

@test "problem ledger and claims retain severity and diagnostic framing" {
  signal_health_set test api fail "connection refused"
  signal_problem_set test api fail "connection refused"
  assert_equal "$(coll_get_global problem test:api)" \
    "$(printf 'fail\tactive\tfail\tconnection refused')"
  assert_equal "$(coll_get_global problem-claim session:s1:test:api)" \
    "$(printf 'test\tapi\tsession\ts1\tfail\tconnection refused')"

  run signal_health_show test api
  assert_output "$(printf 'fail\tconnection refused')"
  run signal_problem_show test api
  assert_output --partial "session:s1"
}

@test "identical problem reports and absent lifecycle operations do not redraw" {
  signal_problem_set test cpu warn "sensors missing"
  assert_equal "$_FAKE_REDRAWS" 1
  local writes="$_FAKE_WRITES"
  signal_problem_set test cpu warn "sensors missing"
  assert_equal "$_FAKE_REDRAWS" 1
  assert_equal "$_FAKE_WRITES" "$writes"
  signal_problem_clear test cpu
  assert_equal "$_FAKE_REDRAWS" 2
  signal_problem_clear test cpu
  assert_equal "$_FAKE_REDRAWS" 2
  signal_problem_close --pane %9
  assert_equal "$_FAKE_REDRAWS" 2
  signal_problem_resolve test missing
  assert_equal "$_FAKE_REDRAWS" 2
}

@test "identical status and health reports and absent clears do not redraw" {
  signal_status_set agent active
  signal_health_set test context warn "context pressure"
  assert_equal "$_FAKE_REDRAWS" 2
  local writes="$_FAKE_WRITES"

  signal_status_set agent active
  signal_health_set test context warn "context pressure"
  assert_equal "$_FAKE_REDRAWS" 2
  assert_equal "$_FAKE_WRITES" "$writes"

  signal_status_clear missing
  signal_health_clear test missing
  assert_equal "$_FAKE_REDRAWS" 2
  assert_equal "$_FAKE_WRITES" "$writes"
}

@test "managed configuration problems use the same redraw-gated service" {
  signal_problem_report s1 airline airline-layout fail "layout failed"
  assert_equal "$_FAKE_REDRAWS" 1
  signal_problem_report s1 airline airline-layout fail "layout failed"
  assert_equal "$_FAKE_REDRAWS" 1
  signal_problem_report s1 airline airline-layout ok ""
  assert_equal "$_FAKE_REDRAWS" 2
}
