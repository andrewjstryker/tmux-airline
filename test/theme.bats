#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load
load helper

@test "solarized-dark theme sets @airline-outer-bg" {
  init_theme
  run get_option @airline-outer-bg
  assert_output "colour11"
}

@test "solarized-dark theme sets @airline-middle-bg" {
  init_theme
  run get_option @airline-middle-bg
  assert_output "colour10"
}

@test "solarized-dark theme sets @airline-inner-bg" {
  init_theme
  run get_option @airline-inner-bg
  assert_output "colour0"
}

@test "solarized-dark theme sets @airline-secondary" {
  init_theme
  run get_option @airline-secondary
  assert_output "colour12"
}

@test "solarized-dark theme sets @airline-primary" {
  init_theme
  run get_option @airline-primary
  assert_output "colour14"
}

@test "solarized-dark theme sets @airline-emphasized" {
  init_theme
  run get_option @airline-emphasized
  assert_output "colour7"
}

@test "solarized-dark theme sets @airline-active" {
  init_theme
  run get_option @airline-active
  assert_output "colour3"
}

@test "solarized-dark theme sets @airline-special" {
  init_theme
  run get_option @airline-special
  assert_output "colour5"
}

@test "solarized-dark theme sets @airline-alert" {
  init_theme
  run get_option @airline-alert
  assert_output "colour9"
}

@test "solarized-dark theme sets @airline-stress" {
  init_theme
  run get_option @airline-stress
  assert_output "colour1"
}

@test "solarized-dark theme sets @airline-zoom" {
  init_theme
  run get_option @airline-zoom
  assert_output "colour13"
}

@test "solarized-dark theme sets @airline-copy" {
  init_theme
  run get_option @airline-copy
  assert_output "colour4"
}

@test "solarized-dark theme sets @airline-monitor" {
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

# --- Theme contract tests ---
# Every theme file must define all required @airline-* keys.

REQUIRED_KEYS=(
  @airline-outer-bg
  @airline-middle-bg
  @airline-inner-bg
  @airline-secondary
  @airline-primary
  @airline-emphasized
  @airline-active
  @airline-special
  @airline-alert
  @airline-stress
  @airline-zoom
  @airline-copy
  @airline-monitor
)

@test "all themes define every required key" {
  load_airline
  local missing=""
  for theme_file in "$PROJECT_ROOT"/themes/*; do
    local name="$(basename "$theme_file")"
    $TMUX -L "$_bats_socket" source-file "$theme_file"
    for key in "${REQUIRED_KEYS[@]}"; do
      local val="$(get_option "$key")"
      if [[ -z "$val" ]]; then
        missing+="  $name: $key"$'\n'
      fi
    done
  done
  if [[ -n "$missing" ]]; then
    echo "Missing keys:"$'\n'"$missing"
    return 1
  fi
}
