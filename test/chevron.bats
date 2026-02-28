#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load
load helper

# Powerline separator characters
RIGHT_SEP=$'\ue0b0'
LEFT_SEP=$'\ue0b2'

@test "chevron outputs fg/bg with separator" {
  load_airline
  run chevron "red" "blue" "X"
  assert_output "#[fg=blue,bg=red]X"
}

@test "chev_right swaps colors for right-pointing separator" {
  load_airline
  run chev_right "red" "blue"
  assert_output "#[fg=red,bg=blue]${RIGHT_SEP}"
}

@test "chev_left keeps colors for left-pointing separator" {
  load_airline
  run chev_left "red" "blue"
  assert_output "#[fg=blue,bg=red]${LEFT_SEP}"
}

@test "chevron with theme colors" {
  init_theme
  run chev_right "${THEME[outer-bg]}" "${THEME[middle-bg]}"
  assert_output "#[fg=colour11,bg=colour10]${RIGHT_SEP}"
}
