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
  assert_line conventional
  run airline filter list
  assert_line tap
  run airline probe list
  assert_line http
  run airline runner list
  assert_line tap
  assert_line http

  run airline classifier describe conventional
  assert_output --partial "Map exit zero"
  run airline probe describe http
  assert_output --partial "<endpoint> [<endpoint>...]"
  run airline runner describe http
  assert_output --partial "classifier   conventional"
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
    'airline_runner_classify() { printf "warn\\tcustom classifier warning\\n"; }' > "$BATS_TEST_TMPDIR/classifiers/custom.sh"
  printf '%s\n' '#| summary: custom filter' \
    'airline_runner_filter() { :; }' > "$BATS_TEST_TMPDIR/filters/custom.sh"
  printf '%s\n' '#| summary: custom probe' '#| usage:' \
    'airline_runner_probe() { "$2" test-elements probe ok; }' > "$BATS_TEST_TMPDIR/probes/custom.sh"

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
  printf 'unrelated() { :; }\n' > "$BATS_TEST_TMPDIR/classifiers/broken.sh"
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
  run airline health show airline-runner-classifier-conventional command
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
  run airline health show airline-runner-classifier-conventional command
  assert_output "$(printf 'fail\tcommand exited with status 7')"
}

@test "a registered classifier can interpret a nonzero exit as warn" {
  airline session init
  pane="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{pane_id}')"
  mkdir -p "$BATS_TEST_TMPDIR/classifiers"
  printf '%s\n' '#| summary: Interpret pytest exit status' \
    'airline_runner_classify() { [[ "$1" == 5 ]] && printf "warn\\tno tests collected\\n" || printf "fail\\tcommand failed\\n"; }' \
    > "$BATS_TEST_TMPDIR/classifiers/pytest.sh"
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
    '}' > "$BATS_TEST_TMPDIR/probes/server.sh"
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
    '}' > "$BATS_TEST_TMPDIR/probes/remote.sh"
  printf '%s\n' \
    '#| summary: Watch remote test state' \
    '#| usage: <endpoint>' \
    'airline_runner_configure() {' \
    '  local configure="$1"; shift' \
    '  (( $# == 1 )) || return 2' \
    '  "$configure" classify conventional' \
    '  "$configure" probe remote "$1"' \
    '}' \
    > "$BATS_TEST_TMPDIR/runners/remote-watch.sh"
  airline probe register "$BATS_TEST_TMPDIR/probes"
  airline runner register "$BATS_TEST_TMPDIR/runners"

  run airline runner describe remote-watch "$endpoint"
  assert_success
  assert_output --partial 'probe        remote'
  assert_output --partial "$endpoint"

  watch_id="$(airline runner watch remote-watch "$endpoint")"
  assert_regex "$watch_id" '^p-[a-zA-Z0-9]+$'

  observed=""
  for _ in {1..100}; do
    observed="$(airline health show test-elements "$probe_key")"
    [[ "$observed" == "$(printf 'fail\tservice is unavailable')" ]] && break
    sleep 0.01
  done
  assert_equal "$observed" "$(printf 'fail\tservice is unavailable')"
  run cat "$observed_pid_file"
  assert_regex "$output" '^[0-9]+$'
  run cat "$observed_arg_file"
  assert_output "$endpoint"
  run airline process show "$watch_id"
  assert_output --partial "watch"
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

  airline process stop "$watch_id"
  run airline process list
  assert_output ""
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
  run airline health show airline-runner-classifier-conventional command
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
  run airline health show airline-runner-classifier-conventional command
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
    > "$BATS_TEST_TMPDIR/filters/capture.sh"
  airline filter register "$BATS_TEST_TMPDIR/filters"

  run airline runner run --filter capture -- bash -c \
    'printf "stdout evidence\n"; printf "stderr evidence\n" >&2'
  run cat "$evidence_file"
  assert_output 'stdout evidence$'

  run airline runner run --filter capture --merge-stderr -- bash -c \
    'printf "stdout evidence\n"; printf "stderr evidence\n" >&2'
  run cat "$evidence_file"
  assert_line 'stdout evidence$'
  assert_line 'stderr evidence$'
}

