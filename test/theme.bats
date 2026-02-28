#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load
load helper

@test "solarized theme sets @airline-outer-bg" {
  init_theme
  run get_option @airline-outer-bg
  assert_output "colour11"
}

@test "solarized theme sets @airline-middle-bg" {
  init_theme
  run get_option @airline-middle-bg
  assert_output "colour10"
}

@test "solarized theme sets @airline-inner-bg" {
  init_theme
  run get_option @airline-inner-bg
  assert_output "colour0"
}

@test "solarized theme sets @airline-secondary" {
  init_theme
  run get_option @airline-secondary
  assert_output "colour12"
}

@test "solarized theme sets @airline-primary" {
  init_theme
  run get_option @airline-primary
  assert_output "colour14"
}

@test "solarized theme sets @airline-emphasized" {
  init_theme
  run get_option @airline-emphasized
  assert_output "colour7"
}

@test "solarized theme sets @airline-active" {
  init_theme
  run get_option @airline-active
  assert_output "colour3"
}

@test "solarized theme sets @airline-special" {
  init_theme
  run get_option @airline-special
  assert_output "colour5"
}

@test "solarized theme sets @airline-alert" {
  init_theme
  run get_option @airline-alert
  assert_output "colour9"
}

@test "solarized theme sets @airline-stress" {
  init_theme
  run get_option @airline-stress
  assert_output "colour1"
}

@test "solarized theme sets @airline-zoom" {
  init_theme
  run get_option @airline-zoom
  assert_output "colour13"
}

@test "solarized theme sets @airline-copy" {
  init_theme
  run get_option @airline-copy
  assert_output "colour4"
}

@test "solarized theme sets @airline-monitor" {
  init_theme
  run get_option @airline-monitor
  assert_output "colour6"
}

@test "THEME array is populated from tmux options" {
  init_theme
  [[ "${THEME[outer-bg]}" == "colour11" ]]
  [[ "${THEME[active]}" == "colour3" ]]
  [[ "${THEME[stress]}" == "colour1" ]]
}
