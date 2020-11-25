#! /usr/bin/env bats

BASE_DIR="${BASE_DIR:-${PWD}}"

load fixtures

@test "main help message" {
  skip "Help message not defined"
  run ${BASE_DIR}/status.tmux help
  [[ "$output" = "Place holder" ]]
  [[ "$status" -eq 0 ]]
}

@test "bad arg" {
  skip "Help message not defined"
  run ${BASE_DIR}/status.tmux blat
  [[ "$output" = "Place holder" ]]
  [[ "$status" -eq 1 ]]
}

# vim: ft=bash sts=2 sw=2 et
