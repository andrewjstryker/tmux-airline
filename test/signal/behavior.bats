#!/usr/bin/env bats

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load
load ../support/helper

# Signal behavior runs in-process over the mechanical fake. Renderer tests cover
# projection details; these tests cover the public signal service boundary.
setup() { load_signal; }
teardown() { :; }

@test "status stores entries, shows them, and clears them" {
  signal_status_set -t %1 active
  signal_status_set -t %2 attention
  run signal_status_show
  assert_output --partial "%1"
  assert_output --partial "active"
  assert_output --partial "revision 1"
  assert_output --partial "%2"
  assert_output --partial "attention"
  signal_status_clear -t %2
  signal_status_clear -t %1
  run signal_status_show
  assert_output ""
}

@test "result revisions are pane-local guards for private observed clearing" {
  signal_status_set -t %1 result
  revision="$(prv_get_pane %1 status-revision)"
  assert_equal "$revision" 1

  # An idempotent result retains the same revision.
  signal_status_set -t %1 result
  assert_equal "$(prv_get_pane %1 status-revision)" "$revision"

  # A different pane owns an independent counter.
  signal_status_set -t %2 result
  assert_equal "$(prv_get_pane %2 status-revision)" 1

  signal_status_set -t %1 active
  signal_status_observed_result %1 "$revision"
  run signal_status_show
  assert_output --partial "%1"
  assert_output --partial "active  revision 2"

  # Even an exact active revision is not an observed result.
  signal_status_observed_result %1 2
  run signal_status_show
  assert_output --partial "active  revision 2"

  signal_status_set -t %1 result
  assert_equal "$(prv_get_pane %1 status-revision)" 3
  signal_status_observed_result %1 3
  run signal_status_show
  refute_output --partial "%1"
  run prv_get_pane %1 status-revision
  assert_output 4
}

@test "status validates levels and target options at the command boundary" {
  run signal_status_set bogus
  assert_failure
  assert_output --partial "invalid value"
  run signal_status_set -t
  assert_failure
  assert_output --partial "-t requires <pane-target>"
  run signal_status_clear -t
  assert_failure
  run signal_status_show -t
  assert_failure
  run signal_status_set active --unknown
  assert_failure
  assert_output --partial "options must precede arguments"
  run signal_status_clear --unknown
  assert_failure
  assert_output --partial "unknown option"
  run signal_status_observed_result %1 nope
  assert_failure
  assert_output --partial "invalid revision"
  run signal_status_observed_result %1
  assert_failure
  assert_output --partial "need <pane> <revision>"
}

@test "health recovery clears its contributor" {
  signal_health_set test cpu fail "sensor unavailable"
  run signal_health_show test cpu
  assert_output "$(printf 'fail\tsensor unavailable')"
  signal_health_set test cpu ok
  run signal_health_show test cpu
  assert_output ""
}

@test "health acknowledgement follows the current level and recovery lifecycle" {
  signal_health_set test api warn "slow response"
  signal_health_ack test api
  run signal_health_show test api
  assert_output ""
  run signal_health_show --all test api
  assert_output "$(printf 'acknowledged\twarn\tslow response')"
  run prv_get_window "$_FAKE_WIN" "$AIRLINE_KEY_HEALTH"
  assert_output ""

  # Diagnostic refreshes do not turn the same acknowledged state back on.
  signal_health_set test api warn "still slow"
  run signal_health_show test api
  assert_output ""
  run signal_health_show --all test api
  assert_output "$(printf 'acknowledged\twarn\tstill slow')"

  # A semantic level change is a new, visible state.
  signal_health_set test api fail "unavailable"
  run signal_health_show test api
  assert_output "$(printf 'fail\tunavailable')"
  run prv_get_window "$_FAKE_WIN" "$AIRLINE_KEY_HEALTH"
  assert_output fail

  signal_health_set test api ok
  run signal_health_show --all test api
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
  assert_output --partial "resolved  warn  sensors missing"
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
  assert_output --partial "--pane requires <pane-target>"
  run signal_problem_clear
  assert_failure
  assert_output --partial "need exactly <contributor> <key>"
}

