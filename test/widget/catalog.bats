#!/usr/bin/env bats
load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load
load ../support/helper
setup() { load_session; }
teardown() { :; }
@test "battery reads validated capacity and detects missing hardware" {
  source "$PROJECT_ROOT/layouts/widgets/battery"
  export AIRLINE_POWER_SUPPLY="$BATS_TEST_TMPDIR/power"
  mkdir -p "$AIRLINE_POWER_SUPPLY/BAT0"
  run airline_widget_available; assert_failure 3
  printf 'Battery\n' > "$AIRLINE_POWER_SUPPLY/BAT0/type"
  printf '42\n' > "$AIRLINE_POWER_SUPPLY/BAT0/capacity"
  run airline_widget_available; assert_success
  run airline_widget_sample; assert_success; assert_output 42
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
