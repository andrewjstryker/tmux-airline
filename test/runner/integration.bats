#!/usr/bin/env bats

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load
load ../support/helper

# Runner behavior through the real CLI and an isolated tmux server. These drive the
# CLI as a subprocess (the `airline()` helper points it at the isolated server
# via AIRLINE_TMUX), so they exercise the same path production uses.
#
# A clean server (-f /dev/null) so `init`'s default-seeding isn't perturbed by the
# developer's own ~/.tmux.conf (which may already configure airline).

setup() {
  $TMUX -L "$_bats_socket" -f /dev/null new-session -d -s bats
}

# --- init -------------------------------------------------------------------
@test "init exposes first-class element and runner catalogs" {
  airline session init

  run airline classifier list
  assert_line basic
  run airline filter list
  assert_line tap
  run airline probe list
  assert_line http
  run airline runner list
  assert_line tap
  assert_line http

  run airline classifier show basic
  assert_output --partial "Map exit zero"
  run airline probe show http
  assert_output --partial "<endpoint> [<endpoint>...]"
  run airline runner show http
  assert_output --partial "classifier   basic"
  assert_output --partial "probe        http"
  assert_output --partial "http://localhost/health/live"
  run airline runner show http http://example.test/health
  assert_output --partial "http://example.test/health"
  refute_output --partial "http://localhost/health/live"
}

@test "each runner primitive has its own registered path" {
  airline session init
  mkdir -p "$BATS_TEST_TMPDIR/classifiers" "$BATS_TEST_TMPDIR/filters" \
    "$BATS_TEST_TMPDIR/probes"
  printf '%s\n' 'AIRLINE_CLASSIFIER_SUMMARY="custom classifier"' \
    'airline_runner_classify() { printf "warn\\n"; }' > "$BATS_TEST_TMPDIR/classifiers/custom"
  printf '%s\n' 'AIRLINE_FILTER_SUMMARY="custom filter"' \
    'airline_runner_filter() { :; }' > "$BATS_TEST_TMPDIR/filters/custom"
  printf '%s\n' 'AIRLINE_PROBE_SUMMARY="custom probe"' 'AIRLINE_PROBE_USAGE=""' \
    'airline_runner_probe() { "$2" ok; }' > "$BATS_TEST_TMPDIR/probes/custom"

  airline classifier register "$BATS_TEST_TMPDIR/classifiers"
  airline filter register "$BATS_TEST_TMPDIR/filters"
  airline probe register "$BATS_TEST_TMPDIR/probes"
  run airline classifier list
  assert_line custom
  run airline filter list
  assert_line custom
  run airline probe list
  assert_line custom
}

@test "runner validates the selected element contract" {
  airline session init
  mkdir -p "$BATS_TEST_TMPDIR/classifiers"
  printf 'unrelated() { :; }\n' > "$BATS_TEST_TMPDIR/classifiers/broken"
  airline classifier register "$BATS_TEST_TMPDIR/classifiers"

  run airline runner run --classify broken -- true
  assert_failure
  assert_output --partial "classifier 'broken' is invalid"
}

@test "runner here streams output, returns the child status, and projects success" {
  airline session init
  pane="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{pane_id}')"
  key="runner-${pane#%}"

  run airline runner run -- bash -c 'printf "job output\\n"'
  assert_success
  assert_output "job output"
  run airline status show "$key"
  assert_output result
  run airline health show "$key"
  assert_output ""
}

@test "runner here preserves a failed exit and projects attention plus fail" {
  airline session init
  pane="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{pane_id}')"
  key="runner-${pane#%}"

  run airline runner run -- bash -c 'printf "failed output\\n"; exit 7'
  assert_failure 7
  assert_output "failed output"
  run airline status show "$key"
  assert_output attention
  run airline health show "$key"
  assert_output fail
}

