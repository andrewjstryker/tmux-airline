#!/usr/bin/env bats

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  source "$PROJECT_ROOT/lib/command.sh"
  source "$PROJECT_ROOT/lib/transaction.sh"
}

@test "show rejects arguments and otherwise lists transactions" {
  transaction_list () { printf 'session\ts1\tproblem\tstale\n'; }
  run transaction_show unexpected
  assert_failure
  assert_output --partial "takes no arguments"

  run transaction_show
  assert_success
  assert_output $'session\ts1\tproblem\tstale'
}

@test "clear validates its tuple before reaching transaction mechanics" {
  run transaction_clear_stale session s1
  assert_failure
  assert_output --partial "need <global|session|window> <target> <namespace>"
}

@test "clear translates mechanical recovery outcomes" {
  transaction_clear () { return 3; }
  run transaction_clear_stale session s1 problem
  assert_failure
  assert_output --partial "no such outstanding transaction"

  transaction_clear () { return 4; }
  run transaction_clear_stale session s1 problem
  assert_failure
  assert_output --partial "owner is still active"
}
