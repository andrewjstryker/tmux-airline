#! /usr/bin/env bats

@test "bail immediately without tmux" {
  if [[ -x tmux ]]
    then
    skip "tmux installed"
  fi

  run ./status.tmux
  [[ "$output" = "tmux not on search path" ]]
  [[ "$status" = 1 ]]
}
