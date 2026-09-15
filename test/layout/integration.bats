#!/usr/bin/env bats

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load
load ../support/helper

# Executable layout behavior through the real CLI and an isolated tmux server.
# These drive the CLI as a subprocess (the `airline()` helper points it at the server
# via AIRLINE_TMUX), so they exercise the same path production uses.
#
# A clean server (-f /dev/null) so `init`'s default-seeding isn't perturbed by the
# developer's own ~/.tmux.conf (which may already configure airline).

setup() {
  $TMUX -L "$_bats_socket" -f /dev/null new-session -d -s bats
}

write_layout() {   # <path> <configure-body>
  printf '#!/usr/bin/env bash\nairline_layout_configure () {\n  local declare="$1"\n%s\n}\n' \
    "$2" > "$1"
}

# --- init -------------------------------------------------------------------
@test "palette catalog selection, validation, recovery, and provenance compose" {
  airline session init
  mkdir -p "$BATS_TMPDIR/mypalettes"
  cp "$PROJECT_ROOT/layouts/palettes/default.conf" "$BATS_TMPDIR/mypalettes/custom.conf"
  printf 'set @airline-palette-inner-bg colour55\n' >> "$BATS_TMPDIR/mypalettes/custom.conf"
  airline palette register "$BATS_TMPDIR/mypalettes"
  airline palette use custom
  run airline palette show inner-bg
  assert_output "colour55"
  run sopt status-style
  assert_output --partial "bg=colour55"     # rendered with the new color
  run airline palette use no-such-palette-xyz
  assert_failure
  run airline palette use /etc/passwd        # a path is not a bare name
  assert_failure
  session="$($TMUX -L "$_bats_socket" display-message -p '#{session_id}')"
  mkdir -p "$BATS_TMPDIR/incomplete"
  printf 'set @airline-palette-inner-bg colour55\n' > "$BATS_TMPDIR/incomplete/broken.conf"
  airline palette register "$BATS_TMPDIR/incomplete"

  run airline palette use broken
  assert_failure
  assert_output --partial "is incomplete"
  run airline palette show name
  assert_output custom
  run airline problem show airline airline-palette
  assert_output --partial "palette 'broken' is incomplete or could not be evaluated"

  cp "$PROJECT_ROOT/layouts/palettes/default.conf" "$BATS_TMPDIR/incomplete/broken.conf"
  airline palette use broken
  run airline problem show airline airline-palette
  assert_output ""
  run airline palette use light       # a shipped bare name → found in layouts/palettes
  assert_success

  mkdir -p "$BATS_TMPDIR/shadow"
  cp "$PROJECT_ROOT/layouts/palettes/default.conf" "$BATS_TMPDIR/shadow/dark.conf"
  printf 'set @airline-palette-inner-bg colour42\n' >> "$BATS_TMPDIR/shadow/dark.conf"   # same name as shipped
  airline palette register "$BATS_TMPDIR/shadow"
  airline palette use dark
  run airline palette show inner-bg
  assert_output "colour42"            # the registered dark won, not the shipped colour234
  airline palette use light
  run sopt @airline--palette
  assert_output "light"
}

@test "palette load and describe share native evaluation without committing inspection" {
  airline session init
  mkdir -p "$BATS_TEST_TMPDIR/palettes"
  palette_file="$BATS_TEST_TMPDIR/palettes/custom palette.conf"
  cp "$PROJECT_ROOT/layouts/palettes/default.conf" "$palette_file"
  printf 'set-option @airline-palette-inner-bg colour55\n' >> "$palette_file"
  airline palette register "$BATS_TEST_TMPDIR/palettes"
  prior="$(airline palette show inner-bg)"
  prior_name="$(airline palette show name)"
  run airline palette describe 'custom palette'
  assert_success
  assert_output --partial 'inner-bg     colour55'
  run airline palette show inner-bg
  assert_output "$prior"
  run airline palette show name
  assert_output "$prior_name"
  run sopt @airline-palette-inner-bg
  assert_output "$prior"

  airline palette load "$palette_file"
  run airline palette show name
  assert_output "$palette_file"
  run airline palette show inner-bg
  assert_output colour55
  run sopt @airline-palette-inner-bg
  assert_output colour55

  printf '#| summary: Broken source\nset-option @airline-palette-inner-bg colour99\nnot-a-tmux-command\n' > "$palette_file"
  run airline palette describe 'custom palette'
  assert_failure 70
  run airline palette show inner-bg
  assert_output colour55
  run sopt @airline-palette-inner-bg
  assert_output colour55
  run airline problem show airline airline-palette
  assert_output ''
}

