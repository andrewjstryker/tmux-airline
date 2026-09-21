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
  cp "$PROJECT_ROOT/layouts/palettes/default.conf" "$file"
  printf 'set-option @airline-palette-inner-bg colour55\n' >> "$file"
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
  printf '#| summary: Incomplete\nset-option @airline-palette-inner-bg colour55\n' > "$BATS_TEST_TMPDIR/catalog/broken.conf"
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
  printf 'set-option @airline-palette-inner-bg colour55\n' > "$file"
  layout_palette_load "$file" || rc=$?
  assert_equal "$rc" "$AIRLINE_CONFIG_PALETTE_FAILURE"
  assert_equal "$(cfg_get_session s1 inner-bg)" "$prior"
  assert_equal "$(prv_get_session s1 palette)" default
  [[ -z "${_RENDERED:-}" ]]
  run stage_has_session s1 inner-bg
  assert_failure
  run signal_problem_show airline airline-palette
  assert_output --partial 'incomplete or could not be evaluated'
  cp "$PROJECT_ROOT/layouts/palettes/light.conf" "$file"
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
  cat > "$BATS_TEST_TMPDIR/catalog/named.sh" <<'WIDGET'
#| summary: Fixture
airline_widget_format() { printf '%s' "$1"; }
WIDGET
  catalog_register s1 widget "$BATS_TEST_TMPDIR/catalog"
  catalog_register s1 layout "$BATS_TEST_TMPDIR/catalog"
  cat > "$BATS_TEST_TMPDIR/catalog/inspect.sh" <<'LAYOUT'
#| summary: Inspect declarations
_LAYOUT_TEST_SOURCED=changed
airline_layout_configure() {
  "$1" segment left-out '#S#{E:@airline--widget-named}#{E:@airline--widget-named}'
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
  assert_output --partial 'left-out widget named #[push-default]default'
  assert_output --partial '#S#{E:@airline--widget-named}#{E:@airline--widget-named}'
}

