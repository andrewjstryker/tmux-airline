#!/usr/bin/env bats

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load
load ../support/helper

setup() {
  load_render
  source "$PROJECT_ROOT/lib/catalog.sh"
  source "$PROJECT_ROOT/lib/signal.sh"
  source "$PROJECT_ROOT/lib/runner.sh"
}

@test "basic classifier interprets successful and failed termination" {
  runner_classifier_load "$PROJECT_ROOT/runners/classifiers/basic"
  run runner_classifier_run 0 ""
  assert_output ok
  run runner_classifier_run 7 ""
  assert_output "$(printf 'fail\tcommand exited with status 7')"
  run runner_classifier_run 143 15
  assert_output "$(printf 'fail\tcommand terminated by signal 15 (status 143)')"
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

@test "named runners declare metadata in the header and validate their builder" {
  printf '%s\n' \
    '#| summary: test composition' \
    '#| usage:' \
    'airline_runner_configure() {' \
    '  "$1" classify basic' \
    '  "$1" filter tap' \
    '}' > "$BATS_TEST_TMPDIR/runner"
  run _runner_metadata_require runner "$BATS_TEST_TMPDIR/runner"
  assert_success
  runner_definition_load "$BATS_TEST_TMPDIR/runner"
  run runner_definition_configure
  assert_success

  sed -i 's/"$1" filter tap/"$1" placement pane/' "$BATS_TEST_TMPDIR/runner"
  runner_definition_load "$BATS_TEST_TMPDIR/runner"
  run runner_definition_configure
  assert_failure

  # A summary is required; a usage line must be declared even when it is empty.
  printf '%s\n' '#| usage:' 'airline_runner_configure() { :; }' > "$BATS_TEST_TMPDIR/no-summary"
  run _runner_metadata_require runner "$BATS_TEST_TMPDIR/no-summary"
  assert_failure
  printf '%s\n' '#| summary: no usage' 'airline_runner_configure() { :; }' > "$BATS_TEST_TMPDIR/no-usage"
  run _runner_metadata_require runner "$BATS_TEST_TMPDIR/no-usage"
  assert_failure
}

@test "watch projects only the probe from a complete runner" {
  airline_runner_configure() {
    "$1" classify basic
    "$1" filter tap --merge-stderr
    "$1" probe http one two
  }
  runner_definition_configure

  runner_definition_project run
  run printf '%s\n' "${AIRLINE_RUNNER_DEFINITION_ARGV[@]}"
  assert_output $'--classify\nbasic\n--filter\ntap\n--merge-stderr\n--probe\nhttp\none\ntwo'

  runner_definition_project watch
  run printf '%s\n' "${AIRLINE_RUNNER_DEFINITION_ARGV[@]}"
  assert_output $'--probe\nhttp\none\ntwo'
}

@test "pane placement accepts tmux orientation modifiers" {
  _runner_parse run --pane -h -- true
  assert_equal "$AIRLINE_RUNNER_PLACEMENT" pane
  assert_equal "$AIRLINE_RUNNER_PANE_ORIENTATION" -h

  _runner_parse run --pane -v -- true
  assert_equal "$AIRLINE_RUNNER_PLACEMENT" pane
  assert_equal "$AIRLINE_RUNNER_PANE_ORIENTATION" -v

  _runner_parse run --pane -- true
  assert_equal "$AIRLINE_RUNNER_PLACEMENT" pane
  assert_equal "$AIRLINE_RUNNER_PANE_ORIENTATION" ""

  run _runner_parse run --pane --window -- true
  assert_failure
  assert_output --partial "placement already specified"

  run _runner_parse watch --window --pane --probe visible
  assert_failure
  assert_output --partial "placement already specified"

  _runner_parse run --probe visible endpoint --filter tap -- true
  assert_equal "${AIRLINE_RUNNER_PROBE_ARGS[*]}" endpoint
  assert_equal "$AIRLINE_RUNNER_FILTER" tap
}

@test "spawned placements re-enter public runner commands with normalized argv" {
  evidence="$BATS_TEST_TMPDIR/spawn"
  _runner_expand_named() { AIRLINE_RUNNER_INVOCATION_ARGV=("$3"); }
  _runner_parse() {
    AIRLINE_RUNNER_PLACEMENT=pane
    AIRLINE_RUNNER_PANE_ORIENTATION=-h
  }
  _runner_validate_spec() { :; }
  _runner_normalize_spec() {
    AIRLINE_RUNNER_SPEC_ARGV=(--probe visible endpoint)
    [[ "$1" != run ]] || AIRLINE_RUNNER_SPEC_ARGV+=(-- true)
  }
  runner_open_pane() {
    printf '<%s>' "$@" > "$evidence"
    printf '%%2'
  }
  runner_retain_pane() { printf '<retain:%s>' "$1" >> "$evidence"; }

  local mode
  for mode in run watch; do
    _runner_invoke s1 "$mode" --pane >/dev/null
    run cat "$evidence"
    assert_output --partial '<env><AIRLINE_RUNNER_SPAWNED=1>'
    assert_output --partial "<${PROJECT_ROOT}/airline.sh><runner><$mode><--probe>"
    assert_output --partial '<--probe><visible><endpoint>'
    assert_output --partial '<retain:%2>'
  done
}

@test "public runner consumes spawn context and retains before invocation" {
  _RUNNER_EVENTS=""
  current_pane() { printf '%%7'; }
  runner_retain_pane() { _RUNNER_EVENTS+="retain:$1 "; }
  _runner_exit_guard_start() { _RUNNER_EVENTS+=" guard:$1"; }
  command_current_session() { printf s1; }
  _runner_invoke() {
    [[ ! -v AIRLINE_RUNNER_SPAWNED ]] || return 9
    _RUNNER_EVENTS+="invoke:$2"
  }

  AIRLINE_RUNNER_SPAWNED=1
  runner_run -- true
  assert_regex "$_RUNNER_EVENTS" '^retain:%7 invoke:run guard:[0-9]+$'
  [[ ! -v AIRLINE_RUNNER_SPAWNED ]]

  _RUNNER_EVENTS=""
  runner_watch --probe visible
  assert_equal "$_RUNNER_EVENTS" "invoke:watch"
}

@test "probe interval must be positive seconds" {
  printf '%s\n' \
    '#| summary: test probe' \
    '#| usage:' \
    '#| interval: 0' \
    'airline_runner_probe() { "$2" ok; }' > "$BATS_TEST_TMPDIR/probe"
  run runner_probe_valid "$BATS_TEST_TMPDIR/probe"
  assert_failure
  sed -i 's/interval: 0/interval: 0.05/' "$BATS_TEST_TMPDIR/probe"
  run runner_probe_valid "$BATS_TEST_TMPDIR/probe"
  assert_success

  # An undeclared interval falls back to the shipped default rather than failing.
  printf '%s\n' '#| summary: test probe' '#| usage:' \
    'airline_runner_probe() { "$2" ok; }' > "$BATS_TEST_TMPDIR/default-interval"
  run runner_probe_valid "$BATS_TEST_TMPDIR/default-interval"
  assert_success
  run _runner_probe_interval "$BATS_TEST_TMPDIR/default-interval"
  assert_output 5
}

@test "classifier output must be one normalized condition" {
  printf '%s\n' '#| summary: invalid test classifier' \
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
  report_state() { printf '%s\n' "$*" >> "$output_file"; }
  airline_runner_filter() {
    local pid="$1" report="$2"
    "$report" warn "filter degraded"
    printf '%s\n' "$pid" >> "$output_file"
    sed -n '1p' >> "$output_file"
  }

  runner_filter_start 4321 report_state "$input_file"
  wait "$AIRLINE_RUNNER_FILTER_PID"
  run cat "$output_file"
  assert_output $'warn filter degraded\n4321\nserver evidence'
}

@test "filter must emit at least one condition report" {
  input_file="$BATS_TEST_TMPDIR/filter-input"
  : > "$input_file"
  airline_runner_filter() { :; }

  runner_filter_start 4321 report_state "$input_file"
  run runner_filter_wait "$AIRLINE_RUNNER_FILTER_PID"
  assert_failure
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
    else : > "$state_file"; "$report" fail "probe unavailable"; fi
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
    "$report" fail "primary failed"
    "$report" fail "secondary also failed"
    "$report" warn "secondary degraded"
  }
  transcript="$BATS_TEST_TMPDIR/probe-transcript"
  runner_probe_once 4321 > "$transcript"
  assert_equal "$AIRLINE_RUNNER_PROBE_CONDITION" fail
  assert_equal "$AIRLINE_RUNNER_PROBE_MESSAGE" "primary failed"
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
  report_state() { printf '%s\n' "$*" >> "$reports_file"; }
  curl() {
    local url="${*: -1}"
    if [[ "$url" == *unhealthy* ]]; then printf 503; else printf 204; fi
  }
  runner_probe_load "$PROJECT_ROOT/runners/probes/http"
  run airline_runner_probe 4321 report_state \
    http://service/one http://service/unhealthy http://service/two
  assert_output $'ok 204 http://service/one\nfail 503 http://service/unhealthy\nok 204 http://service/two'
  run cat "$reports_file"
  assert_output $'ok\nfail HTTP 503 from http://service/unhealthy\nok'

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
  report_state() { printf '%s\n' "$*" >> "$output_file"; }
  runner_filter_load "$PROJECT_ROOT/runners/filters/tap"

  airline_runner_filter 4321 report_state <<'TAP'
TAP version 13
1..3
ok 1 - first
not ok 2 - second
ok 3 - third
TAP
  run cat "$output_file"
  assert_output $'warn TAP assertion failed: not ok 2 - second\nfail TAP stream completed with unsuccessful assertions'
}

