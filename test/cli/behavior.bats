#!/usr/bin/env bats

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load
load ../support/helper

# Exercise the public grammar over the in-memory tmux boundary. Unlike
# grammar.bats, these tests retain the real behavior handlers behind dispatch.
setup() {
  export AIRLINE_DIR="$PROJECT_ROOT"
  source "$PROJECT_ROOT/airline.sh"
  source "$PROJECT_ROOT/test/support/fake-tmux.sh"
}

@test "fixed-arity commands reject trailing operands" {
  local argv
  while IFS= read -r argv; do
    run main $argv
    assert_failure
  done <<'CASES'
session apply extra
session suspend extra
session resume extra
session toggle extra
palette describe dark extra
palette show name extra
palette list extra
segment show left-out extra
adapter load /tmp/adapter extra
adapter describe cpu extra
adapter show extra
adapter list extra
layout describe full extra
layout show name extra
layout list extra
classifier describe basic extra
classifier list extra
filter describe tap extra
filter list extra
probe describe http extra
probe list extra
runner list extra
CASES
}

@test "runner catalogs reject show and require bare names for describe" {
  local noun
  for noun in classifier filter probe runner; do
    run main "$noun" show sample
    assert_failure
    assert_output --partial "unknown $noun command: show"

    run main "$noun" describe
    assert_failure
    assert_output --partial "$noun describe: need"

    run main "$noun" describe /tmp/sample
    assert_failure
    assert_output --partial "$noun describe: need a bare name"

    run main "$noun" describe nonexistent
    assert_failure
    assert_output --partial "$noun describe: 'nonexistent' not found"
  done
}

@test "element describe reads registered metadata without executing the element" {
  local noun
  mkdir -p "$BATS_TEST_TMPDIR/catalog"
  printf '%s\n' '#| summary: Inspection fixture' '#| usage: <target>' \
    '#| interval: 7' 'exit 99' > "$BATS_TEST_TMPDIR/catalog/sample"
  for noun in palette adapter layout classifier filter probe; do
    main "$noun" register "$BATS_TEST_TMPDIR/catalog"
    run main "$noun" describe sample
    assert_success
    assert_output --partial 'Inspection fixture'
    assert_output --partial "$BATS_TEST_TMPDIR/catalog/sample"
    if [[ "$noun" == probe ]]; then
      assert_output --partial '<target>'
      assert_output --partial '7 seconds'
    fi
  done
}

@test "element describe rejects invalid metadata" {
  printf '%s\n' '#| summary: first' '#| summary: duplicate' > "$BATS_TEST_TMPDIR/invalid"
  main classifier register "$BATS_TEST_TMPDIR"
  run main classifier describe invalid
  assert_failure
  assert_output --partial "classifier describe: 'invalid' has invalid metadata"
}

@test "runner describe resolves defaults and preserves argument boundaries" {
  main runner register "$PROJECT_ROOT/runners/definitions"
  run main runner describe tap
  assert_success
  assert_line 'modes        run'
  assert_output --partial 'filter       tap'
  assert_output --partial 'probe        none'

  run main runner describe http
  assert_success
  assert_line 'modes        run watch'
  assert_output --partial 'classifier   basic'
  assert_output --partial 'probe        http'
  assert_output --partial 'http://localhost/health/live'

  mkdir -p "$BATS_TEST_TMPDIR/catalog"
  cat > "$BATS_TEST_TMPDIR/catalog/custom" <<'RUNNER'
#| summary: Argument fixture
#| usage: <first> <second>
airline_runner_configure() {
  local configure="$1"; shift
  [[ $# == 2 && "$1" == 'one two' && "$2" == '--opaque' ]] || return 2
  "$configure" probe http "$@"
}
RUNNER
  main runner register "$BATS_TEST_TMPDIR/catalog"
  run main runner describe custom 'one two' --opaque
  assert_success
  assert_output --partial 'one\ two --opaque'

  run main runner describe custom incomplete
  assert_failure
  assert_output --partial "runner describe: 'custom' produced an invalid configuration"
}

@test "runner describe derives modes from the composition evaluated with its arguments" {
  mkdir -p "$BATS_TEST_TMPDIR/catalog"
  cat > "$BATS_TEST_TMPDIR/catalog/conditional" <<'RUNNER'
#| summary: Conditional probe fixture
#| usage: <command|observe>
airline_runner_configure() {
  local configure="$1"; shift
  case "$1" in
    command) "$configure" classify basic ;;
    observe) "$configure" probe http http://localhost/health ;;
    *) return 2 ;;
  esac
}
RUNNER
  main runner register "$BATS_TEST_TMPDIR/catalog"

  # Reevaluate in the same shell so a prior probe cannot leak into later modes.
  main runner describe conditional observe > "$BATS_TEST_TMPDIR/observe"
  main runner describe conditional command > "$BATS_TEST_TMPDIR/command"
  run cat "$BATS_TEST_TMPDIR/observe"
  assert_success
  assert_line 'modes        run watch'
  run cat "$BATS_TEST_TMPDIR/command"
  assert_success
  assert_line 'modes        run'

  run main runner describe conditional invalid
  assert_failure
  refute_output --partial 'modes '
}