@test "a registered classifier can interpret a nonzero exit as warn" {
  airline session init
  pane="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{pane_id}')"
  key="runner-${pane#%}"
  mkdir -p "$BATS_TEST_TMPDIR/classifiers"
  printf '%s\n' 'AIRLINE_CLASSIFIER_SUMMARY="Interpret pytest exit status"' \
    'airline_runner_classify() { [[ "$1" == 5 ]] && printf "warn\\n" || printf "fail\\n"; }' \
    > "$BATS_TEST_TMPDIR/classifiers/pytest"
  airline classifier register "$BATS_TEST_TMPDIR/classifiers"

  run airline runner run --classify pytest -- bash -c 'exit 5'
  assert_failure 5
  run airline status show "$key"
  assert_output attention
  run airline health show "$key"
  assert_output warn
}

@test "a named runner composes monitoring while the caller supplies the command" {
  airline session init

  run airline runner run tap -- bash -c \
    'printf "TAP version 13\n1..1\nok 1 - catalogued\n"'
  assert_success
  assert_output --partial "ok 1 - catalogued"

  run airline runner watch tap
  assert_failure 2
  assert_output --partial "runner 'tap' has no probe"
}

@test "a probe can fail and recover health while the process stays active" {
  airline session init
  session="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{session_id}')"
  pane="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{pane_id}')"
  key="runner-${pane#%}"
  probe_key="$key-probe"
  mkdir -p "$BATS_TEST_TMPDIR/probes"
  health_file="$BATS_TEST_TMPDIR/healthy"
  export health_file
  printf '%s\n' \
    'AIRLINE_PROBE_SUMMARY="Observe test health state"' \
    'AIRLINE_PROBE_USAGE=""' \
    'AIRLINE_RUNNER_PROBE_INTERVAL=0.05' \
    'airline_runner_probe() {' \
    '  [[ -e "$health_file" ]] && "$2" ok || "$2" fail' \
    '}' > "$BATS_TEST_TMPDIR/probes/server"
  airline probe register "$BATS_TEST_TMPDIR/probes"

  airline runner run --probe server -- bash -c 'sleep 0.15; touch "$health_file"; sleep 0.5' & runner_pid=$!
  observed=""
  for _ in {1..100}; do
    observed="$(airline health show "$probe_key")"
    [[ "$observed" == fail ]] && break
    sleep 0.01
  done
  assert_equal "$observed" fail

  recovered=fail
  for _ in {1..100}; do
    recovered="$(airline health show "$probe_key")"
    [[ -z "$recovered" ]] && break
    sleep 0.01
  done
  assert_equal "$recovered" ""
  run airline status show "$key"
  assert_output active

  wait "$runner_pid"
  run airline problem show "$session" airline-runner-server-probe
  assert_output ""
  run airline status show "$key"
  assert_output result
}

@test "runner watch probes remote state without a placeholder command" {
  airline session init
  session="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{session_id}')"
  pane="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{pane_id}')"
  key="runner-${pane#%}-watch"
  probe_key="$key-probe"
  mkdir -p "$BATS_TEST_TMPDIR/probes" "$BATS_TEST_TMPDIR/runners"
  health_file="$BATS_TEST_TMPDIR/healthy"
  observed_pid_file="$BATS_TEST_TMPDIR/watcher-pid"
  observed_arg_file="$BATS_TEST_TMPDIR/watcher-arg"
  watch_output="$BATS_TEST_TMPDIR/watch-output"
  endpoint="http://localhost/health/live"
  export health_file observed_pid_file observed_arg_file endpoint
  printf '%s\n' \
    'AIRLINE_PROBE_SUMMARY="Observe remote test state"' \
    'AIRLINE_PROBE_USAGE="<endpoint>"' \
    'AIRLINE_RUNNER_PROBE_INTERVAL=0.05' \
    'airline_runner_probe() {' \
    '  [[ -e "$observed_pid_file" ]] || printf "%s\n" "$1" > "$observed_pid_file"' \
    '  [[ -e "$observed_arg_file" ]] || printf "%s\n" "$3" > "$observed_arg_file"' \
    '  printf "polled %s\n" "$3"' \
    '  [[ -e "$health_file" ]] && "$2" ok || "$2" fail' \
    '}' > "$BATS_TEST_TMPDIR/probes/remote"
  printf '%s\n' \
    'airline_runner_metadata() {' \
    '  "$1" summary "Watch the remote test endpoint"' \
    '  "$1" usage "<endpoint>"' \
    '}' \
    'airline_runner_configure() {' \
    '  local configure="$1"; shift' \
    '  (( $# == 1 )) || return 2' \
    '  "$configure" classify basic' \
    '  "$configure" probe remote "$1"' \
    '}' \
    > "$BATS_TEST_TMPDIR/runners/remote-watch"
  airline probe register "$BATS_TEST_TMPDIR/probes"
  airline runner register "$BATS_TEST_TMPDIR/runners"

  TMUX_PANE="$pane" AIRLINE_DIR="$PROJECT_ROOT" AIRLINE_TMUX="$TMUX -L $_bats_socket" \
    "$PROJECT_ROOT/airline.sh" runner watch --here remote-watch "$endpoint" \
    > "$watch_output" & watch_pid=$!

  observed=""
  for _ in {1..100}; do
    observed="$(airline health show "$probe_key")"
    [[ "$observed" == fail ]] && break
    sleep 0.01
  done
  assert_equal "$observed" fail
  run cat "$observed_pid_file"
  assert_output "$watch_pid"
  run cat "$observed_arg_file"
  assert_output "$endpoint"
  run cat "$watch_output"
  assert_output --partial "polled $endpoint"
  run airline status show "$key"
  assert_output active

  touch "$health_file"
  recovered=fail
  for _ in {1..100}; do
    recovered="$(airline health show "$probe_key")"
    [[ -z "$recovered" ]] && break
    sleep 0.01
  done
  assert_equal "$recovered" ""

  kill -TERM "$watch_pid"
  wait "$watch_pid" || watch_rc=$?
  assert_equal "${watch_rc:-0}" 143
  run airline status show "$key"
  assert_output ""
  run airline health show "$probe_key"
  assert_output ""
  run airline problem show "$session" airline-runner-remote-probe
  assert_output ""
}