@test "layout describe evaluates current environment and resets previous declarations" {
  mkdir "$BATS_TEST_TMPDIR/catalog"
  catalog_register s1 layout "$BATS_TEST_TMPDIR/catalog"
  cat > "$BATS_TEST_TMPDIR/catalog/conditional.sh" <<'LAYOUT'
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
    printf '#| summary: Invalid fixture\n%s\n' "$body" > "$BATS_TEST_TMPDIR/catalog/invalid.sh"
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

@test "shipped layouts retain host-session, online, prefix, CPU, and power positions" {
  for name in full; do
    source "$PROJECT_ROOT/layouts/definitions/$name.sh"
    declare_part() { printf '%s\n' "$*"; }
    run airline_layout_configure declare_part
    assert_success
    assert_line --index 0 'segment left-out #h:#S'
    assert_line --index 1 'segment left-mid #{E:@airline--widget-online}'
    assert_line --index 2 'segment right-in #{E:@airline--widget-prefix}'
    assert_line --index 3 'segment right-mid #{E:@airline--widget-cpu}'
    assert_line --index 4 'segment right-out %Y-%m-%d %H:%M #{E:@airline--widget-battery}#{E:@airline--widget-power} #{E:@airline--widget-problem}'
  done
}

@test "dependency-free default gives host the outer-left segment and session the middle" {
  source "$PROJECT_ROOT/layouts/definitions/default.sh"
  declare_part() { printf '%s\n' "$*"; }
  run airline_layout_configure declare_part
  assert_success
  assert_line --index 0 'segment left-out #h'
  assert_line --index 1 'segment left-mid #S'
  assert_line --index 2 'segment right-out %Y-%m-%d %H:%M #{E:@airline--widget-problem}'
}

@test "segment replacements compile only final content and widgets" {
  mkdir "$BATS_TEST_TMPDIR/catalog"
  catalog_register s1 layout "$BATS_TEST_TMPDIR/catalog"
  cat > "$BATS_TEST_TMPDIR/catalog/replaced.sh" <<'LAYOUT'
#| summary: Replacement fixture
airline_layout_configure() {
  "$1" segment left-out '#{E:@airline--widget-does-not-exist}'
  "$1" segment right-out '#{E:@airline--widget-also-missing}'
  "$1" segment left-out 'final #S #{?client_prefix,yes,no} ##{E:@airline--widget-literal}'
  "$1" segment right-out ''
}
LAYOUT
  run layout_describe replaced
  assert_success
  assert_output --partial 'final #S #{?client_prefix,yes,no} ##{E:@airline--widget-literal}'
  assert_line 'right-out    '
  refute_output --partial 'does-not-exist'
  refute_output --partial 'also-missing'
}

@test "native widget references remain intact and configuration comes from tmux options" {
  mkdir "$BATS_TEST_TMPDIR/catalog"
  catalog_register s1 layout "$BATS_TEST_TMPDIR/catalog"
  catalog_register s1 widget "$BATS_TEST_TMPDIR/catalog"
  cat > "$BATS_TEST_TMPDIR/catalog/echo.sh" <<'WIDGET'
#| summary: Option fixture
airline_widget_format() {
  local text
  text="$(tmux show-option -gqv @airline-widget-echo-text)" || return
  printf '%s' "${text:-fallback}"
}
WIDGET
  cat > "$BATS_TEST_TMPDIR/catalog/native.sh" <<'LAYOUT'
#| summary: Native format fixture
airline_layout_configure() {
  "$1" segment left-out 'before #S #{?client_prefix,#{E:@airline--widget-echo},idle} ##{E:@airline--widget-absent} after'
  "$1" segment right-out '#{E:@airline--widget-echo}'
}
LAYOUT
  pub_set widget-echo-text 'two words $HOME $(touch sentinel)'
  cd "$BATS_TEST_TMPDIR"
  layout_use native
  run cfg_get_session s1 segment-left-out
  assert_output --partial 'before #S #{?client_prefix,#{E:@airline--widget-echo},idle} ##{E:@airline--widget-absent} after'
  run prv_get_session s1 widget-echo
  assert_output '#[push-default]two words $HOME $(touch sentinel)#[default]#[pop-default]'
  run signal_problem_show airline-widget
  assert_output ''
  [[ ! -e sentinel ]]

  # Removing one placement preserves the shared expression for the other slot.
  widget_retire_session s1 left-out
  run prv_get_session s1 widget-echo
  assert_output --partial 'two words'
  widget_retire_session s1 right-out
  run prv_get_session s1 widget-echo
  assert_output ''
}

@test "widget describe rejects argument overrides" {
  run widget_describe prefix --show-copy off
  assert_failure
  assert_output --partial 'need exactly one <widget>'
}

@test "broken embedded widgets report problems while neighboring content renders and recover on reload" {
  mkdir "$BATS_TEST_TMPDIR/catalog"
  catalog_register s1 layout "$BATS_TEST_TMPDIR/catalog"
  catalog_register s1 widget "$BATS_TEST_TMPDIR/catalog"
  cat > "$BATS_TEST_TMPDIR/catalog/degraded.sh" <<'LAYOUT'
#| summary: Recoverable widget failure
airline_layout_configure() {
  "$1" segment left-out 'before #{E:@airline--widget-fixture} after'
}
LAYOUT
  run layout_describe degraded
  assert_success
  assert_output --partial 'before #{E:@airline--widget-fixture} after'
  assert_output --partial 'fixture widget was not found'
  run signal_problem_show airline-widget
  assert_output ''

  layout_use degraded
  run signal_problem_show airline-widget
  assert_output --partial fail
  assert_output --partial 'fixture widget was not found'

  cat > "$BATS_TEST_TMPDIR/catalog/fixture.sh" <<'WIDGET'
#| summary: Broken format
airline_widget_format() { printf '\n\n'; }
WIDGET
  layout_use degraded
  run signal_problem_show airline-widget
  assert_output --partial 'could not be evaluated'
  run cfg_get_session s1 segment-left-out
  assert_output --partial 'before #{E:@airline--widget-fixture} after'

  cat > "$BATS_TEST_TMPDIR/catalog/fixture.sh" <<'WIDGET'
#| summary: Recovered widget
airline_widget_format() { printf 'working'; }
WIDGET
  layout_use degraded
  run cfg_get_session s1 segment-left-out
  assert_output --partial 'before #{E:@airline--widget-fixture} after'
  run prv_get_session s1 widget-fixture
  assert_output '#[push-default]working#[default]#[pop-default]'
  run signal_problem_show airline-widget
  assert_output ''
  run signal_problem_show --all airline-widget s1-left-out-1-fixture
  assert_output --partial resolved
}
