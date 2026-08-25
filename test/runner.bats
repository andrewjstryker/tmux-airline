#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load
load helper

setup() {
  load_render
  source "$PROJECT_ROOT/src/runner.sh"
}

@test "basic classifier interprets successful and failed termination" {
  runner_classifier_load "$PROJECT_ROOT/classifiers/basic"
  run runner_classifier_run 0 ""
  assert_output ok
  run runner_classifier_run 7 ""
  assert_output fail
  run runner_classifier_run 143 15
  assert_output fail
}

@test "each element loader requires its own function contract" {
  printf 'unrelated() { :; }\n' > "$BATS_TEST_TMPDIR/missing"
  run runner_classifier_valid "$BATS_TEST_TMPDIR/missing"
  assert_failure
  run runner_filter_valid "$BATS_TEST_TMPDIR/missing"
  assert_failure
  run runner_probe_valid "$BATS_TEST_TMPDIR/missing"
  assert_failure
}

@test "named runners require quiet metadata and a validated builder contract" {
  printf '%s\n' \
    'airline_runner_metadata() {' \
    '  "$1" summary "test composition"' \
    '  "$1" usage ""' \
    '}' \
    'airline_runner_configure() {' \
    '  "$1" classify basic' \
    '  "$1" filter tap' \
    '}' > "$BATS_TEST_TMPDIR/runner"
  run runner_definition_valid "$BATS_TEST_TMPDIR/runner"
  assert_success

  sed -i 's/"$1" filter tap/"$1" placement pane/' "$BATS_TEST_TMPDIR/runner"
  run runner_definition_valid "$BATS_TEST_TMPDIR/runner"
  assert_failure
}

@test "watch projects only the probe from a complete runner" {
  airline_runner_metadata() { "$1" summary "server"; "$1" usage ""; }
  airline_runner_configure() {
    "$1" classify basic
    "$1" filter tap merge-stderr
    "$1" probe http one two
  }
  runner_definition_metadata
  runner_definition_configure

  runner_definition_project run
  run printf '%s\n' "${AIRLINE_RUNNER_DEFINITION_ARGV[@]}"
  assert_output $'--classify\nbasic\n--filter\ntap\n--merge-stderr\n--probe\nhttp\none\ntwo'

  runner_definition_project watch
  run printf '%s\n' "${AIRLINE_RUNNER_DEFINITION_ARGV[@]}"
  assert_output $'--probe\nhttp\none\ntwo'
}

@test "probe interval must be positive seconds" {
  printf '%s\n' \
    'AIRLINE_PROBE_SUMMARY="test probe"' \
    'AIRLINE_PROBE_USAGE=""' \
    'AIRLINE_RUNNER_PROBE_INTERVAL=0' \
    'airline_runner_probe() { "$2" ok; }' > "$BATS_TEST_TMPDIR/probe"
  run runner_probe_valid "$BATS_TEST_TMPDIR/probe"
  assert_failure
  sed -i 's/INTERVAL=0/INTERVAL=0.05/' "$BATS_TEST_TMPDIR/probe"
  run runner_probe_valid "$BATS_TEST_TMPDIR/probe"
  assert_success
}

@test "classifier output must be one normalized condition" {
  printf '%s\n' 'AIRLINE_CLASSIFIER_SUMMARY="invalid test classifier"' \
    'airline_runner_classify() { printf "maybe\\n"; }' > "$BATS_TEST_TMPDIR/invalid"
  runner_classifier_load "$BATS_TEST_TMPDIR/invalid"
  run runner_classifier_run 0 ""
  assert_failure
}

@test "live filter receives copied input, child pid, and reporter" {
  output_file="$BATS_TEST_TMPDIR/filter-output"
  input_file="$BATS_TEST_TMPDIR/filter-input"
  printf 'server evidence\n' > "$input_file"
  export output_file
  report_state() { printf '%s\n' "$1" >> "$output_file"; }
  airline_runner_filter() {
    local pid="$1" report="$2"
    "$report" warn
    printf '%s\n' "$pid" >> "$output_file"
    sed -n '1p' >> "$output_file"
  }

  runner_filter_start 4321 report_state "$input_file"
  wait "$AIRLINE_RUNNER_FILTER_PID"
  run cat "$output_file"
  assert_output $'warn\n4321\nserver evidence'
}

