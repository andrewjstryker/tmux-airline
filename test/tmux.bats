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

@test "redraw is harmless with no attached client" {
  load_tmux
  run redraw
  assert_success
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
