#!/usr/bin/env bats
load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load
load ../support/helper

setup() { load_session; catalog_register_builtin s1 widget "$PROJECT_ROOT/layouts/widgets"; }

@test "widget catalog resolves format definitions and hides runtime companions" {
  run catalog_list s1 widget
  assert_success
  refute_output --partial battery
  assert_line cpu
  assert_line online
  assert_line power
  assert_line prefix
  assert_line problem
  refute_output --partial '.sh'
  run catalog_resolve s1 widget power
  assert_output "$PROJECT_ROOT/layouts/widgets/power.sh"
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

@test "widgets expose capability checks without running runtime companions" {
  source "$PROJECT_ROOT/layouts/widgets/prefix.sh"
  run airline_widget_available
  assert_success
  refute [ -e "$BATS_TEST_TMPDIR/runtime-ran" ]
}

@test "CPU owns threshold defaults and validation" {
  pub_set widget-cpu-medium 72
  pub_set widget-cpu-high 91
  run widget_describe cpu
  assert_success
  assert_output --partial ',91}'
  assert_output --partial ',72}'
  assert_output --partial CPU
  refute_output --partial effective-arguments

  pub_set widget-cpu-medium ''
  run widget_describe cpu
  assert_success
  assert_output --partial ',60}'
  pub_set widget-cpu-medium 99
  run widget_describe cpu
  assert_failure
}

@test "prefix consults its own public namespace" {
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

@test "power companion distinguishes charging connected and discharging with validated capacity" {
  local root="$BATS_TEST_TMPDIR/power" state
  mkdir -p "$root/BAT0"
  printf 'Battery\n' > "$root/BAT0/type"
  printf '005\n' > "$root/BAT0/capacity"
  for state in Charging Discharging Full 'Not charging' Unknown; do
    printf '%s\n' "$state" > "$root/BAT0/status"
    run env AIRLINE_POWER_SUPPLY="$root" "$PROJECT_ROOT/layouts/widgets/power"
    assert_success
    case "$state" in
      Charging) assert_output 'charging 5' ;;
      Discharging) assert_output 'battery 5' ;;
      Full|'Not charging') assert_output 'connected 5' ;;
      Unknown) assert_output unknown ;;
    esac
  done
  printf 'Charging\n' > "$root/BAT0/status"
  for capacity in '' -1 101 nonsense; do
    printf '%s\n' "$capacity" > "$root/BAT0/capacity"
    run env AIRLINE_POWER_SUPPLY="$root" "$PROJECT_ROOT/layouts/widgets/power"
    assert_success
    assert_output unknown
  done
  rm "$root/BAT0/capacity"
  run env AIRLINE_POWER_SUPPLY="$root" "$PROJECT_ROOT/layouts/widgets/power"
  assert_output unknown
  printf 'Not charging\n' > "$root/BAT0/status"
  run env AIRLINE_POWER_SUPPLY="$root" "$PROJECT_ROOT/layouts/widgets/power"
  assert_output unknown
  rm "$root/BAT0/status"
  run env AIRLINE_POWER_SUPPLY="$root" "$PROJECT_ROOT/layouts/widgets/power"
  assert_output unknown
}

@test "layout resolves font preference once and shares it across widgets" {
  eval "$(declare -f pub_get_into | sed '1s/pub_get_into/original_pub_get_into/')"
  pub_get_into() {
    [[ "$2" != nerd-fonts ]] || printf 'read\n' >> "$BATS_TEST_TMPDIR/font-reads"
    original_pub_get_into "$@"
  }
  pub_set nerd-fonts on
  _layout_definition_evaluate s1 "$PROJECT_ROOT/layouts/definitions/full.sh"
  assert_equal "$(cat "$BATS_TEST_TMPDIR/font-reads")" read
  [[ "${AIRLINE_LAYOUT_PART_FORMATS[*]}" == *$'\uf4bc'* ]]
  [[ "${AIRLINE_LAYOUT_PART_FORMATS[*]}" != *CPU* ]]
  pub_set nerd-fonts invalid
  run _layout_definition_evaluate s1 "$PROJECT_ROOT/layouts/definitions/full.sh"
  assert_failure
  assert_output --partial 'nerd-fonts must be on or off'
}

@test "widget inspection resolves font preference and defaults to text" {
  run widget_describe cpu
  assert_success
  assert_output --partial CPU
  pub_set nerd-fonts on
  run widget_describe cpu
  assert_success
  assert_output --partial $'\uf4bc'
  refute_output --partial ']CPU'
}

@test "built-in icon selection performs no per-widget option reads" {
  tmux() { printf 'unexpected option read\n' >&2; return 1; }
  for widget in power online problem; do
    source "$PROJECT_ROOT/layouts/widgets/$widget.sh"
    AIRLINE_WIDGET_RUNTIME="$PROJECT_ROOT/layouts/widgets/$widget"
    run airline_widget_format white black
    assert_success
    refute_output --partial 'unexpected option read'
  done
}
