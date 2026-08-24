#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load
load helper

# tmux.sh — the mechanical layer, exercised directly against an isolated server.

# --- scalar options: global -------------------------------------------------

@test "opt_set_global / opt_get_global round-trip" {
  load_tmux
  opt_set_global @airline-x hello
  run opt_get_global @airline-x
  assert_output "hello"
}

@test "opt_get_global is empty when unset" {
  load_tmux
  run opt_get_global @airline-missing
  assert_output ""
}

@test "opt_set_global preserves a value with spaces" {
  load_tmux
  opt_set_global @airline-x "a b  c"
  run opt_get_global @airline-x
  assert_output "a b  c"
}

@test "opt_unset_global removes the option" {
  load_tmux
  opt_set_global @airline-x hello
  opt_unset_global @airline-x
  run opt_get_global @airline-x
  assert_output ""
}

@test "opt_unset_global on a missing option is harmless" {
  load_tmux
  run opt_unset_global @airline-missing
  assert_success
}

@test "opt_getor_global returns default when unset, value when set" {
  load_tmux
  run opt_getor_global @airline-x 42
  assert_output "42"
  opt_set_global @airline-x 7
  run opt_getor_global @airline-x 42
  assert_output "7"
}

@test "opt_setif_global writes and signals change only when the value moves" {
  load_tmux
  run opt_setif_global @airline-x a   # unset -> a : changed
  assert_success
  run opt_setif_global @airline-x a   # a -> a    : no change
  assert_failure
  run opt_setif_global @airline-x b   # a -> b    : changed
  assert_success
  run opt_get_global @airline-x
  assert_output "b"
}

# --- scalar options: session ------------------------------------------------

@test "opt_set_session / opt_get_session round-trip at session scope" {
  load_tmux
  session="$(current_session)"
  opt_set_session "$session" @airline-problem alert
  run opt_get_session "$session" @airline-problem
  assert_output "alert"
}

@test "session and global scopes are independent" {
  load_tmux
  session="$(current_session)"
  opt_set_global @airline-problem ok
  opt_set_session "$session" @airline-problem stress
  run opt_get_global @airline-problem
  assert_output "ok"
  run opt_get_session "$session" @airline-problem
  assert_output "stress"
}

@test "opt_unset_session removes a session option" {
  load_tmux
  session="$(current_session)"
  opt_set_session "$session" @airline-problem alert
  opt_unset_session "$session" @airline-problem
  run opt_get_session "$session" @airline-problem
  assert_output ""
}

@test "opt_setif_session gates on change" {
  load_tmux
  session="$(current_session)"
  run opt_setif_session "$session" @airline-problem alert
  assert_success
  run opt_setif_session "$session" @airline-problem alert
  assert_failure
}

# --- scalar options: window -------------------------------------------------

@test "opt_set_window / opt_get_window round-trip at window scope" {
  load_tmux
  win="$(current_window)"
  opt_set_window "$win" @airline-health alert
  run opt_get_window "$win" @airline-health
  assert_output "alert"
}

@test "window and global scopes are independent" {
  load_tmux
  win="$(current_window)"
  opt_set_global @airline-health ok
  opt_set_window "$win" @airline-health stress
  run opt_get_global @airline-health
  assert_output "ok"
  run opt_get_window "$win" @airline-health
  assert_output "stress"
}

@test "opt_unset_window removes the window option" {
  load_tmux
  win="$(current_window)"
  opt_set_window "$win" @airline-health alert
  opt_unset_window "$win" @airline-health
  run opt_get_window "$win" @airline-health
  assert_output ""
}

@test "opt_setif_window gates on change" {
  load_tmux
  win="$(current_window)"
  run opt_setif_window "$win" @airline-health alert
  assert_success
  run opt_setif_window "$win" @airline-health alert
  assert_failure
}

# --- standalone verbs -------------------------------------------------------

@test "current_window returns a window id" {
  load_tmux
  run current_window
  assert_output --regexp '^@[0-9]+$'
}

@test "resolve_window lets tmux canonicalize a pane target" {
  load_tmux
  pane="$(tmux display-message -p '#{pane_id}')"
  run resolve_window "$pane"
  assert_output --regexp '^@[0-9]+$'
}

@test "current_session returns a session id" {
  load_tmux
  run current_session
  assert_output --regexp '^\$[0-9]+$'
}

@test "resolve_session lets tmux map a pane target to its session" {
  load_tmux
  pane="$(tmux display-message -p '#{pane_id}')"
  run resolve_session "$pane"
  assert_output --regexp '^\$[0-9]+$'
}

@test "resolve_session_target canonicalizes a session name" {
  load_tmux
  run resolve_session_target bats
  assert_output --regexp '^\$[0-9]+$'
}