@test "tap filter ignores TODO failures and fails immediately on bailout" {
  output_file="$BATS_TEST_TMPDIR/tap-output"
  export output_file
  report_state() { printf '%s\n' "$*" >> "$output_file"; }
  runner_filter_load "$PROJECT_ROOT/runners/filters/tap"

  airline_runner_filter 4321 report_state <<'TAP'
1..2
not ok 1 - later # TODO not implemented
ok 2 - done
Bail out! infrastructure disappeared
TAP
  run cat "$output_file"
  assert_output "fail TAP bailout: Bail out! infrastructure disappeared"
}

@test "tap filter reports ok after a clean stream" {
  output_file="$BATS_TEST_TMPDIR/tap-output"
  export output_file
  report_state() { printf '%s\n' "$*" >> "$output_file"; }
  runner_filter_load "$PROJECT_ROOT/runners/filters/tap"

  airline_runner_filter 4321 report_state <<'TAP'
1..2
ok 1 - first
not ok 2 - later # TODO not implemented
TAP
  run cat "$output_file"
  assert_output ok
}

@test "a named composition may pace its probe and projects the interval down" {
  airline_runner_configure() {
    "$1" classify basic
    "$1" probe http one
    "$1" interval 30
  }
  runner_definition_configure
  runner_definition_project watch
  run printf '%s\n' "${AIRLINE_RUNNER_DEFINITION_ARGV[@]}"
  assert_output $'--interval\n30\n--probe\nhttp\none'
}

