#!/usr/bin/env bats

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load
load ../support/helper

setup() {
  load_session
  catalog_register s1 palette "$PROJECT_ROOT/layouts/palettes"
  _palette_select_unlocked s1 default
  render() { _RENDERED="$1"; }
}
teardown() { :; }

@test "palette describe evaluates all roles without changing configuration or problem state" {
  local before element
  signal_problem_report s1 airline airline-palette fail 'existing failure'
  before="$(declare -p _FAKE_OPT)"
  layout_palette_describe light > "$BATS_TEST_TMPDIR/description"
  assert_equal "$(declare -p _FAKE_OPT)" "$before"
  [[ -z "${_RENDERED:-}" ]]
  run cat "$BATS_TEST_TMPDIR/description"
  assert_success
  assert_output --partial 'name         light'
  for element in "${AIRLINE_PALETTE_ELEMENTS[@]}"; do
    assert_output --partial "$element"
  done
  local described
  described="$(awk '$1 == "inner-bg" {print $2}' "$BATS_TEST_TMPDIR/description")"
  layout_palette_use light
  assert_equal "$(cfg_get_session s1 inner-bg)" "$described"
}

@test "palette load records an absolute path and repaints adapters with evaluated values" {
  local file="$BATS_TEST_TMPDIR/unregistered palette"
  cp "$PROJECT_ROOT/layouts/palettes/default" "$file"
  printf 'set-option @airline-inner-bg colour55\n' >> "$file"
  coll_set session s1 adapters test load "$BATS_TEST_TMPDIR/adapter"
  touch "$BATS_TEST_TMPDIR/adapter"
  _source_adapter() { _ADAPTER_COLOR="$(cfg_get_session "$1" inner-bg)"; }
  layout_palette_load "$file"
  assert_equal "$(prv_get_session s1 palette)" "$file"
  assert_equal "$(cfg_get_session s1 inner-bg)" colour55
  assert_equal "$_ADAPTER_COLOR" colour55
  assert_equal "$_RENDERED" s1
  run stage_has_session s1 inner-bg
  assert_failure
  run catalog_resolve s1 palette 'unregistered palette'
  assert_output ''
  layout_palette_use light
  assert_equal "$(prv_get_session s1 palette)" light
}

@test "incomplete palette inspection cleans staging and cannot commit or recover a problem" {
  mkdir "$BATS_TEST_TMPDIR/catalog"
  printf '#| summary: Incomplete\nset-option @airline-inner-bg colour55\n' > "$BATS_TEST_TMPDIR/catalog/broken"
  catalog_register s1 palette "$BATS_TEST_TMPDIR/catalog"
  local before rc=0
  before="$(declare -p _FAKE_OPT)"
  layout_palette_describe broken > "$BATS_TEST_TMPDIR/description" 2>&1 || rc=$?
  assert_equal "$rc" "$AIRLINE_CONFIG_PALETTE_FAILURE"
  assert_equal "$(declare -p _FAKE_OPT)" "$before"
  run cat "$BATS_TEST_TMPDIR/description"
  assert_output --partial "palette 'broken' is incomplete"
  refute_output --partial 'name '
}

@test "palette load failure preserves selected roles and later success recovers its diagnostic" {
  local file="$BATS_TEST_TMPDIR/broken" prior rc=0
  prior="$(cfg_get_session s1 inner-bg)"
  printf 'set-option @airline-inner-bg colour55\n' > "$file"
  layout_palette_load "$file" || rc=$?
  assert_equal "$rc" "$AIRLINE_CONFIG_PALETTE_FAILURE"
  assert_equal "$(cfg_get_session s1 inner-bg)" "$prior"
  assert_equal "$(prv_get_session s1 palette)" default
  [[ -z "${_RENDERED:-}" ]]
  run stage_has_session s1 inner-bg
  assert_failure
  run signal_problem_show airline airline-palette
  assert_output --partial 'incomplete or could not be evaluated'
  cp "$PROJECT_ROOT/layouts/palettes/light" "$file"
  layout_palette_load "$file"
  run signal_problem_show airline airline-palette
  assert_output ''
}

@test "palette source failure cleans partial staging without changing the selected palette" {
  source_file_session() { opt_set_session "$1" @airline-inner-bg colour55; return 1; }
  local before rc=0
  before="$(declare -p _FAKE_OPT)"
  layout_palette_describe light > "$BATS_TEST_TMPDIR/description" 2>&1 || rc=$?
  assert_equal "$rc" "$AIRLINE_CONFIG_PALETTE_FAILURE"
  assert_equal "$(declare -p _FAKE_OPT)" "$before"
}
