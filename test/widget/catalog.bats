#!/usr/bin/env bats
load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load
load ../support/helper

setup() { load_session; catalog_register_builtin s1 widget "$PROJECT_ROOT/layouts/widgets"; }

@test "widget catalog resolves format definitions and hides runtime companions" {
  run catalog_list s1 widget
  assert_success
  assert_line battery
  assert_line cpu
  assert_line online
  assert_line prefix
  refute_output --partial '.sh'
  run catalog_resolve s1 widget battery
  assert_output "$PROJECT_ROOT/layouts/widgets/battery.sh"
}

@test "widget format receives segment colors and emits a native fragment" {
  run widget_format s1 inspect "$PROJECT_ROOT/layouts/widgets/prefix.sh" \
    '#{@airline-palette-emphasized}' '#{@airline-palette-inner-bg}' \
    --show-copy off --show-sync off
  assert_success
  assert_output --partial 'client_prefix'
  assert_output --partial '#{@airline-palette-active}'
  assert_output --partial '#{@airline-palette-emphasized}'
}

@test "runtime companion emits a scalar without Airline state" {
  mkdir -p "$BATS_TEST_TMPDIR/power/BAT0"
  printf 'Battery\n' > "$BATS_TEST_TMPDIR/power/BAT0/type"
  printf '42\n' > "$BATS_TEST_TMPDIR/power/BAT0/capacity"
  printf 'Charging\n' > "$BATS_TEST_TMPDIR/power/BAT0/status"
  run env AIRLINE_POWER_SUPPLY="$BATS_TEST_TMPDIR/power" "$PROJECT_ROOT/layouts/widgets/battery"
  assert_success
  assert_output '42:charging'
}

@test "widgets expose capability checks without running runtime companions" {
  source "$PROJECT_ROOT/layouts/widgets/prefix.sh"
  run airline_widget_available
  assert_success
  refute [ -e "$BATS_TEST_TMPDIR/runtime-ran" ]
}