@test "problem acknowledgement follows the current level and clear deletes all state" {
  signal_problem_set test cpu fail "sensors missing"
  signal_problem_ack test cpu
  run signal_problem_show test cpu
  assert_output ""
  run signal_problem_show --all test cpu
  assert_output --partial "acknowledged  fail"
  run prv_get_global "$AIRLINE_KEY_PROBLEM"
  assert_output ""

  signal_problem_set test cpu fail "still missing"
  run signal_problem_show --all test cpu
  assert_output --partial "acknowledged  fail  still missing"
  run prv_get_global "$AIRLINE_KEY_PROBLEM"
  assert_output ""

  signal_problem_set test cpu warn "partially restored"
  run signal_problem_show test cpu
  assert_output --partial "active  warn"

  signal_problem_clear test cpu
  run signal_problem_show --all test cpu
  assert_output ""
  run coll_members global server problem-claim
  assert_output ""
}

@test "close and resolve retain distinct terminal history" {
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
  run signal_problem_show --all test cpu
  assert_output --partial "resolved  warn  sensors missing"
}

@test "focus clear removes only results at the observation boundary" {
  signal_status_set -t %1 active
  signal_status_set -t %2 attention
  signal_status_set -t %3 result
  signal_status_set -t %4 result
  signal_health_set test api fail "connection refused"
  local boundary
  boundary="$(prv_get_pane %3 status-revision)"

  # A newer result under the same pane identity was not observed at the boundary.
  signal_status_set -t %3 active
  signal_status_set -t %3 result
  signal_status_observed_result %3 "$boundary"
  run signal_status_show
  assert_output --partial "%1"
  assert_output --partial "active"
  assert_output --partial "%2"
  assert_output --partial "attention"
  assert_output --partial "%3"
  assert_output --partial "result"
  assert_output --partial "%4"
  run signal_health_show test api
  assert_output "$(printf 'fail\tconnection refused')"

  local redraws="$_FAKE_REDRAWS" writes="$_FAKE_WRITES"
  signal_status_observed_result %3 "$boundary"
  assert_equal "$_FAKE_REDRAWS" "$redraws"
  assert_equal "$_FAKE_WRITES" "$writes"

  signal_status_clear -t %2
  run signal_status_show
  refute_output --partial "%2"
}

@test "focus clear removes an observed result and leaves no history" {
  signal_status_set -t %1 result
  boundary="$(prv_get_pane %1 status-revision)"
  signal_status_observed_result %1 "$boundary"
  run signal_status_show
  assert_output ""
}

@test "signal target options validate at the boundary" {
  run signal_status_clear -t "$_FAKE_WIN"
  assert_success
}

@test "status and health enforce exact grammar before mutation" {
  local writes="$_FAKE_WRITES" argv
  while IFS= read -r argv; do
    run $argv
    assert_failure
    assert_equal "$_FAKE_WRITES" "$writes" "$argv"
  done <<'CASES'
signal_status_set active extra
signal_status_set active -t %1
signal_status_set -t %1 -t %1 active
signal_status_set result --unknown
signal_status_set active --unknown
signal_status_clear extra
signal_status_clear --unknown
signal_status_observed_result %1
signal_status_observed_result %1 1 extra
signal_status_show extra
signal_health_set test api fail
signal_health_set test api ok unexpected-message
signal_health_set --unknown api fail message
signal_health_ack test api --unknown
signal_health_clear test api --unknown
signal_health_show test --all
signal_health_show test api -t @1
signal_problem_show test --all
signal_problem_close test --pane
CASES

  run signal_health_show 'bad contributor'
  assert_failure
  assert_equal "$_FAKE_WRITES" "$writes"
}

@test "canonical leading signal options are accepted" {
  signal_status_set -t %1 result
  signal_health_set -t "$_FAKE_WIN" test api warn "slow response"
  run signal_health_show -t "$_FAKE_WIN" test api
  assert_output "$(printf 'warn\tslow response')"
}

@test "signal services propagate resolution, transaction, callback, and reporting failures" {
  resolve_window () { return 9; }
  run signal_status_set -t missing active
  assert_failure 2
  assert_output --partial "cannot resolve window for pane 'missing'"

  resolve_window () { printf '%s' "$1"; }
  with_window_transaction () { return 7; }
  run signal_health_clear test api
  assert_failure 7

  with_window_transaction () { local callback="$3"; shift 3; "$callback" "$@"; }
  _signal_status_set_unlocked () { return 6; }
  run signal_status_set active
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
  signal_status_set active
  signal_health_set test context warn "context pressure"
  assert_equal "$_FAKE_REDRAWS" 2
  local writes="$_FAKE_WRITES"

  signal_status_set active
  signal_health_set test context warn "context pressure"
  assert_equal "$_FAKE_REDRAWS" 2
  assert_equal "$_FAKE_WRITES" "$writes"

  signal_status_clear -t %9
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