@test "layout catalogs require a bare description name and segment has no catalog" {
  local noun
  for noun in palette adapter layout; do
    run main "$noun" describe
    assert_failure
    assert_output --partial "$noun describe: need"
    run main "$noun" describe /tmp/sample
    assert_failure
    assert_output --partial "$noun describe: need a bare name"
    run main "$noun" describe nonexistent
    assert_failure
    assert_output --partial "$noun describe: 'nonexistent' not found"
  done
  run main segment describe sample
  assert_failure
  assert_output --partial 'unknown segment command: describe'
}

@test "catalog inspection preserves active configuration and performs no writes" {
  main palette register "$PROJECT_ROOT/layouts/palettes"
  main adapter register "$PROJECT_ROOT/layouts/adapters"
  main layout register "$PROJECT_ROOT/layouts/definitions"
  prv_set_session s1 palette light
  prv_set_session s1 layout minimal
  local before="$_FAKE_WRITES"
  main palette describe dark >/dev/null
  main adapter describe cpu >/dev/null
  main layout describe full >/dev/null
  assert_equal "$_FAKE_WRITES" "$before"
  assert_equal "$(prv_get_session s1 palette)" light
  assert_equal "$(prv_get_session s1 layout)" minimal
}

@test "runner run delivers configured arguments through execution and describe" {
  cat > "$BATS_TEST_TMPDIR/custom" <<'ELEMENT'
#| summary: Argument-aware elements
#| usage: <value>
airline_runner_classify() {
  [[ $# == 4 && "$1" == 0 && "$2" == '' && "$3" == 'one two' && "$4" == '' ]] || return 1
  printf 'warn\tconfigured classification\n'
}
airline_runner_filter() {
  local report="$2"; shift 3
  [[ $# == 2 && "$1" == 'three four' && "$2" == '' ]] || return 1
  local line
  read -r line
  [[ "$line" == 'child output' ]] || return 1
  "$report" test-elements output ok
}
airline_runner_configure() {
  "$1" classify custom 'one two' ''
  "$1" filter custom 'three four' '' --merge-stderr
}
ELEMENT
  local kind
  for kind in classifier filter runner; do
    main "$kind" register "$BATS_TEST_TMPDIR"
  done
  run main runner describe custom
  assert_success
  assert_output --partial "classifier-args one\\ two ''"
  assert_output --partial "filter-args  three\\ four ''"

  main runner run custom -- printf 'child output\n' >/dev/null
  run main health show airline-runner-classifier-custom command
  assert_success
  assert_output --partial 'configured classification'
  run main problem show airline-runner-classifier-custom classify
  assert_success
  assert_output ''
  run main problem show airline-runner-filter-custom filter
  assert_success
  assert_output ''
}

@test "element usage failures precede commands, topology, and signal mutations" {
  main classifier register "$PROJECT_ROOT/runners/classifiers"
  cat > "$BATS_TEST_TMPDIR/validated" <<'ELEMENT'
#| summary: Validated elements
#| usage: --value <value>
_fixture_parse() {
  # options:begin
  case "${1:-}" in
    --value|-v) [[ $# == 2 ]] && return 0 ;; #| <value> — choose a value
  esac
  # options:end
  printf 'expected --value and one value; received %s\n' "${1:-nothing}" >&2
  return 3
}
airline_runner_classify() { printf 'ok\n'; }
airline_runner_filter() { "$2" test-elements output ok; }
airline_runner_probe() { "$2" test-elements probe ok; }
airline_runner_classify_parse() { _fixture_parse "$@"; }
airline_runner_filter_parse() { _fixture_parse "$@"; }
airline_runner_probe_parse() { _fixture_parse "$@"; }
airline_runner_configure() { "$1" probe validated "${@:2}"; }
ELEMENT
  local kind effects="$BATS_TEST_TMPDIR/effects"
  for kind in classifier filter probe runner; do
    main "$kind" register "$BATS_TEST_TMPDIR"
  done
  signal_status_set() { touch "$effects"; }
  signal_health_set() { touch "$effects"; }
  signal_problem_report() { touch "$effects"; }
  runner_open_pane() { touch "$effects"; }
  runner_open_window() { touch "$effects"; }

  for kind in classify filter probe; do
    run main runner run "--$kind" validated --typo -- touch "$effects"
    assert_failure 2
    assert_output --partial 'expected --value and one value; received --typo'
    [[ ! -e "$effects" ]]
    run main runner run --pane "--$kind" validated --value -- true
    assert_failure 2
    assert_output --partial 'expected --value and one value'
    [[ ! -e "$effects" ]]
  done
  run main runner watch validated --typo
  assert_failure 2
  assert_output --partial 'expected --value and one value; received --typo'
  [[ ! -e "$effects" ]]
  run main runner watch --window --probe validated --typo
  assert_failure 2
  [[ ! -e "$effects" ]]

  # Discovery reads options without calling the parser (which would reject no argv).
  for kind in classifier filter probe; do
    run main "$kind" describe validated
    assert_success
    assert_output --partial '--value|-v <value> — choose a value'
  done
}

@test "successful parsing preserves execution argv and hides validation output" {
  cat > "$BATS_TEST_TMPDIR/parsed" <<'ELEMENT'
#| summary: Parsed classifier
#| usage: --value <value>
airline_runner_classify_parse() {
  printf 'private validation output\n'
  [[ $# == 2 && "$1" == --value && "$2" == 'one two' ]]
}
airline_runner_classify() {
  [[ $# == 4 && "$3" == --value && "$4" == 'one two' ]] || return 1
  printf 'warn\tparsed arguments arrived\n'
}
ELEMENT
  main classifier register "$BATS_TEST_TMPDIR"
  main runner run --classify parsed --value 'one two' -- printf 'child output' > "$BATS_TEST_TMPDIR/output"
  run cat "$BATS_TEST_TMPDIR/output"
  assert_output 'child output'
  run main health show airline-runner-classifier-parsed command
  assert_success
  assert_output $'warn\tparsed arguments arrived'
}

@test "reporting functions and CLI mutations produce identical signal state" {
  AIRLINE_RUNNER_PANE='%1'
  local snapshot
  main health set -t %1 external endpoint fail 'unhealthy endpoint'
  main problem set --pane %1 external capability fail 'cannot observe'
  snapshot="$(declare -p _FAKE_OPT)"
  _FAKE_OPT=()
  _runner_health_report external endpoint fail 'unhealthy endpoint'
  _runner_problem_report external capability fail 'cannot observe'
  assert_equal "$(declare -p _FAKE_OPT)" "$snapshot"

  # Health recovery must not recover a separate capability claim.
  _runner_health_report external endpoint ok
  run main problem show external capability
  assert_output --partial 'cannot observe'
  _runner_problem_report external capability ok
  run main problem show external capability
  assert_output ''
}

@test "invalid reports return without exiting the host or mutating state" {
  AIRLINE_RUNNER_PANE='%1'
  local reporter rc before="$_FAKE_WRITES"
  for reporter in _runner_health_report _runner_problem_report; do
    rc=0
    "$reporter" 'invalid contributor' key fail message 2>/dev/null || rc=$?
    assert_equal "$rc" 2
    rc=0
    "$reporter" author key ok unexpected-message 2>/dev/null || rc=$?
    assert_equal "$rc" 2
    rc=0
    "$reporter" 2>/dev/null || rc=$?
    assert_equal "$rc" 2
  done
  assert_equal "$_FAKE_WRITES" "$before"
}

@test "runner startup completion and silent observations leave element claims intact" {
  main classifier register "$PROJECT_ROOT/runners/classifiers"
  cat > "$BATS_TEST_TMPDIR/silent" <<'ELEMENT'
#| summary: Silent observer
#| usage:
airline_runner_filter() { cat >/dev/null; }
airline_runner_probe() { :; }
ELEMENT
  main filter register "$BATS_TEST_TMPDIR"
  main probe register "$BATS_TEST_TMPDIR"
  main health set author endpoint fail 'previous observation'
  main problem set --pane %1 author prerequisite fail 'not recovered'
  main runner run --filter silent --probe silent -- printf 'input\n' >/dev/null
  run main health show author endpoint
  assert_output $'fail\tprevious observation'
  run main problem show author prerequisite
  assert_output --partial 'not recovered'
  run main problem show airline-runner
  assert_output ''
}