# --- palette / segment (static config nouns: read-only `show`, written via set -g) --

@test "manual palette and segment inputs preserve clear provenance and show contracts" {
  airline session init
  $TMUX -L "$_bats_socket" set -t bats @airline-palette-active colour201
  airline session apply
  run sopt window-status-current-format
  assert_output --partial "colour201"   # rendered into the bar (active highlight)
  airline palette use light
  $TMUX -L "$_bats_socket" set -t bats @airline-palette-active colour201
  airline session apply
  run airline palette show active
  assert_output colour201
  run airline palette show name
  assert_output ""

  $TMUX -L "$_bats_socket" set -u -t bats @airline-palette-active
  airline session apply
  run airline palette show active
  assert_output colour201

  airline palette use light
  run airline palette show active
  assert_output colour136
  run airline palette show name
  assert_output light
  airline palette use light
  $TMUX -L "$_bats_socket" set -t bats @airline-palette-active colour201

  run airline palette show active
  assert_output colour201             # public reads reflect direct session writes
  run airline palette show name
  assert_output light

  airline layout use full
  run airline palette show active
  assert_output colour201
  run airline palette show name
  assert_output ""
  run airline layout show name
  assert_output full
  airline layout use full
  $TMUX -L "$_bats_socket" set -g @airline-segment-right-out MANUAL
  airline session apply
  run airline segment show right-out
  assert_output MANUAL
  run airline layout show name
  assert_output ""

  $TMUX -L "$_bats_socket" set -gu @airline-segment-right-out
  airline session apply
  run airline segment show right-out
  assert_output MANUAL
  $TMUX -L "$_bats_socket" set -t bats @airline-palette-active colour201
  airline session apply
  run airline palette show active
  assert_output "colour201"
  run airline palette show
  assert_output --partial "active"
  assert_output --partial "inner-bg"
  run airline palette show bogus
  assert_failure

  $TMUX -L "$_bats_socket" set -g @airline-segment-left-out "#H"   # the only write path
  airline session apply
  run airline segment show left-out
  assert_output "#H"
  run airline segment show middle
  assert_failure
}

@test "widget catalog placement and layout replacement compose without plugin configuration" {
  airline session init
  run airline adapter use cpu
  assert_failure; assert_output --partial 'adapter was removed'
  run airline widget list
  assert_line battery; assert_line online; assert_line power; assert_line prefix
  mkdir -p "$BATS_TEST_TMPDIR/widgets"
  write_layout "$BATS_TEST_TMPDIR/widgets/withprefix.sh" '  "$declare" widget left-out prefix'
  write_layout "$BATS_TEST_TMPDIR/widgets/bare.sh" '  "$declare" segment left-out "#S"'
  airline layout register "$BATS_TEST_TMPDIR/widgets"
  airline layout use withprefix
  [[ -n "$(sopt @airline--widgets)" ]]
  run sopt @cpu_low_fg_color
  assert_output ''
  airline layout use bare
  run sopt @airline--widgets
  assert_output ''
  run airline palette list
  assert_line default; assert_line dark
  run airline layout list
  assert_line full; assert_line minimal
}

# --- layout (validated Bash declaration, captured into private state) --------

@test "layout composition preserves committed state and replaces prior declarations" {
  airline session init
  $TMUX -L "$_bats_socket" set -t bats @airline-segment-left-out "SCRATCH"
  airline layout use default
  run airline segment show left-out
  assert_output --partial "#h"                   # host owns the outer-left slot
  run airline segment show left-mid
  assert_output --partial "#S"                   # session follows in the middle slot
  run sopt @airline-segment-left-out
  assert_output "SCRATCH"              # layout declarations never use public staging
  run sopt @airline--layout
  assert_output "default"              # recorded active
  airline layout use default
  $TMUX -L "$_bats_socket" set -t bats @airline-segment-left-out "SCRATCH"
  airline session apply
  run airline segment show left-out
  assert_output --partial "#h"                    # private snapshot was not replaced by staging
  mkdir -p "$BATS_TMPDIR/mylayouts"
  write_layout "$BATS_TMPDIR/mylayouts/withprefix.sh" \
    '  "$declare" widget right-mid prefix
  "$declare" segment left-out "#S"'
  airline layout register "$BATS_TMPDIR/mylayouts"
  airline layout use withprefix
  run airline segment show right-mid
  assert_output --partial 'client_prefix'
  mkdir -p "$BATS_TMPDIR/switch"
  write_layout "$BATS_TMPDIR/switch/rich.sh" '  "$declare" segment left-mid "MID"'
  write_layout "$BATS_TMPDIR/switch/lean.sh" '  "$declare" segment left-out "OUT"'
  airline layout register "$BATS_TMPDIR/switch"
  airline layout use rich
  run airline segment show left-mid
  assert_output --partial "MID"
  airline layout use lean                # lean never sets left-mid
  run airline segment show left-mid
  assert_output ""                       # cleared — not stale from rich
}

