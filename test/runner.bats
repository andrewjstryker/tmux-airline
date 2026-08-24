#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load
load helper

setup() {
  load_render
  source "$PROJECT_ROOT/runner.sh"
}

@test "basic runner classifies successful and failed termination" {
  runner_impl_load "$PROJECT_ROOT/runners/basic"

  run runner_impl_classify 0 ""
  assert_success
  assert_output ok

  run runner_impl_classify 7 ""
  assert_success
  assert_output fail

  run runner_impl_classify 143 15
  assert_success
  assert_output fail
}

@test "runner contract requires a classifier" {
  printf 'unrelated() { :; }\n' > "$BATS_TEST_TMPDIR/missing"
  run runner_impl_valid "$BATS_TEST_TMPDIR/missing"
  assert_failure
}

@test "classifier output must be one normalized condition" {
  printf 'airline_runner_classify() { printf "maybe\\n"; }\n' > "$BATS_TEST_TMPDIR/invalid"
  runner_impl_load "$BATS_TEST_TMPDIR/invalid"
  run runner_impl_classify 0 ""
  assert_failure
}

@test "live filter receives the child pid, reporter, and command argv" {
  output_file="$BATS_TEST_TMPDIR/filter-output"
  export output_file
  report_state() { printf '%s\n' "$1" >> "$output_file"; }
  airline_runner_filter() {
    local pid="$1" report="$2"; shift 2
    "$report" warn
    printf '%s %s\n' "$pid" "$*" >> "$output_file"
  }

  runner_impl_filter_start 4321 report_state server --port 80
  wait "$AIRLINE_RUNNER_FILTER_PID"

  run sed -n '1p' "$output_file"
  assert_output warn
  run sed -n '2p' "$output_file"
  assert_output "4321 server --port 80"
}
