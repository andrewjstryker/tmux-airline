#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load
load helper

# Helper: point _is_installed at a temp dir holding the named fake plugins.
fake_plugin_dir() {
  _fake_plugins="$(mktemp -d)"
  CURRENT_DIR="$_fake_plugins/tmux-airline"
  mkdir -p "$CURRENT_DIR"
  export XDG_CONFIG_HOME="$_fake_plugins"
  for plugin in "$@"; do mkdir -p "$_fake_plugins/$plugin"; done
}

# --- default segments + powerline tiers (composed by main) ------------------

@test "main registers the default segments" {
  init_theme
  main
  run airline_segment_list
  assert_output --partial "online"
  assert_output --partial "host"
  assert_output --partial "prefix"
  assert_output --partial "cpu"
  assert_output --partial "date"
}

@test "status-left steps outer -> middle -> inner across the default segments" {
  init_theme
  main
  run get_option status-left
  assert_output --partial "bg=${THEME[outer-bg]}"   # online
  assert_output --partial "bg=${THEME[middle-bg]}"  # host
  assert_output --partial "${THEME[inner-bg]}"      # chevron into the window list
}

@test "status-right includes the date widget by default" {
  init_theme
  main
  run get_option status-right
  assert_output --partial "%Y-%m-%d %H:%M"
}

# --- CLI: register / order / unregister -------------------------------------

@test "segment register orders by ascending priority" {
  airline segment register beta  --side right --priority 30 --format 'BETA'
  airline segment register alpha --side right --priority 10 --format 'ALPHA'
  run get_option status-right
  [[ "$output" == *"ALPHA"*"BETA"* ]]
}

@test "segment register places content on the requested side" {
  airline segment register note --side left --tier middle --format 'NOTE'
  run get_option status-left
  assert_output --partial "NOTE"
}

@test "segment register is idempotent (no duplicate in the roster)" {
  airline segment register note --side left --format 'NOTE'
  airline segment register note --side left --format 'NOTE2'
  run airline segment list
  assert_equal "$(printf '%s\n' "$output" | grep -c '^note')" "1"
}

@test "segment unregister removes it from the bar" {
  airline segment register note --side right --format 'NOTE'
  airline segment unregister note
  run get_option status-right
  refute_output --partial "NOTE"
}

@test "segment list reports side, priority, and tier" {
  airline segment register note --side right --priority 15 --tier inner --format 'NOTE'
  run airline segment list
  assert_output --partial "note	side=right	prio=15	tier=inner"
}

# --- CLI: tier derived from position (the powerline gradient) ---------------

@test "segment register derives tier from stack depth when --tier is omitted" {
  # right stack, center -> edge: inner, middle, outer
  airline segment register near --side right --priority 10 --format 'N'
  airline segment register mid  --side right --priority 20 --format 'M'
  airline segment register edge --side right --priority 30 --format 'E'
  run airline segment list
  assert_output --partial "near	side=right	prio=10	tier=inner"
  assert_output --partial "mid	side=right	prio=20	tier=middle"
  assert_output --partial "edge	side=right	prio=30	tier=outer"
}

@test "segment register --tier overrides the derived tier" {
  airline segment register a --side left --priority 10 --format 'A'             # derives outer
  airline segment register b --side left --priority 20 --tier inner --format 'B' # derives middle
  run airline segment list
  assert_output --partial "b	side=left	prio=20	tier=inner"
}

# --- CLI: validation --------------------------------------------------------

@test "segment register requires a side" {
  run airline segment register note --format 'NOTE'
  assert_failure
  assert_output --partial "requires --side"
}

@test "segment register requires content" {
  run airline segment register note --side right
  assert_failure
  assert_output --partial "requires --format"
}

@test "segment register rejects a bad side" {
  run airline segment register note --side up --format 'NOTE'
  assert_failure
  assert_output --partial "side must be"
}

@test "segment register rejects a bad tier" {
  run airline segment register note --side right --tier deep --format 'NOTE'
  assert_failure
  assert_output --partial "tier must be"
}

@test "segment register rejects a non-integer priority" {
  run airline segment register note --side right --priority soon --format 'NOTE'
  assert_failure
  assert_output --partial "priority"
}

# --- built-in widget content via the generators -----------------------------

@test "the default cpu segment renders the cpu widget when tmux-cpu is installed" {
  init_theme
  main
  fake_plugin_dir tmux-cpu
  run _build_status_right
  assert_output --partial "cpu_icon"
  rm -rf "$_fake_plugins"
}

@test "the default cpu segment is empty when tmux-cpu is absent" {
  init_theme
  main
  fake_plugin_dir
  run _build_status_right
  refute_output --partial "cpu_icon"
  rm -rf "$_fake_plugins"
}
