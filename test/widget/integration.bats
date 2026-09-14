#!/usr/bin/env bats
load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load
load ../support/helper

setup() { $TMUX -L "$_bats_socket" -f /dev/null new-session -d -s bats; }

@test "layout composes stateless widgets and direct tmux runtime jobs" {
  airline session init
  airline layout use minimal
  left="$(sopt status-left)"
  assert [ -n "$left" ]
  [[ "$left" == *'@airline-'* ]]
  [[ "$left" != *'airline.sh widget run'* ]]
}

@test "widget format changes restore the supplied segment colors" {
  airline session init
  airline layout use minimal
  run airline widget describe prefix
  assert_success
  assert_output --partial 'format       '
  assert_output --partial 'client_prefix'
}

@test "required unavailable widgets report a warning and add no segment content" {
  airline session init
  mkdir "$BATS_TEST_TMPDIR/widgets"
  cat > "$BATS_TEST_TMPDIR/widgets/missing.sh" <<'WIDGET'
#| summary: Missing dependency fixture
airline_widget_available() { return 3; }
airline_widget_format() { printf '%s' "$1"; }
WIDGET
  cat > "$BATS_TEST_TMPDIR/layout" <<'LAYOUT'
airline_layout_configure() { "$1" widget left-out missing; }
LAYOUT
  airline widget register "$BATS_TEST_TMPDIR/widgets"
  airline layout load "$BATS_TEST_TMPDIR/layout"
  assert_output ''
  run airline segment show left-out
  assert_output ''
  run airline problem show airline-widget
  assert_output --partial 'warn'
}
