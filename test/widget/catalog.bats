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
  assert_line power
  assert_line prefix
  assert_line problem
  refute_output --partial '.sh'
  run catalog_resolve s1 widget battery
  assert_output "$PROJECT_ROOT/layouts/widgets/battery.sh"
}

@test "problem format emits a companion job and live palette references" {
  run widget_format s1 inspect "$PROJECT_ROOT/layouts/widgets/problem.sh" white black
  assert_success
  assert_output --partial "#('$PROJECT_ROOT/layouts/widgets/problem' )"
  assert_output --partial '#{@airline-palette-alert}'
  assert_output --partial '#{@airline-palette-stress}'
  refute_output --partial '@airline--badge-problem'
}

@test "widget format receives segment colors and emits a native fragment" {
  pub_set widget-prefix-show-copy off
  pub_set widget-prefix-show-sync off
  run widget_format s1 inspect "$PROJECT_ROOT/layouts/widgets/prefix.sh" \
    '#{@airline-palette-emphasized}' '#{@airline-palette-inner-bg}'
  assert_success
  assert_output --partial 'client_prefix'
  assert_output --partial '[Prefix]'
  refute_output --partial '#{prefix}'
  assert_output --partial '#{@airline-palette-active}'
  assert_output --partial '#{@airline-palette-emphasized}'
}

@test "battery and power runtime companions emit focused scalars" {
  mkdir -p "$BATS_TEST_TMPDIR/power/BAT0"
  printf 'Battery\n' > "$BATS_TEST_TMPDIR/power/BAT0/type"
  printf '42\n' > "$BATS_TEST_TMPDIR/power/BAT0/capacity"
  printf 'Charging\n' > "$BATS_TEST_TMPDIR/power/BAT0/status"
  run env AIRLINE_POWER_SUPPLY="$BATS_TEST_TMPDIR/power" "$PROJECT_ROOT/layouts/widgets/battery"
  assert_success
  assert_output '42'
  run env AIRLINE_POWER_SUPPLY="$BATS_TEST_TMPDIR/power" "$PROJECT_ROOT/layouts/widgets/power"
  assert_success
  assert_output 'connected'
  printf 'Discharging\n' > "$BATS_TEST_TMPDIR/power/BAT0/status"
  run env AIRLINE_POWER_SUPPLY="$BATS_TEST_TMPDIR/power" "$PROJECT_ROOT/layouts/widgets/power"
  assert_success
  assert_output 'battery'
}

@test "battery and power formats present their independent observations" {
  source "$PROJECT_ROOT/layouts/widgets/battery.sh"
  widget_runtime() { printf '%s' '#(battery-runtime)'; }
  run airline_widget_format '#{@airline-palette-emphasized}' '#{@airline-palette-inner-bg}'
  assert_success
  refute_output --partial '🔋'
  refute_output --partial '⚡'

  source "$PROJECT_ROOT/layouts/widgets/power.sh"
  widget_runtime() { printf '%s' '#(power-runtime)'; }
  run airline_widget_format '#{@airline-palette-emphasized}' '#{@airline-palette-inner-bg}'
  assert_success
  assert_output --partial '🔋'
  assert_output --partial '⚡'
}

@test "widgets expose capability checks without running runtime companions" {
  source "$PROJECT_ROOT/layouts/widgets/prefix.sh"
  run airline_widget_available
  assert_success
  refute [ -e "$BATS_TEST_TMPDIR/runtime-ran" ]
}

@test "CPU owns option defaults validation and literal icons" {
  pub_set widget-cpu-medium 72
  pub_set widget-cpu-high 91
  pub_set widget-cpu-high-icon 'hot $(touch marker)'
  run widget_describe cpu
  assert_success
  assert_output --partial ',91}'
  assert_output --partial ',72}'
  assert_output --partial 'hot $(touch marker)'
  refute_output --partial effective-arguments

  pub_set widget-cpu-medium ''
  run widget_describe cpu
  assert_success
  assert_output --partial ',60}'
  pub_set widget-cpu-medium 99
  run widget_describe cpu
  assert_failure
}

@test "online embeds its own host and timeout options in its runtime expression" {
  pub_set widget-online-host example.com
  pub_set widget-online-timeout 3
  pub_set widget-online-online-icon UP
  source "$PROJECT_ROOT/layouts/widgets/online.sh"
  AIRLINE_WIDGET_RUNTIME="$PROJECT_ROOT/layouts/widgets/online"
  run airline_widget_format white black
  assert_success
  assert_output --partial "'--host' 'example.com' '--timeout' '3'"
  assert_output --partial UP
  pub_set widget-online-timeout 0
  run airline_widget_format white black
  assert_failure
}

@test "power and prefix consult their own public namespaces" {
  pub_set widget-power-connected-icon AC
  source "$PROJECT_ROOT/layouts/widgets/power.sh"
  AIRLINE_WIDGET_RUNTIME="$PROJECT_ROOT/layouts/widgets/power"
  run airline_widget_format white black
  assert_success
  assert_output --partial AC
  assert_output --partial '🔋'
  refute_output --partial '⚡'

  pub_set widget-prefix-show-copy off
  pub_set widget-prefix-show-sync off
  source "$PROJECT_ROOT/layouts/widgets/prefix.sh"
  run airline_widget_format white black
  assert_success
  refute_output --partial '[Copy]'
  refute_output --partial '[Sync]'
  pub_set widget-prefix-show-copy ''
  run airline_widget_format white black
  assert_success
  assert_output --partial '[Copy]'
  pub_set widget-prefix-show-sync invalid
  run airline_widget_format white black
  assert_failure
}

@test "CPU unavailability is returned to the host without publishing a problem" {
  command() {
    [[ "$*" != '-v top' ]] || return 1
    builtin command "$@"
  }
  local before="$(declare -p _FAKE_OPT)"
  run widget_format s1 instance "$PROJECT_ROOT/layouts/widgets/cpu.sh" white black
  assert_failure 3
  assert_output ''
  assert_equal "$(declare -p _FAKE_OPT)" "$before"
}