@test "a paced composition requires a probe and a positive interval" {
  # An interval with no probe paces nothing; that is a mistake, not a no-op.
  airline_runner_configure() { "$1" classify basic; "$1" interval 30; }
  run runner_definition_configure
  assert_failure

  airline_runner_configure() { "$1" probe http; "$1" interval 0; }
  run runner_definition_configure
  assert_failure

  airline_runner_configure() { "$1" probe http; "$1" interval 30; "$1" interval 60; }
  run runner_definition_configure
  assert_failure
}

@test "an invocation interval overrides the probe's declared default" {
  printf '%s\n' '#| summary: test probe' '#| usage:' '#| interval: 5' \
    'airline_runner_probe() { "$2" ok; }' > "$BATS_TEST_TMPDIR/paced"

  # The element default applies when the invocation is silent.
  AIRLINE_RUNNER_INTERVAL=""
  runner_probe_load "$BATS_TEST_TMPDIR/paced"
  run _runner_effective_interval
  assert_output 5

  # An explicit interval wins, whether typed or projected from a named runner.
  AIRLINE_RUNNER_INTERVAL=30
  run _runner_effective_interval
  assert_output 30
  AIRLINE_RUNNER_INTERVAL=""
}

@test "interval parsing validates its value, placement, and repetition" {
  # Called directly: `run` would set the parsed globals in a subshell.
  _runner_parse watch --interval 30 --probe http
  assert_equal "$AIRLINE_RUNNER_INTERVAL" 30

  # Normalization re-emits it ahead of the probe, whose arguments run to the end.
  _runner_parse watch --interval 30 --probe http one two
  _runner_normalize_spec watch
  run printf '%s\n' "${AIRLINE_RUNNER_SPEC_ARGV[@]}"
  assert_output $'--interval\n30\n--probe\nhttp\none\ntwo'

  run _runner_parse watch --interval 0 --probe http
  assert_failure
  run _runner_parse watch --interval --probe http
  assert_failure
  run _runner_parse watch --interval 30 --interval 60 --probe http
  assert_failure
  # An interval paces probe observations, so `run` without a probe rejects it.
  run _runner_parse run --interval 30 -- true
  assert_failure
  assert_output --partial "paces --probe"
}