@test "runner watch requires a probe capability" {
  airline session init
  run airline runner watch
  assert_failure 2
  assert_output --partial "need --probe"
}

@test "tap runner preserves output and filters progressive test health" {
  airline session init
  pane="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{pane_id}')"
  key="runner-${pane#%}"
  filter_key="$key-filter"
  output_file="$BATS_TEST_TMPDIR/tap-stream"

  airline runner run --filter tap -- bash -c \
    'printf "TAP version 13\n1..3\nok 1 - first\nnot ok 2 - second\n"; sleep 1.5; printf "ok 3 - third\n"; sleep 1.5; exit 1' \
    > "$output_file" & runner_pid=$!

  observed=""
  for _ in {1..100}; do
    observed="$(airline health show "$filter_key")"
    [[ "$observed" == warn ]] && break
    sleep 0.01
  done
  assert_equal "$observed" warn

  completed=""
  for _ in {1..100}; do
    completed="$(airline health show "$filter_key")"
    [[ "$completed" == fail ]] && break
    sleep 0.01
  done
  assert_equal "$completed" fail

  wait "$runner_pid" || runner_rc=$?
  assert_equal "${runner_rc:-0}" 1
  run cat "$output_file"
  assert_output --partial "not ok 2 - second"
  run airline health show "$filter_key"
  assert_output ""
  run airline health show "$key"
  assert_output fail
}

@test "filter observes stdout by default and can merge stderr" {
  airline session init
  mkdir -p "$BATS_TEST_TMPDIR/filters"
  evidence_file="$BATS_TEST_TMPDIR/evidence"
  export evidence_file
  printf '%s\n' \
    'AIRLINE_FILTER_SUMMARY="Capture filter input"' \
    'airline_runner_filter() { sed -n l > "$evidence_file"; }' \
    > "$BATS_TEST_TMPDIR/filters/capture"
  airline filter register "$BATS_TEST_TMPDIR/filters"

  run airline runner run --filter capture -- bash -c \
    'printf "stdout evidence\n"; printf "stderr evidence\n" >&2'
  run cat "$evidence_file"
  assert_output 'stdout evidence$'

  run airline runner run --filter capture --merge-stderr -- bash -c \
    'printf "stdout evidence\n"; printf "stderr evidence\n" >&2'
  run cat "$evidence_file"
  assert_output $'stdout evidence$\nstderr evidence$'
}