@test "invalid layouts are rejected atomically, reported, and recoverable" {
  airline session init
  mkdir -p "$BATS_TMPDIR/loopy"
  write_layout "$BATS_TMPDIR/loopy/rogue.sh" \
    '  airline palette use light
  "$declare" segment left-out "#S"'
  airline layout register "$BATS_TMPDIR/loopy"
  run airline layout use rogue
  assert_failure
  assert_output --partial "nested airline commands are not layout declarations"
  run airline palette show name
  assert_output "default"
  session="$($TMUX -L "$_bats_socket" display-message -p '#{session_id}')"
  mkdir -p "$BATS_TMPDIR/invalid-layout"
  write_layout "$BATS_TMPDIR/invalid-layout/broken.sh" \
    '  "$declare" segment nowhere "INVALID"'
  airline layout register "$BATS_TMPDIR/invalid-layout"

  run airline layout use broken
  assert_failure
  assert_output --partial "unknown segment slot 'nowhere'"
  run airline layout show name
  assert_output full
  run airline problem show airline airline-layout
  assert_output --partial "layout 'broken' unknown segment slot 'nowhere'"

  write_layout "$BATS_TMPDIR/invalid-layout/broken.sh" \
    '  "$declare" segment left-out "RECOVERED"'
  airline layout use broken
  run airline problem show airline airline-layout
  assert_output ""
  mkdir -p "$BATS_TMPDIR/ambiguous-layout"
  write_layout "$BATS_TMPDIR/ambiguous-layout/duplicate.sh" \
    '  "$declare" segment left-out "ONE"
  "$declare" segment left-out "TWO"'
  write_layout "$BATS_TMPDIR/ambiguous-layout/noisy.sh" \
    '  printf "not a protocol\\n"
  "$declare" segment left-out "ONE"'
  airline layout register "$BATS_TMPDIR/ambiguous-layout"

  run airline layout use duplicate
  assert_success
  [[ "$(airline segment show left-out)" == *ONE*TWO* ]]
  run airline layout use noisy
  assert_failure
  assert_output --partial "wrote to stdout"
  session="$($TMUX -L "$_bats_socket" display-message -p '#{session_id}')"
  mkdir -p "$BATS_TMPDIR/failing-layout"
  write_layout "$BATS_TMPDIR/failing-layout/unstable.sh" '  return 7'
  airline layout register "$BATS_TMPDIR/failing-layout"
  run airline layout use unstable
  assert_failure
  run airline problem show airline airline-layout
  assert_output --partial "layout 'unstable' could not be evaluated"

  write_layout "$BATS_TMPDIR/failing-layout/unstable.sh" \
    '  "$declare" segment left-out "RECOVERED"'
  airline layout use unstable
  run airline problem show airline airline-layout
  assert_output ""
}

@test "one-off layouts retain widget formats and identities through palette changes" {
  airline session init
  write_layout "$BATS_TEST_TMPDIR/oneoff.sh" '  "$declare" widget left-out prefix'
  airline layout load "$BATS_TEST_TMPDIR/oneoff.sh"
  run airline layout show name
  assert_output "$BATS_TEST_TMPDIR/oneoff.sh"
  prior="$(airline segment show left-out)"
  ids="$(sopt @airline--widgets)"
  airline palette use light
  assert_equal "$(airline segment show left-out)" "$prior"
  assert_equal "$(sopt @airline--widgets)" "$ids"
  run airline layout load /no/such/layout-file
  assert_failure
}

# --- session isolation ------------------------------------------------------