@test "probe stdout is visible and remains outside the filter stream" {
  airline session init
  mkdir -p "$BATS_TEST_TMPDIR/filters" "$BATS_TEST_TMPDIR/probes"
  evidence_file="$BATS_TEST_TMPDIR/filter-evidence"
  export evidence_file
  printf '%s\n' '#| summary: Capture filter input' \
    'airline_runner_filter() { sed -n l > "$evidence_file"; "$2" test-elements probe ok; }' \
    > "$BATS_TEST_TMPDIR/filters/capture.sh"
  printf '%s\n' \
    '#| summary: Write visible probe evidence' \
    '#| usage:' \
    '#| interval: 5' \
    'airline_runner_probe() {' \
    '  printf "probe evidence\n"' \
    '  "$2" test-elements probe ok' \
    '}' > "$BATS_TEST_TMPDIR/probes/visible.sh"
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
  run airline health show -t "$spawned" airline-runner-classifier-conventional command
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
  cat > "$BATS_TEST_TMPDIR/catalog/arguments.sh" <<'ELEMENT'
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
  assert_line 'stdout evidence'
  assert_line 'stderr evidence'
  run airline health show -t "$spawned" airline-runner-classifier-arguments command
  assert_output $'warn\tconfigured classification'
}

@test "invalid probe options fail before starting work or creating topology" {
  airline session init
  mkdir -p "$BATS_TEST_TMPDIR/probes"
  cat > "$BATS_TEST_TMPDIR/probes/validated.sh" <<'PROBE'
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
  cat > "$BATS_TEST_TMPDIR/filters/reporting.sh" <<'FILTER'
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

make_lifecycle_probe() {
  mkdir -p "$BATS_TEST_TMPDIR/probes"
  cat > "$BATS_TEST_TMPDIR/probes/lifecycle.sh" <<'PROBE'
#| summary: Exercise process lifetime and streams
#| usage: <evidence>
#| interval: 0.05
airline_runner_probe() {
  printf 'probe stdout\n'
  printf 'probe stderr\n' >&2
  printf '%s\n' "$BASHPID" >> "$4"
  "$2" lifecycle observed fail 'last observation'
}
PROBE
  airline probe register "$BATS_TEST_TMPDIR/probes"
}

@test "probe-only run holds output until process stop and retains observations" {
  airline session init
  make_lifecycle_probe
  airline runner run --probe lifecycle "$BATS_TEST_TMPDIR/evidence" > "$BATS_TEST_TMPDIR/out" 2>&1 &
  local launcher=$! id=""
  for _ in {1..100}; do
    id="$(airline process list | awk '$3 == "run" {print $1}')"
    [[ -s "$BATS_TEST_TMPDIR/evidence" ]] && break
    sleep 0.05
  done
  [[ -n "$id" ]]
  kill -0 "$launcher"
  run cat "$BATS_TEST_TMPDIR/out"
  assert_output --partial 'probe stdout'
  assert_output --partial 'probe stderr'
  airline process stop "$id"
  wait "$launcher" || rc=$?
  assert_equal "${rc:-0}" 143
  run airline process list
  assert_output ''
  run airline health show lifecycle observed
  assert_output $'fail\tlast observation'
}

@test "two watches release the pane and stopping one preserves the other's status" {
  airline session init
  make_lifecycle_probe
  local first second pane
  pane="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{pane_id}')"
  first="$(airline runner watch --probe lifecycle "$BATS_TEST_TMPDIR/first")"
  second="$(airline runner watch --probe lifecycle "$BATS_TEST_TMPDIR/second")"
  assert_regex "$first" '^p-[a-zA-Z0-9]+$'
  assert_regex "$second" '^p-[a-zA-Z0-9]+$'
  [[ "$first" != "$second" ]]
  run airline process show "$second"
  assert_output --partial "$pane"
  assert_output --partial 'watch'
  assert_output --partial 'lifecycle'
  assert_output --partial 'pids'
  airline process stop "$first"
  run airline process list
  refute_output --partial "$first"
  assert_output --partial "$second"
  run airline status show -t "$pane"
  assert_output --partial active
  airline process stop "$second"
  run airline status show -t "$pane"
  assert_output ''
}

@test "pane closure removes a watch without claiming private element children" {
  airline session init
  mkdir -p "$BATS_TEST_TMPDIR/probes"
  cat > "$BATS_TEST_TMPDIR/probes/blocked.sh" <<'PROBE'
#| summary: Block inside an observation
#| usage: <evidence>
airline_runner_probe() {
  sleep 120 &
  printf '%s\n' "$!" > "$4"
  wait "$!"
}
PROBE
  airline probe register "$BATS_TEST_TMPDIR/probes"
  local id owner child records
  id="$(airline runner watch --pane --probe blocked "$BATS_TEST_TMPDIR/child")"
  owner="$(airline process show "$id" | awk '$1 == "pane" {print $2}')"
  for _ in {1..100}; do
    [[ -s "$BATS_TEST_TMPDIR/child" ]] && break
    sleep 0.05
  done
  child="$(cat "$BATS_TEST_TMPDIR/child")"
  kill -0 "$child"
  # The new pane contains a usable shell, not a retained dead supervisor.
  run $TMUX -L "$_bats_socket" display-message -p -t "$owner" '#{pane_dead}'
  assert_output 0
  $TMUX -L "$_bats_socket" kill-pane -t "$owner"
  for _ in {1..100}; do
    records="$(airline process list)"
    [[ "$records" != *"$id"* ]] && break
    sleep 0.05
  done
  [[ "$records" != *"$id"* ]]
  # The probe owns this privately-created child; Airline records and signals its
  # own supervisor/worker only and does not walk the process table.
  kill -0 "$child"
  kill "$child" 2>/dev/null || true
}

@test "none preserves the command exit status without a health verdict" {
  airline session init
  run airline runner run --classify none -- sh -c 'exit 7'
  assert_failure 7
  run airline health show airline-runner-classifier-none command
  assert_output ''
  run airline problem show airline-runner-classifier-none classify
  assert_output ''
}

@test "stop is harmless after completion and accepts repeated stops" {
  airline session init
  make_lifecycle_probe
  local id
  id="$(airline runner watch --probe lifecycle "$BATS_TEST_TMPDIR/evidence")"
  airline process stop "$id"
  run airline process stop "$id"
  assert_success
  assert_output --partial 'already finished'
  run airline process stop "$id"
  assert_success
  assert_output --partial 'already finished'
  run airline problem show airline-runner "process-${id#p-}"
  assert_output ''
}

@test "listing and stopping stale invocations never signal recorded child PIDs" {
  airline session init
  load_tmux
  source "$PROJECT_ROOT/lib/collections.sh"
  local child pane session id
  pane="$(current_pane)"
  session="$(current_session)"
  # A live unrelated process stands in for a numeric PID reused after the original
  # supervisor exited. Neither list nor stop may signal this stored number.
  sleep 30 & child=$!
  for id in p-stalelist p-stalestop; do
    with_global_transaction process coll_set global server process "$id" \
      "$pane" watch 999999999 active '--probe fixture' "$child" "$session"
    if [[ "$id" == p-stalelist ]]; then
      run airline process list
      assert_success
      refute_output --partial "$id"
    else
      run airline process stop "$id"
      assert_success
      assert_output --partial 'already finished'
    fi
    kill -0 "$child"
    run airline problem show airline-runner "process-${id#p-}"
    assert_output ''
  done
  kill "$child"
  wait "$child" 2>/dev/null || true
}

@test "overlapping PID updates preserve membership, stop state, and retirement" {
  load_tmux
  source "$PROJECT_ROOT/lib/collections.sh"
  source "$PROJECT_ROOT/lib/runner.sh"
  local pane session supervisor="$BASHPID"
  pane="$(current_pane)"; session="$(current_session)"

  # Pause the first writer after its tuple read. This forces contenders to arrive
  # while the read/modify/write is in flight, rather than hoping to hit the race.
  eval "$(declare -f coll_get_into | sed '1s/coll_get_into/process_original_get/')"
  coll_get_into() {
    process_original_get "$@" || return
    if [[ "${hold_process_read:-}" == 1 && "$4" == process ]]; then
      hold_process_read=""
      : > "$ready"
      tmux wait-for "$release"
    fi
  }

  local scenario ready release done_file first second blocked attempt tuple
  local owner mode pid state spec pids record_session first_rc second_rc
  for scenario in add remove stop retire; do
    with_global_transaction process _runner_process_record p-overlap "$pane" run \
      "$supervisor" '-- true' "$session"
    _runner_process_add_pid p-overlap 200
    ready="$BATS_TEST_TMPDIR/ready-$scenario"
    done_file="$BATS_TEST_TMPDIR/done-$scenario"
    release="process-release-$scenario-$BATS_TEST_NUMBER"
    (
      hold_process_read=1
      if [[ "$scenario" == remove ]]; then
        _runner_process_remove_pid p-overlap 200
      else
        _runner_process_add_pid p-overlap 300
      fi
    ) & first=$!
    for attempt in {1..500}; do
      [[ -e "$ready" ]] && break
      sleep 0.01
    done
    # Always release/reap before asserting, including a failed setup or writer.
    (
      case "$scenario" in
        add|remove) _runner_process_add_pid p-overlap 400 ;;
        stop) with_global_transaction process _runner_process_request_stop p-overlap ;;
        retire) with_global_transaction process _runner_process_remove p-overlap ;;
      esac
      rc=$?
      : > "$done_file"
      exit "$rc"
    ) & second=$!
    sleep 0.1
    blocked=1; [[ ! -e "$done_file" ]] || blocked=0
    tmux wait-for -S "$release"
    first_rc=0; wait "$first" || first_rc=$?
    second_rc=0; wait "$second" || second_rc=$?
    [[ -e "$ready" ]]
    assert_equal "$first_rc" 0
    assert_equal "$second_rc" 0
    assert_equal "$blocked" 1

    tuple="$(coll_get global server process p-overlap)"
    if [[ "$scenario" == retire ]]; then
      assert_equal "$tuple" ''
      run coll_has global server process p-overlap
      assert_failure 1
      run _runner_process_add_pid p-overlap 500
      assert_failure 1
      run _runner_process_remove_pid p-overlap 200
      assert_success
      run coll_has global server process p-overlap
      assert_failure 1
      continue
    fi
    IFS=$'\t' read -r owner mode pid state spec pids record_session <<< "$tuple"
    assert_equal "$owner" "$pane"
    assert_equal "$pid" "$supervisor"
    assert_equal "$spec" '-- true'
    assert_equal "$record_session" "$session"
    case "$scenario" in
      add) assert_equal "$pids" "$supervisor 200 300 400" ;;
      remove) assert_equal "$pids" "$supervisor 400" ;;
      stop)
        assert_equal "$state" stopping
        assert_equal "$pids" "$supervisor 200 300"
        run coll_get global server process-stop p-overlap
        assert_output stop
        ;;
    esac
  done
}

