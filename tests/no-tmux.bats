#! /usr/bin/env bats

BASE_DIR="${BASE_DIR:-${PWD}}"

@test "bail immediately without tmux" {
  if hash tmux 2> /dev/null
  then
    skip "tmux installed"
  fi

  run "${BASE_DIR}/status.tmux"
  [[ "$output" = "tmux not on search path" ]]
  [[ "$status" -eq 1 ]]
}

# vim: ft=bash sts=2 sw=2 et
