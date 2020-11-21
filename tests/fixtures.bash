#! /usr/bin/env bats

setup () {
  if ! hash tmux 2>/dev/null
  then
    skip "tmux not installed"
  fi

  tmux new-session -d -s test-tmux-status
}

teardown () {
  tmux kill-session -t test-tmux-status
}

# vim: ft=bash sts=2 sw=2 et
