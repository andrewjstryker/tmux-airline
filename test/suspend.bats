#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load
load helper

@test "apply_suspended_overrides flattens backgrounds to inner-bg" {
  init_theme
  local inner="${THEME[inner-bg]}"
  apply_suspended_overrides
  [[ "${THEME[outer-bg]}" == "$inner" ]]
  [[ "${THEME[middle-bg]}" == "$inner" ]]
}

@test "apply_suspended_overrides flattens text to secondary" {
  init_theme
  local sec="${THEME[secondary]}"
  apply_suspended_overrides
  [[ "${THEME[emphasized]}" == "$sec" ]]
  [[ "${THEME[primary]}" == "$sec" ]]
}

@test "apply_suspended_overrides flattens accents to secondary" {
  init_theme
  local sec="${THEME[secondary]}"
  apply_suspended_overrides
  [[ "${THEME[active]}" == "$sec" ]]
  [[ "${THEME[special]}" == "$sec" ]]
  [[ "${THEME[zoom]}" == "$sec" ]]
  [[ "${THEME[copy]}" == "$sec" ]]
  [[ "${THEME[monitor]}" == "$sec" ]]
}

@test "apply_suspended_overrides preserves alert and stress" {
  init_theme
  local alert="${THEME[alert]}"
  local stress="${THEME[stress]}"
  apply_suspended_overrides
  [[ "${THEME[alert]}" == "$alert" ]]
  [[ "${THEME[stress]}" == "$stress" ]]
}

@test "left_outer uses dimmed colors after override" {
  init_theme
  apply_suspended_overrides
  run left_outer
  assert_output --partial "fg=${THEME[secondary]}"
  assert_output --partial "bg=${THEME[inner-bg]}"
}

@test "left_outer uses normal colors without override" {
  init_theme
  run left_outer
  assert_output --partial "fg=${THEME[emphasized]}"
  assert_output --partial "bg=${THEME[outer-bg]}"
}
