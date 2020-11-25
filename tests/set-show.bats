#! /usr/bin/env bats

BASE_DIR="${BASE_DIR:-${PWD}}"

load fixtures

@test "set help message" {
  run ${BASE_DIR}/status.tmux set help
  [[ "$output" = "Place holder" ]]
  [[ "$status" -eq 0 ]]
}

@test "set/show theme value" {
  local value="yellow" # arbitrary color

  run ${BASE_DIR}/status.tmux set theme monitor "$value"
  [[ "$status" -eq 0 ]]

  run ${BASE_DIR}/status.tmux show theme monitor
  [[ "$output" = "$value" ]]
  [[ "$status" -eq 0 ]]
}

# vim: ft=bash sts=2 sw=2 et