@test "list_sessions returns canonical session ids" {
  load_tmux
  tmux new-session -d -s second
  run list_sessions
  assert_line --index 0 --regexp '^\$[0-9]+$'
  assert_line --index 1 --regexp '^\$[0-9]+$'
}

# Transaction callbacks used below. They exercise tmux.sh directly; API tests assume
# this mechanical contract and do not reproduce lock scheduling through CLI calls.
transaction_result () { printf '%s' "$1"; return "$2"; }
transaction_mark () { printf '%s' "${2:-done}" > "$1"; }
transaction_hold () { : > "$1"; tmux wait-for "$2"; }
transaction_spin () { : > "$1"; while :; do :; done; }
transaction_exit () { exit "$1"; }
transaction_nested () { with_session_transaction "$1" problem transaction_result nested 0; }

wait_for_file () {
  local file="$1"
  for _ in {1..100}; do
    [[ -e "$file" ]] && return 0
    sleep 0.01
  done
  return 1
}

@test "scoped transaction preserves callback output/status and releases after return" {
  load_tmux
  session="$(current_session)"

  run with_session_transaction "$session" problem transaction_result payload 7
  assert_failure 7
  assert_output "payload"
  run with_session_transaction "$session" problem transaction_nested "$session"
  assert_failure 2
  assert_output --partial "nested state transaction"
  run with_session_transaction "$session" problem transaction_result reused 0
  assert_success
  assert_output "reused"
}

@test "scoped transaction releases its lock when a callback exits" {
  load_tmux
  session="$(current_session)"

  run with_session_transaction "$session" problem transaction_exit 9
  assert_failure 9
  run with_session_transaction "$session" problem transaction_result reused 0
  assert_success
  assert_output "reused"
}

@test "scoped transaction releases its lock when its process is terminated" {
  load_tmux
  session="$(current_session)"
  ready="$BATS_TEST_TMPDIR/ready-signal"
  reused="$BATS_TEST_TMPDIR/reused-signal"
  export PROJECT_ROOT
  export TMUX_TEST_BIN="$TMUX" TMUX_TEST_SOCKET="$_bats_socket"

  bash -c '
    tmux () { "$TMUX_TEST_BIN" -L "$TMUX_TEST_SOCKET" "$@"; }
    source "$PROJECT_ROOT/tmux.sh"
    spin () { : > "$1"; while :; do :; done; }
    with_session_transaction "$1" problem spin "$2"
  ' _ "$session" "$ready" & transaction_pid=$!
  wait_for_file "$ready"
  record="$(transaction_list)"
  IFS=$'\t' read -r scope owner namespace state owner_pid _ <<< "$record"
  assert_equal "$scope" session
  assert_equal "$owner" "$session"
  assert_equal "$namespace" problem
  assert_equal "$state" active
  kill -TERM "$owner_pid"
  transaction_status=0
  wait "$transaction_pid" || transaction_status=$?
  assert_equal "$transaction_status" 143

  run timeout -k 1 2 bash -c '
    tmux () { "$TMUX_TEST_BIN" -L "$TMUX_TEST_SOCKET" "$@"; }
    source "$PROJECT_ROOT/tmux.sh"
    mark () { : > "$1"; }
    with_session_transaction "$1" problem mark "$2"
  ' _ "$session" "$reused"
  assert_success
  [[ -e "$reused" ]]
}

@test "transaction list detects a SIGKILL-stale lock and clear recovers it" {
  load_tmux
  session="$(current_session)"
  ready="$BATS_TEST_TMPDIR/ready-stale"

  with_session_transaction "$session" problem transaction_spin "$ready" & transaction_pid=$!
  wait_for_file "$ready"
  record="$(transaction_list)"
  IFS=$'\t' read -r scope owner namespace state owner_pid age <<< "$record"
  assert_equal "$scope" session
  assert_equal "$owner" "$session"
  assert_equal "$namespace" problem
  assert_equal "$state" active
  [[ "$age" =~ ^[0-9]+$ ]]

  kill -KILL "$owner_pid"
  wait "$transaction_pid" 2>/dev/null || true
  record="$(transaction_list)"
  IFS=$'\t' read -r _ _ _ state stale_pid _ <<< "$record"
  assert_equal "$state" stale
  assert_equal "$stale_pid" "$owner_pid"

  run transaction_clear session "$session" problem
  assert_success
  run transaction_list
  assert_output ""
  run with_session_transaction "$session" problem transaction_result recovered 0
  assert_success
  assert_output "recovered"
}

@test "transaction clear refuses absent and active locks" {
  load_tmux
  session="$(current_session)"
  ready="$BATS_TEST_TMPDIR/ready-live"
  release="release-live-$BATS_TEST_NUMBER"

  run transaction_clear session "$session" problem
  assert_failure 3
  with_session_transaction "$session" problem transaction_hold "$ready" "$release" & holder=$!
  wait_for_file "$ready"
  run transaction_clear session "$session" problem
  assert_failure 4
  tmux wait-for -S "$release"
  wait "$holder"
}

