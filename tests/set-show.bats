#! /usr/bin/env bats

BASE_DIR="${BASE_DIR:-${PWD}}"

load fixtures

@test "set help message" {
  run ${BASE_DIR}/status.tmux set help
  [[ "$output" = "Place holder" ]]
  [[ "$status" -eq 0 ]]
}

# vim: ft=bash sts=2 sw=2 et
