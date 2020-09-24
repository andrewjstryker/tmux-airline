#! /usr/bin/env bats

@test "bail immediately without tmux" {
  if hash tmux 2>/dev/null
  then
    skip "tmux installed"
  fi

  run status.tmux
  [[ "$output" = "tmux not on search path" ]]
  [[ "$status" -eq 1 ]]
}

# vim: ft=sh sts=2 sw=2 et