@test "probe observations are sequential and repeat while the child lives" {
  output_file="$BATS_TEST_TMPDIR/probe-output"
  state_file="$BATS_TEST_TMPDIR/probe-state"
  export output_file state_file
  AIRLINE_RUNNER_PROBE_INTERVAL=0.05
  report_state() { printf '%s\n' "$1" >> "$output_file"; }
  report_error() { printf 'error\n' >> "$output_file"; }
  airline_runner_probe() {
    local report="$2"
    if [[ -e "$state_file" ]]; then "$report" ok
    else : > "$state_file"; "$report" fail; fi
  }

  sleep 0.18 &
  child_pid=$!
  runner_probe_start "$child_pid" report_state report_error
  wait "$child_pid"
  runner_probe_stop "$AIRLINE_RUNNER_PROBE_PID"
  run sed -n '1p' "$output_file"
  assert_output fail
  run grep -F ok "$output_file"
  assert_success
}

@test "probe core validates and reduces multiple reports" {
  airline_runner_probe() {
    local report="$2"
    printf 'uninterpreted probe output\n'
    "$report" ok
    "$report" fail
    "$report" warn
  }
  transcript="$BATS_TEST_TMPDIR/probe-transcript"
  runner_probe_once 4321 > "$transcript"
  assert_equal "$AIRLINE_RUNNER_PROBE_CONDITION" fail
  run cat "$transcript"
  assert_output "uninterpreted probe output"

  airline_runner_probe() { "$2" ok; "$2" maybe; }
  run runner_probe_once 4321
  assert_failure

  airline_runner_probe() { printf 'output without a report\n'; }
  run runner_probe_once 4321
  assert_failure
}

@test "http probe reports every endpoint and airline reduces the worst" {
  reports_file="$BATS_TEST_TMPDIR/http-reports"
  export reports_file
  report_state() { printf '%s\n' "$1" >> "$reports_file"; }
  curl() {
    local url="${*: -1}"
    if [[ "$url" == *unhealthy* ]]; then printf 503; else printf 204; fi
  }
  runner_probe_load "$PROJECT_ROOT/probes/http"
  run airline_runner_probe 4321 report_state \
    http://service/one http://service/unhealthy http://service/two
  assert_output $'ok 204 http://service/one\nfail 503 http://service/unhealthy\nok 204 http://service/two'
  run cat "$reports_file"
  assert_output $'ok\nfail\nok'

  transcript="$BATS_TEST_TMPDIR/http-transcript"
  runner_probe_once 4321 \
    http://service/one http://service/unhealthy http://service/two > "$transcript"
  assert_equal "$AIRLINE_RUNNER_PROBE_CONDITION" fail
  run cat "$transcript"
  assert_output --partial "fail 503 http://service/unhealthy"
  run runner_probe_once 4321
  assert_failure
}

@test "tap filter warns on a failed assertion and fails at completion" {
  output_file="$BATS_TEST_TMPDIR/tap-output"
  export output_file
  report_state() { printf '%s\n' "$1" >> "$output_file"; }
  runner_filter_load "$PROJECT_ROOT/filters/tap"

  airline_runner_filter 4321 report_state <<'TAP'
TAP version 13
1..3
ok 1 - first
not ok 2 - second
ok 3 - third
TAP
  run cat "$output_file"
  assert_output $'warn\nfail'
}

@test "tap filter ignores TODO failures and fails immediately on bailout" {
  output_file="$BATS_TEST_TMPDIR/tap-output"
  export output_file
  report_state() { printf '%s\n' "$1" >> "$output_file"; }
  runner_filter_load "$PROJECT_ROOT/filters/tap"

  airline_runner_filter 4321 report_state <<'TAP'
1..2
not ok 1 - later # TODO not implemented
ok 2 - done
Bail out! infrastructure disappeared
TAP
  run cat "$output_file"
  assert_output fail
}