@test "merged observation preserves separate visible stdout and stderr destinations" {
  airline session init
  mkdir -p "$BATS_TEST_TMPDIR/filters"
  cat > "$BATS_TEST_TMPDIR/filters/copy.sh" <<'FILTER'
#| summary: Copy observation bytes
#| usage: <file>
airline_runner_filter() { cat > "$4"; }
FILTER
  airline filter register "$BATS_TEST_TMPDIR/filters"
  airline runner run --filter copy "$BATS_TEST_TMPDIR/copy" --merge-stderr -- \
    sh -c 'printf out; printf err >&2' > "$BATS_TEST_TMPDIR/out" 2> "$BATS_TEST_TMPDIR/err"
  run cat "$BATS_TEST_TMPDIR/out"
  assert_output out
  run cat "$BATS_TEST_TMPDIR/err"
  assert_output err
  run cat "$BATS_TEST_TMPDIR/copy"
  assert_output --partial out
  assert_output --partial err
}

@test "an early filter cannot truncate the command's terminal output" {
  airline session init
  mkdir -p "$BATS_TEST_TMPDIR/filters"
  printf '%s\n' '#| summary: Return before consuming output' \
    'airline_runner_filter() { return 0; }' > "$BATS_TEST_TMPDIR/filters/early.sh"
  airline filter register "$BATS_TEST_TMPDIR/filters"
  airline runner run --filter early -- sh -c 'i=0; while [ "$i" -lt 10000 ]; do echo evidence; i=$((i+1)); done' \
    > "$BATS_TEST_TMPDIR/output"
  run wc -l < "$BATS_TEST_TMPDIR/output"
  assert_equal "${output// /}" 10000
  run airline problem show airline-runner filter-early
  assert_output --partial fail
}

