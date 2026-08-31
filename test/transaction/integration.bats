#!/usr/bin/env bats

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load
load ../support/helper

# Public transaction diagnostics through the real CLI and an isolated tmux server.
setup() {
  $TMUX -L "$_bats_socket" -f /dev/null new-session -d -s bats
}

@test "diagnostics are empty normally and clear rejects a missing marker" {
  airline session init
  run airline transaction show
  assert_success
  assert_output ""

  run airline transaction clear global server problem
  assert_failure
  assert_output --partial "no such outstanding transaction"
}