@test "probe stdout is visible and remains outside the filter stream" {
  airline session init
  mkdir -p "$BATS_TEST_TMPDIR/filters" "$BATS_TEST_TMPDIR/probes"
  evidence_file="$BATS_TEST_TMPDIR/filter-evidence"
  export evidence_file
  printf '%s\n' 'AIRLINE_FILTER_SUMMARY="Capture filter input"' \
    'airline_runner_filter() { sed -n l > "$evidence_file"; }' \
    > "$BATS_TEST_TMPDIR/filters/capture"
  printf '%s\n' \
    'AIRLINE_PROBE_SUMMARY="Write visible probe evidence"' \
    'AIRLINE_PROBE_USAGE=""' \
    'AIRLINE_RUNNER_PROBE_INTERVAL=5' \
    'airline_runner_probe() {' \
    '  printf "probe evidence\n"' \
    '  "$2" ok' \
    '}' > "$BATS_TEST_TMPDIR/probes/visible"
  airline filter register "$BATS_TEST_TMPDIR/filters"
  airline probe register "$BATS_TEST_TMPDIR/probes"

  run airline runner run --filter capture --probe visible -- \
    bash -c 'printf "command evidence\n"; sleep 0.2'
  assert_success
  assert_output --partial "command evidence"
  assert_output --partial "probe evidence"
  run cat "$evidence_file"
  assert_output 'command evidence$'
}

@test "runner pane retains failed output and native exit status" {
  airline session init
  origin="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{pane_id}')"

  # Avoid making the retained-pane assertion depend on tmux scheduling a payload
  # that exits in the same instant its pane is created.
  run airline runner run --pane -h -- bash -c 'printf "pane failure\\n"; sleep 1; exit 9'
  assert_success
  spawned="$output"
  assert_regex "$spawned" '^%[0-9]+$'
  run $TMUX -L "$_bats_socket" display-message -p -t "$origin" '#{pane_top}'
  origin_top="$output"
  run $TMUX -L "$_bats_socket" display-message -p -t "$spawned" '#{pane_top}'
  assert_output "$origin_top"
  run $TMUX -L "$_bats_socket" display-message -p -t "$origin" '#{pane_left}'
  origin_left="$output"
  run $TMUX -L "$_bats_socket" display-message -p -t "$spawned" '#{pane_left}'
  refute_output "$origin_left"

  dead=""
  dead_status=""
  dead_signal=""
  for _ in {1..200}; do
    state="$($TMUX -L "$_bats_socket" display-message -p -t "$spawned" \
      '#{pane_dead}:#{pane_dead_status}:#{pane_dead_signal}')"
    IFS=: read -r dead dead_status dead_signal <<< "$state"
    [[ "$dead" == 1 && "$dead_status" == 9 ]] && break
    sleep 0.01
  done
  assert_equal "$dead" 1
  assert_equal "$dead_status" 9 "dead pane signal: ${dead_signal:-none}"
  window="$($TMUX -L "$_bats_socket" display-message -p -t "$spawned" '#{window_id}')"
  run airline status show "runner-${spawned#%}" -t "$window"
  assert_output attention
  run airline health show "runner-${spawned#%}" -t "$window"
  assert_output fail
  run $TMUX -L "$_bats_socket" capture-pane -p -t "$spawned" -S -
  assert_output --partial "pane failure"
}

@test "runner window retains a successful result in its execution window" {
  airline session init

  run airline runner run --window -- bash -c 'printf "window success\\n"'
  assert_success
  spawned="$output"
  assert_regex "$spawned" '^%[0-9]+$'

  dead=""
  for _ in {1..200}; do
    dead="$($TMUX -L "$_bats_socket" display-message -p -t "$spawned" '#{pane_dead}')"
    [[ "$dead" == 1 ]] && break
    sleep 0.01
  done
  assert_equal "$dead" 1
  window="$($TMUX -L "$_bats_socket" display-message -p -t "$spawned" '#{window_id}')"
  run airline status show -t "$window"
  assert_output --partial "runner-${spawned#%}"
  assert_output --partial result
  run $TMUX -L "$_bats_socket" capture-pane -p -t "$spawned" -S -
  assert_output --partial "window success"
}

# --- transient (consume-on-view) --------------------------------------------