@test "foreground probe run responds to terminal Ctrl-C and releases its pane" {
  airline session init
  make_lifecycle_probe
  local owner records
  owner="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{pane_id}')"
  # Use an actual shell foreground job, so terminal-generated INT exercises Bash's
  # signal inheritance rather than the different rules of a background test job.
  local invocation
  printf -v invocation 'AIRLINE_TMUX=%q AIRLINE_DIR=%q %q runner run --probe lifecycle %q; echo foreground-finished' \
    "$TMUX -L $_bats_socket" "$PROJECT_ROOT" "$PROJECT_ROOT/airline.sh" "$BATS_TEST_TMPDIR/evidence"
  $TMUX -L "$_bats_socket" send-keys -t "$owner" "$invocation" Enter
  for _ in {1..100}; do
    [[ -s "$BATS_TEST_TMPDIR/evidence" ]] && break
    sleep 0.05
  done
  [[ -s "$BATS_TEST_TMPDIR/evidence" ]]
  $TMUX -L "$_bats_socket" send-keys -t "$owner" C-c
  for _ in {1..100}; do
    records="$(airline process list)"
    [[ -z "$records" ]] && break
    sleep 0.05
  done
  assert_equal "$records" ''
  run $TMUX -L "$_bats_socket" capture-pane -p -t "$owner"
  assert_output --partial 'probe stdout'
  assert_output --partial 'foreground-finished'
}

@test "foreground command keeps stdin and documents status 143 ambiguity" {
  airline session init
  printf 'input evidence\n' | airline runner run -- sh -c 'read value; printf "%s\n" "$value"' \
    > "$BATS_TEST_TMPDIR/out"
  run cat "$BATS_TEST_TMPDIR/out"
  assert_output 'input evidence'
  run airline runner run -- sh -c 'kill -TERM $$'
  assert_failure 143
  run airline health show airline-runner-classifier-conventional command
  assert_output $'fail\tcommand exited with status 143'
  # A child that exits explicitly with 143 is indistinguishable from the
  # signaled child above once Bash reports only the wait status.
  run airline runner run -- sh -c 'exit 143'
  assert_failure 143
  run airline health show airline-runner-classifier-conventional command
  assert_output $'fail\tcommand exited with status 143'
  run airline problem show airline-runner-classifier-conventional classify
  assert_output ''
}
