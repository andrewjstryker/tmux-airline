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

# The companion reads the ledger through the public CLI, so the reduction it
# reports is the one `problem show` publishes, not a private option.
@test "problem companion reduces the ledger and its format presents live values" {
  local level expected format pane
  airline session init
  # tmux gives a #() job its server context; the seam supplies it here.
  pane="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{pane_id}')"
  companion() {
    run env TMUX_PANE="$pane" AIRLINE_TMUX="$TMUX -L $_bats_socket" \
      "$PROJECT_ROOT/layouts/widgets/problem"
  }
  source "$PROJECT_ROOT/layouts/widgets/problem.sh"
  widget_runtime() { printf '%s' '#{@problem-test-value}'; }
  format="$(airline_widget_format white black)"
  # session init publishes the effective palette per session, so pin the two
  # roles under test at that same scope.
  $TMUX -L "$_bats_socket" set-option -t bats @airline-palette-alert yellow
  $TMUX -L "$_bats_socket" set-option -t bats @airline-palette-stress red

  companion
  assert_success
  assert_output ""

  airline problem set example-cpu sensors warn "sensors missing"
  companion
  assert_output warn
  # A second, worse claim reduces past the first; claim rows never contribute.
  airline problem set example-battery query fail "battery query timed out"
  companion
  assert_output fail

  for level in '' warn fail; do
    $TMUX -L "$_bats_socket" set-option -g @problem-test-value "$level"
    case "$level" in
      '') expected='#[fg=white,bg=black]' ;;
      warn) expected='#[fg=yellow]#[bg=black]△#[noblink] #[fg=white,bg=black]' ;;
      fail) expected='#[fg=red]#[bg=black]#[blink]▲#[noblink] #[fg=white,bg=black]' ;;
    esac
    run $TMUX -L "$_bats_socket" display-message -p "$format"
    assert_success
    assert_output "$expected"
  done
}

@test "required unavailable widgets report a warning and add no segment content" {
  airline session init
  mkdir "$BATS_TEST_TMPDIR/widgets"
  cat > "$BATS_TEST_TMPDIR/widgets/missing.sh" <<'WIDGET'
#| summary: Missing dependency fixture
airline_widget_available() { return 3; }
airline_widget_format() { printf '%s' "$1"; }
WIDGET
  mkdir "$BATS_TEST_TMPDIR/layouts"
  cat > "$BATS_TEST_TMPDIR/layouts/missing.sh" <<'LAYOUT'
#| summary: Layout with an unavailable required widget
airline_layout_configure() { "$1" segment left-out "#{E:@airline--widget-missing}"; }
LAYOUT
  airline widget register "$BATS_TEST_TMPDIR/widgets"
  airline layout register "$BATS_TEST_TMPDIR/layouts"

  # Inspection may evaluate a trusted widget definition, but it must not publish
  # the unavailable capability claim before that widget is part of a layout.
  run airline layout describe missing
  assert_success
  run airline problem show --all airline-widget missing
  assert_output ''

  run airline layout use missing
  assert_success
  assert_output ''
  run airline segment show left-out
  assert_output --partial '#{E:@airline--widget-missing}'
  run sopt @airline--widget-missing
  assert_output ''
  run airline problem show airline-widget
  assert_output --partial 'warn'
  widget_id="$(awk '$1 == "airline-widget" { print $2; exit }' <<< "$output")"
  [[ -n "$widget_id" ]]

  # Availability is checked again on reload; the same placement recovers its claim.
  sed -i 's/return 3/return 0/' "$BATS_TEST_TMPDIR/widgets/missing.sh"
  airline layout use missing
  run airline problem show airline-widget
  assert_output ''
  run airline problem show --all airline-widget "$widget_id"
  assert_output --partial 'resolved'

  # A repeated failure reopens that claim instead of accumulating new problems.
  sed -i 's/return 0/return 3/' "$BATS_TEST_TMPDIR/widgets/missing.sh"
  airline layout use missing
  run airline problem show airline-widget
  assert_output --partial "$widget_id"
  assert_output --partial 'warn'

  # Replacing the layout retires both the widget and its active capability claim.
  airline layout use minimal
  run airline problem show airline-widget
  assert_output ''
  run airline problem show --all airline-widget "$widget_id"
  assert_output --partial 'closed'
}

@test "widget-owned public options determine private expressions and recover invalid configuration" {
  airline session init
  $TMUX -L "$_bats_socket" set-option -g @airline-widget-cpu-medium 72
  $TMUX -L "$_bats_socket" set-option -g @airline-widget-cpu-high 91
  $TMUX -L "$_bats_socket" set-option -g @airline-widget-prefix-show-copy off
  airline layout use full
  run sopt @airline--widget-cpu
  assert_output --partial ',72}'
  assert_output --partial ',91}'
  run sopt @airline--widget-prefix
  refute_output --partial '[Copy]'
  assert_output --partial '[Sync]'

  # Invalid options belong to the widget; the host only publishes its failure.
  $TMUX -L "$_bats_socket" set-option -g @airline-widget-cpu-medium 99
  airline layout use full
  run sopt @airline--widget-cpu
  assert_output ''
  run airline problem show airline-widget
  assert_output --partial 'cpu widget could not be evaluated'
  widget_id="$(awk '$1 == "airline-widget" && /cpu widget/ { print $2; exit }' <<< "$output")"
  [[ -n "$widget_id" ]]

  $TMUX -L "$_bats_socket" set-option -g @airline-widget-cpu-medium 72
  airline layout use full
  run airline problem show airline-widget "$widget_id"
  assert_output ''
  run airline problem show --all airline-widget "$widget_id"
  assert_output --partial resolved
  run sopt @airline-widget-cpu-medium -g
  assert_output 72
}
