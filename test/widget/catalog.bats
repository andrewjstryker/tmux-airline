#!/usr/bin/env bats
load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load
load ../support/helper
setup() { load_session; }
teardown() { :; }

@test "widget publication redraws only when the reading changes" {
  local id=1-2-3-4
  coll_register session s1 widgets "$id"
  _widget_publish s1 "$id" 42
  assert_equal "$_FAKE_REDRAWS" 1
  local writes="$_FAKE_WRITES"
  _widget_publish s1 "$id" 42
  assert_equal "$_FAKE_REDRAWS" 1
  assert_equal "$_FAKE_WRITES" "$writes"
  _widget_publish s1 "$id" 43
  assert_equal "$_FAKE_REDRAWS" 2
  assert_equal "$(prv_get_session s1 "widget-$id-value")" 43
  _widget_publish s1 "$id" ''
  assert_equal "$_FAKE_REDRAWS" 3
  _widget_publish s1 "$id" ''
  assert_equal "$_FAKE_REDRAWS" 3
  assert_equal "$(prv_get_session s1 "widget-$id-value")" ''
}

@test "retired widgets and failed publications do not redraw" {
  local id=1-2-3-4 rc=0
  _widget_publish s1 "$id" 42 || rc=$?
  assert_equal "$rc" 3
  assert_equal "$_FAKE_REDRAWS" 0
  coll_register session s1 widgets "$id"
  _opt_write() { return 72; }
  rc=0
  _widget_publish s1 "$id" 42 || rc=$?
  assert_equal "$rc" 72
  assert_equal "$_FAKE_REDRAWS" 0
  assert_equal "$(prv_get_session s1 "widget-$id-value")" ''
}

@test "battery reads validated capacity and detects missing hardware" {
  source "$PROJECT_ROOT/layouts/widgets/battery"
  export AIRLINE_POWER_SUPPLY="$BATS_TEST_TMPDIR/power"
  mkdir -p "$AIRLINE_POWER_SUPPLY/BAT0"
  run airline_widget_available; assert_failure 3
  printf 'Battery\n' > "$AIRLINE_POWER_SUPPLY/BAT0/type"
  printf '42\n' > "$AIRLINE_POWER_SUPPLY/BAT0/capacity"
  run airline_widget_available; assert_success
  run airline_widget_sample; assert_success; assert_output '42:unknown'
  for state in 'Charging:charging' 'Discharging:discharging' 'Full:full' 'Not charging:attached' 'Unknown:unknown'; do
    printf '%s\n' "${state%:*}" > "$AIRLINE_POWER_SUPPLY/BAT0/status"
    run airline_widget_sample; assert_success; assert_output "42:${state##*:}"
  done
  printf '101\n' > "$AIRLINE_POWER_SUPPLY/BAT0/capacity"
  run airline_widget_sample; assert_failure
}
@test "online distinguishes unreachable hosts from failed probes and preserves host argv" {
  source "$PROJECT_ROOT/layouts/widgets/online"
  ping() { [[ "$*" == '-n -c 1 -W 1 example.com' ]] || return 9; return "$PING_RC"; }
  PING_RC=0
  run airline_widget_sample --host example.com; assert_success; assert_output 1
  PING_RC=1
  run airline_widget_sample --host example.com; assert_success; assert_output 0
  PING_RC=2
  run airline_widget_sample --host example.com; assert_failure 2
  run airline_widget_format --host '-bad'; assert_failure
}
@test "prefix uses only native client state and public palette expressions" {
  run widget_format s1 1-2-3-4 "$PROJECT_ROOT/layouts/widgets/prefix"
  assert_success; assert_output --partial '#{@airline-active}'
  assert_output --partial 'client_prefix'; refute_output --partial '#('
  run widget_format s1 1-2-3-4 "$PROJECT_ROOT/layouts/widgets/prefix" unexpected
  assert_failure 2
}

@test "format contract rejects controls, excessive output, layout directives, and invalid budgets" {
  file="$BATS_TEST_TMPDIR/widget"
  for body in \
    "printf 'bad\\000format'" \
    "printf 'bad\\nformat'" \
    "printf 'bad\\n\\n'" \
    "printf '#[fg=red,align=right]bad'" \
    "printf '%09000d' 0"; do
    printf '#| summary: Invalid format\nairline_widget_format() { %s; }\n' "$body" > "$file"
    run widget_format s1 1-2-3-4 "$file"
    assert_failure 2
  done
  printf '#| summary: Invalid budget\n#| interval: 1\n#| timeout: 2\nairline_widget_format() { :; }\n' > "$file"
  run widget_format s1 1-2-3-4 "$file"
  assert_failure 2
}

@test "only the availability check may classify a widget as unavailable" {
  file="$BATS_TEST_TMPDIR/widget"
  for body in 'return 3' 'exit 3' 'airline_widget_format() { return 3; }'; do
    printf '#| summary: Invalid source or format\n%s\n' "$body" > "$file"
    run widget_format s1 1-2-3-4 "$file"
    assert_failure 2
  done
  printf '#| summary: Unavailable\nairline_widget_format() { :; }\nairline_widget_available() { return 3; }\n' > "$file"
  run widget_format s1 1-2-3-4 "$file"
  assert_failure 3
}

@test "widget defaults resolve global policy then placement overrides without splitting text" {
  local -a args=()
  pub_set widget-cpu-warn 50
  pub_set widget-cpu-low-icon 'a b'
  widget_arguments cpu "$PROJECT_ROOT/layouts/widgets/cpu" args --warn 65
  assert_equal "${args[1]}" 65
  assert_equal "${args[9]}" 'a b'
  run widget_format s1 1-2-3-4 "$PROJECT_ROOT/layouts/widgets/cpu" "${args[@]}"
  assert_success
  assert_output --partial 'a b'
  pub_set widget-cpu-warn broken
  widget_arguments cpu "$PROJECT_ROOT/layouts/widgets/cpu" args
  run widget_format s1 1-2-3-4 "$PROJECT_ROOT/layouts/widgets/cpu" "${args[@]}"
  assert_failure 2
  run widget_arguments cpu "$PROJECT_ROOT/layouts/widgets/cpu" args --unknown value
  assert_failure 2
  run widget_arguments cpu "$PROJECT_ROOT/layouts/widgets/cpu" args --warn
  assert_failure 2
  run widget_arguments cpu "$PROJECT_ROOT/layouts/widgets/cpu" args -- value
  assert_failure 2
}

@test "widget policy validates meter order, display modes, badges, and ping timeouts" {
  for spec in 'cpu --meter-medium 90 --meter-high 80' 'cpu --meter-high 101' 'battery --display invalid' 'prefix --show-copy yes' 'online --timeout 0' 'online --timeout 9'; do
    read -r -a args <<< "$spec"
    run widget_format s1 1-2-3-4 "$PROJECT_ROOT/layouts/widgets/${args[0]}" "${args[@]:1}"
    assert_failure 2
  done
  source "$PROJECT_ROOT/layouts/widgets/online"
  ping() { [[ "$*" == '-n -c 1 -W 3 example.com' ]]; }
  run airline_widget_sample --host example.com --timeout 3
  assert_success; assert_output 1
}