@test "every element keeps opaque arguments up to the next reserved token" {
  _runner_parse run --probe remote 'https://example/a b' --interval 2 \
    --classify custom --policy 'one two' '' '*' \
    --filter capture --format json merge-stderr --merge-stderr -- printf '%s' --probe
  assert_equal "${AIRLINE_RUNNER_PROBE_ARGS[*]}" 'https://example/a b'
  assert_equal "$AIRLINE_RUNNER_INTERVAL" 2
  run printf '<%s>' "${AIRLINE_RUNNER_CLASSIFIER_ARGS[@]}"
  assert_output '<--policy><one two><><*>'
  run printf '<%s>' "${AIRLINE_RUNNER_FILTER_ARGS[@]}"
  assert_output '<--format><json><merge-stderr>'
  assert_equal "$AIRLINE_RUNNER_FILTER_MERGE" 1
  run printf '<%s>' "${AIRLINE_RUNNER_COMMAND[@]}"
  assert_output '<printf><%s><--probe>'

  _runner_normalize_spec run
  local -a normalized=("${AIRLINE_RUNNER_SPEC_ARGV[@]}")
  _runner_parse run "${normalized[@]}"
  _runner_normalize_spec run
  assert_equal "$(printf '<%s>' "${AIRLINE_RUNNER_SPEC_ARGV[@]}")" "$(printf '<%s>' "${normalized[@]}")"

  _runner_parse run -- true
  assert_equal "${#AIRLINE_RUNNER_CLASSIFIER_ARGS[@]}" 0
  assert_equal "${#AIRLINE_RUNNER_FILTER_ARGS[@]}" 0
  assert_equal "$AIRLINE_RUNNER_FILTER_MERGE" ''
}

@test "merge stderr is independent of option order and requires a filter" {
  local -a spec=(--classify basic --filter tap --probe http endpoint)
  local index
  for index in 0 2 4 7; do
    _runner_parse run "${spec[@]:0:index}" --merge-stderr "${spec[@]:index}" -- true
    assert_equal "$AIRLINE_RUNNER_FILTER_MERGE" 1
    assert_equal "${AIRLINE_RUNNER_PROBE_ARGS[*]}" endpoint
  done
  run _runner_parse run --merge-stderr -- true
  assert_failure
  assert_output --partial '--merge-stderr requires --filter'
  run _runner_parse watch --probe http endpoint --merge-stderr
  assert_failure
  assert_output --partial '--merge-stderr requires --filter'
  run _runner_parse run --filter tap --merge-stderr --merge-stderr -- true
  assert_failure
  assert_output --partial '--merge-stderr already specified'
}

