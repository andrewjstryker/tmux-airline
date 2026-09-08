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
  assert_output --partial 'filter       tap'
  assert_output --partial 'probe        none'

  run main runner describe http
  assert_success
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
  local report="$2"; shift 2
  [[ $# == 2 && "$1" == 'three four' && "$2" == '' ]] || return 1
  local line
  read -r line
  [[ "$line" == 'child output' ]] || return 1
  "$report" ok
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
