#!/usr/bin/env bats

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load

PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

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
    session_init session_apply session_show \
    session_suspend session_resume session_toggle \
    signal_clear_transient \
    signal_status_set signal_status_clear signal_status_show \
    signal_health_set signal_health_clear signal_health_show \
    signal_problem_set signal_problem_clear signal_problem_show \
    transaction_show transaction_clear_stale \
    layout_palette_show layout_palette_list layout_palette_use layout_palette_register \
    layout_segment_show \
    layout_adapter_show layout_adapter_list layout_adapter_use layout_adapter_load layout_adapter_register \
    layout_show layout_list layout_use layout_load layout_register \
    runner_classifier_show runner_classifier_list runner_classifier_register \
    runner_filter_show runner_filter_list runner_filter_register \
    runner_probe_show runner_probe_list runner_probe_register \
    runner_show runner_list runner_register runner_run runner_watch; do
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
session init -t work|session_init <-t> <work>
session apply|session_apply
session show state|session_show <state>
session suspend|session_suspend
session resume|session_resume
session toggle|session_toggle
signal clear-transient -t @3|signal_clear_transient <-t> <@3>
status set build active --transient|signal_status_set <build> <active> <--transient>
health clear cpu -t @2|signal_health_clear <cpu> <-t> <@2>
problem set $1 cpu warn sensors-missing|signal_problem_set <$1> <cpu> <warn> <sensors-missing>
transaction clear session $1 problem|transaction_clear_stale <session> <$1> <problem>
palette use light|layout_palette_use <light>
segment show left-out|layout_segment_show <left-out>
adapter load /tmp/adapter|layout_adapter_load </tmp/adapter>
layout register /tmp/layouts|layout_register </tmp/layouts>
classifier show basic|runner_classifier_show <basic>
filter list|runner_filter_list
probe register /tmp/probes|runner_probe_register </tmp/probes>
runner run tap -- true|runner_run <tap> <--> <true>
CASES
}

@test "removed state and callback command vocabularies are rejected" {
  run main state show
  assert_failure
  assert_output --partial "unknown command: state"

  run main _init-session '$2'
  assert_failure
  assert_output --partial "unknown command: _init-session"

  run main _unfocus @3
  assert_failure
  assert_output --partial "unknown command: _unfocus"

  run main _run -- true
  assert_failure
  assert_output --partial "unknown command: _run"

  run main _watch --probe http example.test
  assert_failure
  assert_output --partial "unknown command: _watch"

  run main lock show
  assert_failure
  assert_output --partial "unknown command: lock"
}

@test "help is generated from the grammar without tmux" {
  run main help
  assert_success
  assert_output --partial "palette"
  assert_output --partial "runner"
  assert_output --partial "list"
  assert_output --partial "--transient"
  refute_output --partial "list        — list"

  local session_line layout_line runner_line signals_line diagnostics_line
  session_line="$(printf '%s\n' "$output" | grep -n '^Session commands$' | cut -d: -f1)"
  layout_line="$(printf '%s\n' "$output" | grep -n '^Layout commands$' | cut -d: -f1)"
  runner_line="$(printf '%s\n' "$output" | grep -n '^Runner commands$' | cut -d: -f1)"
  signals_line="$(printf '%s\n' "$output" | grep -n '^Signals commands$' | cut -d: -f1)"
  diagnostics_line="$(printf '%s\n' "$output" | grep -n '^Diagnostics commands$' | cut -d: -f1)"
  (( session_line < layout_line && layout_line < runner_line && \
     runner_line < signals_line && signals_line < diagnostics_line ))
}

@test "canonical help inspects a noun or leaf command" {
  run main help palette
  assert_success
  assert_output --partial "palette:"
  assert_output --partial "list"
  refute_output --partial "runner:"

  run main help palette use
  assert_success
  assert_output --partial "Usage: airline palette use <palette>"
  assert_output --partial "repaint adapters"
}

@test "help sections are explicit and independent of parser indentation" {
  AIRLINE_HELP_SOURCE="$BATS_TEST_TMPDIR/grammar"
  printf '%s\n' \
    '    # help:begin sample' \
    '      case "$verb" in' \
    '        show) owner_show ;; #| — show the sample' \
    '      esac' \
    '    # help:end sample' > "$AIRLINE_HELP_SOURCE"

  run _help_records sample
  assert_success
  assert_output $'show\t— show the sample'

  run _help_records missing
  assert_failure
  assert_output --partial "missing help section: missing"
}

@test "noun-local help is not retained" {
  run main palette help
  assert_failure
  assert_output --partial "unknown palette command: help"
}