@test "reserved tokens cannot replace names or hide duplicate element selections" {
  local option
  for option in --classify --filter --probe; do
    run _runner_parse run "$option" --merge-stderr -- true
    assert_failure
    assert_output --partial "$option requires <name>"
    run _runner_parse run "$option" custom arg "$option" other -- true
    assert_failure
    assert_output --partial 'already specified'
  done
  run _runner_parse watch --probe http endpoint --filter tap arg
  assert_failure
  assert_output --partial '--filter is not applicable'
}

@test "named and explicit compositions normalize to the same element arguments" {
  airline_runner_configure() {
    "$1" classify custom --policy 'one two' '' '*'
    "$1" filter capture --format json --merge-stderr merge-stderr
    "$1" probe remote endpoint
    "$1" interval 2
  }
  runner_definition_configure
  runner_definition_project run
  _runner_parse run "${AIRLINE_RUNNER_DEFINITION_ARGV[@]}" -- true
  _runner_normalize_spec run
  local named
  named="$(printf '<%s>' "${AIRLINE_RUNNER_SPEC_ARGV[@]}")"
  _runner_parse run --merge-stderr --probe remote endpoint --interval 2 \
    --filter capture --format json merge-stderr --classify custom --policy 'one two' '' '*' -- true
  _runner_normalize_spec run
  assert_equal "$(printf '<%s>' "${AIRLINE_RUNNER_SPEC_ARGV[@]}")" "$named"

  runner_definition_project watch
  _runner_parse watch "${AIRLINE_RUNNER_DEFINITION_ARGV[@]}"
  assert_equal "${AIRLINE_RUNNER_PROBE_ARGS[*]}" endpoint
  assert_equal "$AIRLINE_RUNNER_FILTER_MERGE" ''
  assert_equal "${#AIRLINE_RUNNER_CLASSIFIER_ARGS[@]}" 0

  airline_runner_configure() { "$1" classify basic; }
  runner_definition_configure
  assert_equal "${#AIRLINE_RUNNER_CONFIG_CLASSIFIER_ARGS[@]}" 0
  assert_equal "${#AIRLINE_RUNNER_CONFIG_FILTER_ARGS[@]}" 0
  assert_equal "$AIRLINE_RUNNER_CONFIG_FILTER_MERGE" ''
}

@test "configure rejects reserved argument tokens before they can change the projected grammar" {
  local kind token
  for kind in classify filter probe; do
    for token in --pane --window --classify --filter --probe --interval --; do
      airline_runner_configure() { "$1" "$kind" custom "$token"; }
      run runner_definition_configure
      assert_failure
    done
  done
  airline_runner_configure() { "$1" filter custom --merge-stderr --merge-stderr; }
  run runner_definition_configure
  assert_failure
  airline_runner_configure() { "$1" classify custom --merge-stderr; }
  run runner_definition_configure
  assert_failure
}

@test "classifier and background filter receive arguments intact after core parameters" {
  airline_runner_classify() {
    [[ $# == 6 && "$1" == 7 && "$2" == '' && "$3" == '--policy' && "$4" == 'one two' && "$5" == '' && "$6" == '*' ]] || return 1
    printf 'warn\tconfigured classification\n'
  }
  run runner_classifier_run 7 '' --policy 'one two' '' '*'
  assert_success
  assert_output $'warn\tconfigured classification'

  local evidence="$BATS_TEST_TMPDIR/args" input="$BATS_TEST_TMPDIR/input"
  printf 'stream evidence\n' > "$input"
  report_state() { printf '%s\n' "$*" >> "$evidence"; }
  airline_runner_filter() {
    local pid="$1" report="$2"; shift 2
    [[ "$pid" == 4321 && $# == 4 && "$1" == '--format' && "$2" == 'one two' && "$3" == '' && "$4" == '*' ]] || return 1
    cat >> "$evidence"
    "$report" ok
  }
  runner_filter_start 4321 report_state "$input" --format 'one two' '' '*'
  runner_filter_wait "$AIRLINE_RUNNER_FILTER_PID"
  run cat "$evidence"
  assert_output $'stream evidence\nok'
}