@test "session state is isolated and native pane context defeats environment overrides" {
  airline session init
  one="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{session_id}')"
  $TMUX -L "$_bats_socket" new-session -d -s other
  other="$($TMUX -L "$_bats_socket" display-message -p -t other '#{session_id}')"
  airline_session "$other" session init

  airline_session "$one" palette use light
  run airline_session "$one" palette show inner-bg
  assert_output "colour231"
  run airline_session "$other" palette show inner-bg
  assert_output "colour234"

  airline_session "$one" layout use minimal
  airline_session "$other" layout use default
  run airline_session "$one" segment show right-out
  assert_output ""
  run airline_session "$other" segment show right-out
  assert_output --partial "%Y-%m-%d %H:%M"

  run sopt @airline-palette-secondary -t "$one"
  assert_output "colour245"
  run sopt @airline-palette-secondary -t "$other"
  assert_output "colour246"

  airline_session "$other" layout use minimal
  run sopt @airline--layout -t "$other"
  assert_output "minimal"

  pane="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{pane_id}')"

  AIRLINE_SESSION="$other" TMUX_PANE="$pane" AIRLINE_DIR="$PROJECT_ROOT" \
    AIRLINE_TMUX="$TMUX -L $_bats_socket" "$PROJECT_ROOT/airline.sh" palette use light

  run airline_session "$one" palette show inner-bg
  assert_output "colour231"
  run airline_session "$other" palette show inner-bg
  assert_output "colour234"
}

@test "global user configuration is inherited without becoming mutable runtime state" {
  for element in outer-bg middle-bg inner-bg secondary primary emphasized active \
    special ok alert stress zoom copy monitor; do
    $TMUX -L "$_bats_socket" set -g "@airline-$element" colour99
  done
  $TMUX -L "$_bats_socket" set -g @airline-palette-inner-bg colour99
  $TMUX -L "$_bats_socket" set -g @airline-segment-left-out GLOBAL
  airline session init
  one="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{session_id}')"
  $TMUX -L "$_bats_socket" new-session -d -s other
  other="$($TMUX -L "$_bats_socket" display-message -p -t other '#{session_id}')"
  airline_session "$other" session init

  run airline_session "$one" palette show inner-bg
  assert_output "colour99"
  run airline_session "$other" palette show inner-bg
  assert_output "colour99"

  airline_session "$one" palette use light
  run get_option @airline-palette-inner-bg
  assert_output "colour99"             # runtime use did not rewrite the default
  run airline_session "$other" palette show inner-bg
  assert_output "colour99"
}

@test "palette and layout provenance are exposed through the CLI" {
  airline session init
  airline palette use light
  run airline palette show name
  assert_output "light"
  airline layout use default
  run airline layout show name
  assert_output "default"
  run airline layout show path
  assert_output --partial "/layouts/definitions/default.sh"
  run airline layout show
  assert_output --partial "name"
  assert_output --partial "path"
}

@test "catalog describe leaves applied layout state intact" {
  airline session init
  airline palette use light
  airline layout use minimal
  local before
  before="$(airline session show)"

  run airline palette describe dark
  assert_success
  assert_output --partial 'Dark 256-color palette'
  run airline widget describe prefix
  assert_success
  assert_output --partial "Native prefix, copy, sync, and key-table badges"
  run airline layout describe full
  assert_success
  assert_output --partial 'Available native widgets alongside session and date'

  run airline session show
  assert_success
  assert_output "$before"
}

@test "layout describe evaluates native declarations without observing widgets or changing configuration" {
  airline session init
  mkdir "$BATS_TEST_TMPDIR/layouts"
  printf '#| summary: Fixture widget\nairline_widget_format() { printf "%%s" "$1"; }\n' > "$BATS_TEST_TMPDIR/layouts/fixture.sh"
  cat > "$BATS_TEST_TMPDIR/layouts/inspect.sh" <<'LAYOUT'
#| summary: Inspect native declarations
airline_layout_configure() {
  "$1" segment left-out 'candidate #S'
  "$1" widget left-out fixture
}
LAYOUT
  airline layout register "$BATS_TEST_TMPDIR/layouts"
  airline widget register "$BATS_TEST_TMPDIR/layouts"
  before="$($TMUX -L "$_bats_socket" show-options -t bats)"
  run airline layout describe inspect
  assert_success
  assert_output --partial 'candidate #S'
  assert_output --partial 'left-out widget fixture'
  [[ ! -e "$BATS_TEST_TMPDIR/adapter-ran" ]]
  assert_equal "$($TMUX -L "$_bats_socket" show-options -t bats)" "$before"
  run airline problem show airline airline-layout
  assert_output ''
}
