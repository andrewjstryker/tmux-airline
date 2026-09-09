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

wait_for_pane_exit() { # <pane> <status>
  local pane="$1" expected="$2" state="" dead="" status="" signal=""
  for _ in {1..400}; do
    state="$($TMUX -L "$_bats_socket" display-message -p -t "$pane" \
      '#{pane_dead}:#{pane_dead_status}:#{pane_dead_signal}')"
    IFS=: read -r dead status signal <<< "$state"
    if [[ "$dead" == 1 && "$status" == "$expected" ]]; then
      printf '%s\n' "$state"
      return 0
    fi
    # Avoid starving the same tmux server while the spawned Airline process is
    # publishing its terminal status and health through several transactions.
    sleep 0.05
  done
  printf '%s\n' "$state"
  return 1
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

  run airline classifier describe basic
  assert_output --partial "Map exit zero"
  run airline probe describe http
  assert_output --partial "<endpoint> [<endpoint>...]"
  run airline runner describe http
  assert_output --partial "classifier   basic"
  assert_output --partial "probe        http"
  assert_output --partial "http://localhost/health/live"
  run airline runner describe http http://example.test/health
  assert_output --partial "http://example.test/health"
  refute_output --partial "http://localhost/health/live"
}

@test "each runner primitive has its own registered path" {
  airline session init
  mkdir -p "$BATS_TEST_TMPDIR/classifiers" "$BATS_TEST_TMPDIR/filters" \
    "$BATS_TEST_TMPDIR/probes"
  printf '%s\n' '#| summary: custom classifier' \
    'airline_runner_classify() { printf "warn\\tcustom classifier warning\\n"; }' > "$BATS_TEST_TMPDIR/classifiers/custom"
  printf '%s\n' '#| summary: custom filter' \
    'airline_runner_filter() { :; }' > "$BATS_TEST_TMPDIR/filters/custom"
  printf '%s\n' '#| summary: custom probe' '#| usage:' \
    'airline_runner_probe() { "$2" test-elements probe ok; }' > "$BATS_TEST_TMPDIR/probes/custom"

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

@test "runner in the current pane streams output, returns child status, and projects success" {
  airline session init
  pane="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{pane_id}')"

  run airline runner run -- bash -c 'printf "job output\\n"'
  assert_success
  assert_output "job output"
  run airline status show -t "$pane"
  assert_output --partial "$pane"
  assert_output --partial result
  run airline health show airline-runner-classifier-basic command
  assert_output ""
}

@test "runner in the current pane preserves a failed exit and projects result plus fail" {
  airline session init
  pane="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{pane_id}')"

  run airline runner run -- bash -c 'printf "failed output\\n"; exit 7'
  assert_failure 7
  assert_output "failed output"
  run airline status show -t "$pane"
  assert_output --partial "$pane"
  assert_output --partial result
  run airline health show airline-runner-classifier-basic command
  assert_output "$(printf 'fail\tcommand exited with status 7')"
}

@test "a registered classifier can interpret a nonzero exit as warn" {
  airline session init
  pane="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{pane_id}')"
  mkdir -p "$BATS_TEST_TMPDIR/classifiers"
  printf '%s\n' '#| summary: Interpret pytest exit status' \
    'airline_runner_classify() { [[ "$1" == 5 ]] && printf "warn\\tno tests collected\\n" || printf "fail\\tcommand failed\\n"; }' \
    > "$BATS_TEST_TMPDIR/classifiers/pytest"
  airline classifier register "$BATS_TEST_TMPDIR/classifiers"

  run airline runner run --classify pytest -- bash -c 'exit 5'
  assert_failure 5
  run airline status show -t "$pane"
  assert_output --partial "$pane"
  assert_output --partial result
  run airline health show airline-runner-classifier-pytest command
  assert_output "$(printf 'warn\tno tests collected')"
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
  probe_key=probe
  mkdir -p "$BATS_TEST_TMPDIR/probes"
  health_file="$BATS_TEST_TMPDIR/healthy"
  export health_file
  printf '%s\n' \
    '#| summary: Observe test health state' \
    '#| usage:' \
    '#| interval: 0.05' \
    'airline_runner_probe() {' \
    '  [[ -e "$health_file" ]] && "$2" test-elements probe ok || "$2" test-elements probe fail "service is unavailable"' \
    '}' > "$BATS_TEST_TMPDIR/probes/server"
  airline probe register "$BATS_TEST_TMPDIR/probes"

  airline runner run --probe server -- bash -c 'sleep 0.15; touch "$health_file"; sleep 0.5' & runner_pid=$!
  observed=""
  for _ in {1..100}; do
    observed="$(airline health show test-elements "$probe_key")"
    [[ "$observed" == "$(printf 'fail\tservice is unavailable')" ]] && break
    sleep 0.01
  done
  assert_equal "$observed" "$(printf 'fail\tservice is unavailable')"

  recovered=fail
  for _ in {1..100}; do
    recovered="$(airline health show test-elements "$probe_key")"
    [[ -z "$recovered" ]] && break
    sleep 0.01
  done
  assert_equal "$recovered" ""
  run airline status show -t "$pane"
  assert_output --partial "$pane"
  assert_output --partial active

  wait "$runner_pid"
  run airline problem show test-elements probe
  assert_output ""
  run airline status show -t "$pane"
  assert_output --partial "$pane"
  assert_output --partial result
}

@test "runner watch probes remote state without a placeholder command" {
  airline session init
  session="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{session_id}')"
  pane="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{pane_id}')"
  probe_key=probe
  mkdir -p "$BATS_TEST_TMPDIR/probes" "$BATS_TEST_TMPDIR/runners"
  health_file="$BATS_TEST_TMPDIR/healthy"
  observed_pid_file="$BATS_TEST_TMPDIR/watcher-pid"
  observed_arg_file="$BATS_TEST_TMPDIR/watcher-arg"
  watch_output="$BATS_TEST_TMPDIR/watch-output"
  endpoint="http://localhost/health/live"
  export health_file observed_pid_file observed_arg_file endpoint
  printf '%s\n' \
    '#| summary: Observe remote test state' \
    '#| usage: <endpoint>' \
    '#| interval: 0.05' \
    'airline_runner_probe() {' \
    '  [[ -e "$observed_pid_file" ]] || printf "%s\n" "$1" > "$observed_pid_file"' \
    '  [[ -e "$observed_arg_file" ]] || printf "%s\n" "$4" > "$observed_arg_file"' \
    '  printf "polled %s\n" "$4"' \
    '  [[ -e "$health_file" ]] && "$2" test-elements probe ok || "$2" test-elements probe fail "service is unavailable"' \
    '}' > "$BATS_TEST_TMPDIR/probes/remote"
  printf '%s\n' \
    '#| summary: Watch remote test state' \
    '#| usage: <endpoint>' \
    'airline_runner_configure() {' \
    '  local configure="$1"; shift' \
    '  (( $# == 1 )) || return 2' \
    '  "$configure" classify basic' \
    '  "$configure" probe remote "$1"' \
    '}' \
    > "$BATS_TEST_TMPDIR/runners/remote-watch"
  airline probe register "$BATS_TEST_TMPDIR/probes"
  airline runner register "$BATS_TEST_TMPDIR/runners"

  run airline runner describe remote-watch "$endpoint"
  assert_success
  assert_output --partial 'probe        remote'
  assert_output --partial "$endpoint"

  TMUX_PANE="$pane" AIRLINE_DIR="$PROJECT_ROOT" AIRLINE_TMUX="$TMUX -L $_bats_socket" \
    "$PROJECT_ROOT/airline.sh" runner watch remote-watch "$endpoint" \
    > "$watch_output" & watch_pid=$!

  observed=""
  for _ in {1..100}; do
    observed="$(airline health show test-elements "$probe_key")"
    [[ "$observed" == "$(printf 'fail\tservice is unavailable')" ]] && break
    sleep 0.01
  done
  assert_equal "$observed" "$(printf 'fail\tservice is unavailable')"
  run cat "$observed_pid_file"
  assert_output "$watch_pid"
  run cat "$observed_arg_file"
  assert_output "$endpoint"
  run cat "$watch_output"
  assert_output --partial "polled $endpoint"
  run airline status show -t "$pane"
  assert_output --partial "$pane"
  assert_output --partial active

  touch "$health_file"
  recovered=fail
  for _ in {1..100}; do
    recovered="$(airline health show test-elements "$probe_key")"
    [[ -z "$recovered" ]] && break
    sleep 0.01
  done
  assert_equal "$recovered" ""

  kill -TERM "$watch_pid"
  wait "$watch_pid" || watch_rc=$?
  assert_equal "${watch_rc:-0}" 143
  run airline status show -t "$pane"
  assert_output ""
  run airline health show test-elements "$probe_key"
  assert_output ""
  run airline problem show test-elements probe
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
  filter_key=assertions
  output_file="$BATS_TEST_TMPDIR/tap-stream"

  airline runner run --filter tap -- bash -c \
    'printf "TAP version 13\n1..3\nok 1 - first\nnot ok 2 - second\n"; sleep 1.5; printf "ok 3 - third\n"; sleep 1.5; exit 1' \
    > "$output_file" & runner_pid=$!

  observed=""
  for _ in {1..100}; do
    observed="$(airline health show airline-tap "$filter_key")"
    [[ "$observed" == warn$'\t'* ]] && break
    sleep 0.01
  done
  assert_equal "$observed" "$(printf 'warn\tTAP assertion failed: not ok 2 - second')"

  completed=""
  for _ in {1..100}; do
    completed="$(airline health show airline-tap "$filter_key")"
    [[ "$completed" == fail$'\t'* ]] && break
    sleep 0.01
  done
  assert_equal "$completed" \
    "$(printf 'fail\tTAP stream completed with unsuccessful assertions')"

  wait "$runner_pid" || runner_rc=$?
  assert_equal "${runner_rc:-0}" 1
  run cat "$output_file"
  assert_output --partial "not ok 2 - second"
  run airline health show airline-tap "$filter_key"
  assert_output "$(printf 'fail\tTAP stream completed with unsuccessful assertions')"
  run airline health show airline-runner-classifier-basic command
  assert_output "$(printf 'fail\tcommand exited with status 1')"
}

@test "filter health remains independent of successful exit classification" {
  airline session init
  pane="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{pane_id}')"
  filter_key=assertions

  run airline runner run --filter tap -- bash -c \
    'printf "1..1\nnot ok 1 - semantic failure\n"'
  assert_success
  run airline status show -t "$pane"
  assert_output --partial "$pane"
  assert_output --partial result
  run airline health show airline-runner-classifier-basic command
  assert_output ""
  run airline health show airline-tap "$filter_key"
  assert_output "$(printf 'fail\tTAP stream completed with unsuccessful assertions')"
}

@test "filter observes stdout by default and can merge stderr" {
  airline session init
  mkdir -p "$BATS_TEST_TMPDIR/filters"
  evidence_file="$BATS_TEST_TMPDIR/evidence"
  export evidence_file
  printf '%s\n' \
    '#| summary: Capture filter input' \
    'airline_runner_filter() { sed -n l > "$evidence_file"; "$2" test-elements probe ok; }' \
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
  printf '%s\n' '#| summary: Capture filter input' \
    'airline_runner_filter() { sed -n l > "$evidence_file"; "$2" test-elements probe ok; }' \
    > "$BATS_TEST_TMPDIR/filters/capture"
  printf '%s\n' \
    '#| summary: Write visible probe evidence' \
    '#| usage:' \
    '#| interval: 5' \
    'airline_runner_probe() {' \
    '  printf "probe evidence\n"' \
    '  "$2" test-elements probe ok' \
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

  # Exit immediately: the runner must preserve tmux's native status even when PTY
  # EOF and child reaping occur in the same server turn.
  run airline runner run --pane -h -- bash -c 'printf "pane failure\\n"; exit 9'
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

  run wait_for_pane_exit "$spawned" 9
  assert_success
  IFS=: read -r dead dead_status dead_signal <<< "$output"
  assert_equal "$dead" 1
  assert_equal "$dead_status" 9 "dead pane signal: ${dead_signal:-none}"
  window="$($TMUX -L "$_bats_socket" display-message -p -t "$spawned" '#{window_id}')"
  run airline status show -t "$spawned"
  assert_output --partial "$spawned"
  assert_output --partial result
  run airline health show -t "$spawned" airline-runner-classifier-basic command
  assert_output "$(printf 'fail\tcommand exited with status 9')"
  run $TMUX -L "$_bats_socket" capture-pane -p -t "$spawned" -S -
  assert_output --partial "pane failure"
}

@test "runner window retains a successful result in its execution window" {
  airline session init

  run airline runner run --window -- bash -c 'printf "window success\\n"'
  assert_success
  spawned="$output"
  assert_regex "$spawned" '^%[0-9]+$'

  run wait_for_pane_exit "$spawned" 0
  assert_success
  IFS=: read -r dead dead_status _ <<< "$output"
  assert_equal "$dead" 1
  assert_equal "$dead_status" 0
  window="$($TMUX -L "$_bats_socket" display-message -p -t "$spawned" '#{window_id}')"
  run airline status show -t "$window"
  assert_output --partial "$spawned"
  assert_output --partial result
  run $TMUX -L "$_bats_socket" capture-pane -p -t "$spawned" -S -
  assert_output --partial "window success"
}

# --- result observation -----------------------------------------------------

@test "named runner arguments survive spawned pane reentry and merged filter input" {
  airline session init
  mkdir -p "$BATS_TEST_TMPDIR/catalog"
  cat > "$BATS_TEST_TMPDIR/catalog/arguments" <<'ELEMENT'
#| summary: Verify element arguments across process boundaries
#| usage: <evidence-directory>
airline_runner_classify() {
  local status="$1" signal="$2" directory="$3"; shift 3
  [[ "$status" == 7 && "$signal" == '' && $# == 3 && "$1" == '--policy' && "$2" == 'one two' && "$3" == '' ]] || return 1
  printf 'classifier arguments received\n' > "$directory/classifier"
  printf 'warn\tconfigured classification\n'
}
airline_runner_filter() {
  local report="$2" directory="$4"; shift 4
  [[ $# == 3 && "$1" == '--format' && "$2" == 'three four' && "$3" == '' ]] || return 1
  cat > "$directory/filter"
  "$report" test-elements output ok
}
airline_runner_configure() {
  "$1" classify arguments "$2" --policy 'one two' ''
  "$1" filter arguments "$2" --format 'three four' '' --merge-stderr
}
ELEMENT
  local kind spawned
  for kind in classifier filter runner; do
    airline "$kind" register "$BATS_TEST_TMPDIR/catalog"
  done
  run airline runner run --pane arguments "$BATS_TEST_TMPDIR" -- bash -c \
    'printf "stdout evidence\n"; printf "stderr evidence\n" >&2; exit 7'
  assert_success
  spawned="$output"
  run wait_for_pane_exit "$spawned" 7
  assert_success
  run cat "$BATS_TEST_TMPDIR/classifier"
  assert_output 'classifier arguments received'
  run cat "$BATS_TEST_TMPDIR/filter"
  assert_output $'stdout evidence\nstderr evidence'
  run airline health show -t "$spawned" airline-runner-classifier-arguments command
  assert_output $'warn\tconfigured classification'
}

@test "invalid probe options fail before starting work or creating topology" {
  airline session init
  mkdir -p "$BATS_TEST_TMPDIR/probes"
  cat > "$BATS_TEST_TMPDIR/probes/validated" <<'PROBE'
#| summary: Probe with invocation validation
#| usage: --target <target>
airline_runner_probe_parse() {
  [[ $# == 2 && "$1" == --target ]] && return 0
  printf 'expected --target and one target\n' >&2
  return 2
}
airline_runner_probe() { "$2" test-elements probe ok; }
PROBE
  airline probe register "$BATS_TEST_TMPDIR/probes"
  local panes_before status_before
  panes_before="$($TMUX -L "$_bats_socket" list-panes -a -F '#{pane_id}')"
  status_before="$(airline status show)"
  run airline runner run --probe validated --typo -- touch "$BATS_TEST_TMPDIR/started"
  assert_failure 2
  assert_output --partial 'expected --target and one target'
  [[ ! -e "$BATS_TEST_TMPDIR/started" ]]
  run airline runner watch --window --probe validated --typo
  assert_failure 2
  assert_output --partial 'expected --target and one target'
  run "$TMUX" -L "$_bats_socket" list-panes -a -F '#{pane_id}'
  assert_output "$panes_before"
  run airline status show
  assert_output "$status_before"
  run airline health show airline-runner-probe-validated
  assert_output ''
  run airline problem show airline-runner-probe-validated
  assert_output ''
}

@test "background filter reporters share CLI mutations and preserve contributor recovery ownership" {
  airline session init
  mkdir -p "$BATS_TEST_TMPDIR/filters"
  cat > "$BATS_TEST_TMPDIR/filters/reporting" <<'FILTER'
#| summary: Report health and capability independently
#| usage: <fail|recover>
airline_runner_filter() {
  local health="$2" problem="$3" mode="$4"
  cat >/dev/null
  if [[ "$mode" == fail ]]; then
    "$problem" example-filter dependency fail 'dependency absent' || return
    "$health" example-filter endpoint fail 'observed failure' || return
    "$health" example-filter other ok
  else
    "$health" example-filter endpoint ok || return
    "$problem" example-filter dependency ok
  fi
}
FILTER
  airline filter register "$BATS_TEST_TMPDIR/filters"
  run airline runner run --filter reporting fail -- true
  assert_success
  run airline health show example-filter endpoint
  assert_output $'fail\tobserved failure'
  run airline problem show example-filter dependency
  assert_output --partial 'dependency absent'
  # A successful command and another healthy key do not recover either claim.
  run airline problem show airline-runner filter-reporting
  assert_output ''
  run airline runner run --filter reporting recover -- true
  assert_success
  run airline health show example-filter endpoint
  assert_output ''
  run airline problem show example-filter dependency
  assert_output ''
  run airline problem show --all example-filter dependency
  assert_output --partial resolved
}