@test "transaction subshell leaves caller traps unchanged" {
  load_tmux
  session="$(current_session)"
  trap 'printf caller-int >/dev/null' INT
  before="$(trap -p INT)"

  with_session_transaction "$session" problem transaction_result ignored 0 >/dev/null
  after="$(trap -p INT)"
  assert_equal "$after" "$before"
  trap - INT
}

@test "same owner and namespace serialize session and window transactions" {
  load_tmux
  session="$(current_session)"
  win="$(current_window)"
  local wrapper target ns ready release blocked holder contender

  for spec in "with_session_transaction $session problem" "with_window_transaction $win status"; do
    read -r wrapper target ns <<< "$spec"
    ready="$BATS_TEST_TMPDIR/ready-${wrapper}"
    blocked="$BATS_TEST_TMPDIR/blocked-${wrapper}"
    release="release-${wrapper}-${BATS_TEST_NUMBER}"

    "$wrapper" "$target" "$ns" transaction_hold "$ready" "$release" & holder=$!
    wait_for_file "$ready"
    "$wrapper" "$target" "$ns" transaction_mark "$blocked" & contender=$!
    sleep 0.1
    [[ ! -e "$blocked" ]]

    tmux wait-for -S "$release"
    wait "$holder"
    wait "$contender"
    [[ -e "$blocked" ]]
  done
}

@test "transaction locks are isolated by owner, namespace, and scope" {
  load_tmux
  session="$(current_session)"
  tmux new-session -d -s second
  second="$(resolve_session_target second)"
  win="$(current_window)"
  ready="$BATS_TEST_TMPDIR/ready-isolation"
  release="release-isolation-$BATS_TEST_NUMBER"
  same="$BATS_TEST_TMPDIR/same"
  other_owner="$BATS_TEST_TMPDIR/other-owner"
  other_ns="$BATS_TEST_TMPDIR/other-ns"
  other_scope="$BATS_TEST_TMPDIR/other-scope"

  with_session_transaction "$session" problem transaction_hold "$ready" "$release" & holder=$!
  wait_for_file "$ready"
  with_session_transaction "$session" problem transaction_mark "$same" & same_pid=$!
  with_session_transaction "$second" problem transaction_mark "$other_owner" & owner_pid=$!
  with_session_transaction "$session" health transaction_mark "$other_ns" & ns_pid=$!
  with_window_transaction "$win" problem transaction_mark "$other_scope" & scope_pid=$!

  wait_for_file "$other_owner"
  wait_for_file "$other_ns"
  wait_for_file "$other_scope"
  [[ ! -e "$same" ]]

  tmux wait-for -S "$release"
  wait "$holder"
  wait "$same_pid"
  wait "$owner_pid"
  wait "$ns_pid"
  wait "$scope_pid"
  [[ -e "$same" ]]
}

@test "redraw is harmless with no attached client" {
  load_tmux
  run redraw
  assert_success
}

@test "runner topology wrappers create panes/windows with argv and retain per pane" {
  load_tmux
  pane="$(current_pane)"
  cwd="$(current_path)"

  split="$(runner_open_pane "$pane" "$cwd" bash -c 'sleep 30')"
  [[ "$split" =~ ^%[0-9]+$ ]]
  run tmux display-message -p -t "$split" '#{pane_current_path}'
  assert_output "$cwd"
  runner_retain_pane "$split"
  run tmux show-options -pv -t "$split" remain-on-exit
  assert_output on

  window="$(runner_open_window "$(current_session)" "$cwd" bash -c 'sleep 30')"
  [[ "$window" =~ ^%[0-9]+$ ]]
  run tmux display-message -p -t "$window" '#{pane_current_path}'
  assert_output "$cwd"
}

@test "source_file loads a tmux file that sets options" {
  load_tmux
  f="$BATS_TMPDIR/airline-palette-$BATS_TEST_NUMBER"
  printf 'set-option -g @airline-loaded yes\n' > "$f"
  source_file "$f"
  run opt_get_global @airline-loaded
  assert_output "yes"
}

@test "hook_set / hook_unset register and clear a hook" {
  load_tmux
  hook_set "pane-focus-out[90]" "display-message hi"
  run tmux show-hooks -g pane-focus-out
  assert_output --partial "pane-focus-out[90]"
  hook_unset "pane-focus-out[90]"
  run tmux show-hooks -g pane-focus-out
  refute_output --partial "pane-focus-out[90]"
}

@test "key_bind / key_unbind register and clear a binding" {
  load_tmux
  key_bind root F12 "display-message suspended"
  run tmux list-keys -T root
  assert_output --partial "F12"
  key_unbind root F12
  run tmux list-keys -T root
  refute_output --partial "F12"
}
