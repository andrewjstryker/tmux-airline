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

@test "palette load records an absolute path and renders evaluated values" {
  local file="$BATS_TEST_TMPDIR/unregistered palette"
  cp "$PROJECT_ROOT/layouts/palettes/default" "$file"
  printf 'set-option @airline-inner-bg colour55\n' >> "$file"
  layout_palette_load "$file"
  assert_equal "$(prv_get_session s1 palette)" "$file"
  assert_equal "$(cfg_get_session s1 inner-bg)" colour55
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
  source_file_session() { opt_set_session "$1" @airline--stage-inner-bg colour55; return 1; }
  local before rc=0
  before="$(declare -p _FAKE_OPT)"
  layout_palette_describe light > "$BATS_TEST_TMPDIR/description" 2>&1 || rc=$?
  assert_equal "$rc" "$AIRLINE_CONFIG_PALETTE_FAILURE"
  assert_equal "$(declare -p _FAKE_OPT)" "$before"
}

@test "layout describe reports ordered widgets without observing or changing state" {
  mkdir -p "$BATS_TEST_TMPDIR/catalog"
  cat > "$BATS_TEST_TMPDIR/catalog/named" <<'WIDGET'
#| summary: Fixture
airline_widget_format() { printf '%s' "$1"; }
airline_widget_sample() { touch "$BATS_TEST_TMPDIR/observed"; }
WIDGET
  catalog_register s1 widget "$BATS_TEST_TMPDIR/catalog"
  catalog_register s1 layout "$BATS_TEST_TMPDIR/catalog"
  cat > "$BATS_TEST_TMPDIR/catalog/inspect" <<'LAYOUT'
#| summary: Inspect declarations
_LAYOUT_TEST_SOURCED=changed
airline_layout_configure() {
  "$1" segment left-out '#S'
  "$1" widget left-out named 'one two'
  "$1" widget left-out named three
}
LAYOUT
  cfg_set_session s1 segment-left-out old
  prv_set_session s1 layout old
  signal_problem_report s1 airline airline-layout fail 'existing failure'
  local before="$(declare -p _FAKE_OPT)" writes="$_FAKE_WRITES"
  layout_describe inspect > "$BATS_TEST_TMPDIR/description"
  assert_equal "$(declare -p _FAKE_OPT)" "$before"
  assert_equal "$_FAKE_WRITES" "$writes"
  [[ ! -e "$BATS_TEST_TMPDIR/observed" && -z "${_LAYOUT_TEST_SOURCED:-}" && -z "${_RENDERED:-}" ]]
  run cat "$BATS_TEST_TMPDIR/description"
  assert_output --partial 'left-out widget named one two'
  assert_output --partial 'left-out widget named three'
}

@test "layout describe evaluates current environment and resets previous declarations" {
  mkdir "$BATS_TEST_TMPDIR/catalog"
  catalog_register s1 layout "$BATS_TEST_TMPDIR/catalog"
  cat > "$BATS_TEST_TMPDIR/catalog/conditional" <<'LAYOUT'
#| summary: Environment-dependent layout
airline_layout_configure() {
  if [[ "$LAYOUT_TEST_MODE" == full ]]; then
    "$1" segment left-out '#S'
  fi
}
LAYOUT
  LAYOUT_TEST_MODE=full layout_describe conditional > "$BATS_TEST_TMPDIR/full"
  LAYOUT_TEST_MODE=empty layout_describe conditional > "$BATS_TEST_TMPDIR/empty"
  run cat "$BATS_TEST_TMPDIR/full"
  assert_output --partial '#S'
  run cat "$BATS_TEST_TMPDIR/empty"
  assert_line 'left-out     '
  assert_output --partial 'fragments:'
}

@test "layout describe rejects invalid declarations and stdout without changing state" {
  mkdir "$BATS_TEST_TMPDIR/catalog"
  catalog_register s1 layout "$BATS_TEST_TMPDIR/catalog"
  local body before rc
  before="$(declare -p _FAKE_OPT)"
  for body in \
    ':' \
    'airline_layout_configure() { "$1" segment unknown value; }' \
    'airline_layout_configure() { "$1" adapter use missing; }' \
    'airline_layout_configure() { "$1" adapter load /no/such/adapter; }' \
    'airline_layout_configure() { printf unexpected; }' \
    'printf unexpected; airline_layout_configure() { :; }' \
    'airline_layout_configure() { airline segment show; }' \
    'airline_layout_configure() { return 7; }'; do
    printf '#| summary: Invalid fixture\n%s\n' "$body" > "$BATS_TEST_TMPDIR/catalog/invalid"
    rc=0
    layout_describe invalid > "$BATS_TEST_TMPDIR/description" 2>&1 || rc=$?
    assert_equal "$rc" "$AIRLINE_CONFIG_LAYOUT_FAILURE"
    assert_equal "$(declare -p _FAKE_OPT)" "$before"
    run cat "$BATS_TEST_TMPDIR/description"
    assert_output --partial "airline: layout 'invalid'"
    refute_output --partial 'segments:'
    refute_output --partial 'unexpected'
  done
}
