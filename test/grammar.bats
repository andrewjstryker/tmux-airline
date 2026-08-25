#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load

PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
  AIRLINE_DIR="$PROJECT_ROOT"
  # shellcheck source=../airline.sh
  source "$PROJECT_ROOT/airline.sh"

  _record_delegate() {
    printf '%s' "${FUNCNAME[1]}"
    (( $# == 0 )) || printf ' <%s>' "$@"
  }

  local fn
  for fn in \
    lifecycle_init lifecycle_apply lifecycle_show \
    lifecycle_state_suspend lifecycle_state_resume lifecycle_state_toggle lifecycle_state_show \
    lifecycle_status_set lifecycle_status_clear lifecycle_status_show \
    lifecycle_health_set lifecycle_health_clear lifecycle_health_show \
    lifecycle_problem_set lifecycle_problem_clear lifecycle_problem_show \
    lifecycle_lock_show lifecycle_lock_clear \
    layout_palette_show layout_palette_available layout_palette_use layout_palette_register \
    layout_segment_show \
    layout_adapter_show layout_adapter_available layout_adapter_use layout_adapter_load layout_adapter_register \
    layout_show layout_available layout_use layout_load layout_register \
    runner_classifier_show runner_classifier_available runner_classifier_register \
    runner_filter_show runner_filter_available runner_filter_register \
    runner_probe_show runner_probe_available runner_probe_register \
    runner_show runner_available runner_register runner_run runner_watch \
    lifecycle_init_session lifecycle_unfocus runner_exec runner_watch_exec; do
    eval "$fn () { _record_delegate \"\$@\"; }"
  done
}

@test "grammar delegates representative commands once with arguments intact" {
  local row argv expected
  while IFS='|' read -r argv expected; do
    # The grammar contains no quoting syntax; these fixtures intentionally exercise
    # its already-tokenized argv surface.
    run main $argv
    assert_success "$argv"
    assert_output "$expected"
  done <<'CASES'
init|lifecycle_init
apply|lifecycle_apply
show|lifecycle_show
state suspend|lifecycle_state_suspend
status set build active --transient|lifecycle_status_set <build> <active> <--transient>
health clear cpu -t @2|lifecycle_health_clear <cpu> <-t> <@2>
problem set $1 cpu warn sensors-missing|lifecycle_problem_set <$1> <cpu> <warn> <sensors-missing>
lock clear session $1 problem|lifecycle_lock_clear <session> <$1> <problem>
palette use light|layout_palette_use <light>
segment show left-out|layout_segment_show <left-out>
adapter load /tmp/adapter|layout_adapter_load </tmp/adapter>
layout register /tmp/layouts|layout_register </tmp/layouts>
classifier show basic|runner_classifier_show <basic>
filter available|runner_filter_available
probe register /tmp/probes|runner_probe_register </tmp/probes>
runner run tap -- true|runner_run <tap> <--> <true>
_init-session $2|lifecycle_init_session <$2>
_unfocus @3|lifecycle_unfocus <@3>
_run --classify basic -- true|runner_exec <--classify> <basic> <--> <true>
_watch --probe http example.test|runner_watch_exec <--probe> <http> <example.test>
CASES
}

@test "help is generated from the grammar without tmux" {
  run main help
  assert_success
  assert_output --partial "palette"
  assert_output --partial "runner"
  assert_output --partial "available"
  assert_output --partial "--transient"
}

@test "canonical help inspects a noun or leaf command" {
  run main help palette
  assert_success
  assert_output --partial "palette:"
  assert_output --partial "available"
  refute_output --partial "runner:"

  run main help palette use
  assert_success
  assert_output --partial "Usage: airline palette use <palette>"
  assert_output --partial "repaint adapters"
}

@test "noun-local help is not retained" {
  run main palette help
  assert_failure
  assert_output --partial "unknown palette command: help"
}
