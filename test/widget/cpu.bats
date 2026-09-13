#!/usr/bin/env bats
load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load
setup() {
  export AIRLINE_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export AIRLINE_WIDGET_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export AIRLINE_CPU_STAT="$BATS_TEST_TMPDIR/stat"
  mkdir "$AIRLINE_WIDGET_STATE_DIR"
  source "$AIRLINE_DIR/layouts/widgets/cpu"
}
@test "CPU counters establish a baseline then measure utilization without guest double counting" {
  echo 'cpu 100 0 100 800 0 0 0 0 99 99' > "$AIRLINE_CPU_STAT"
  run airline_widget_sample
  assert_success; assert_output '?'
  echo 'cpu 150 0 125 825 0 0 0 0 999 999' > "$AIRLINE_CPU_STAT"
  run airline_widget_sample
  assert_success; assert_output 75
}
@test "CPU resets and malformed counters cannot produce invented utilization" {
  echo 'cpu 100 0 100 800 0 0 0 0' > "$AIRLINE_CPU_STAT"
  airline_widget_sample
  run airline_widget_sample
  assert_output '?'
  echo 'cpu 1 0 1 8 0 0 0 0' > "$AIRLINE_CPU_STAT"
  run airline_widget_sample
  assert_output '?'
  echo 'cpu bad' > "$AIRLINE_CPU_STAT"
  run airline_widget_sample
  assert_failure
}
@test "CPU argument policy rejects invalid or reversed thresholds" {
  run _cpu_options --warn 95 --critical 70
  assert_failure
  run _cpu_options --warn bad
  assert_failure
  run _cpu_options --critical 101
  assert_failure
}
