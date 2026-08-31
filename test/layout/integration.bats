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
  cp "$PROJECT_ROOT/layouts/palettes/default" "$BATS_TMPDIR/mypalettes/custom"
  printf 'set @airline-inner-bg colour55\n' >> "$BATS_TMPDIR/mypalettes/custom"
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
  printf 'set @airline-inner-bg colour55\n' > "$BATS_TMPDIR/incomplete/broken"
  airline palette register "$BATS_TMPDIR/incomplete"

  run airline palette use broken
  assert_failure
  assert_output --partial "is incomplete"
  run airline palette show name
  assert_output custom
  run airline problem show airline-palette
  assert_output --partial "palette 'broken' is incomplete or could not be evaluated"

  cp "$PROJECT_ROOT/layouts/palettes/default" "$BATS_TMPDIR/incomplete/broken"
  airline palette use broken
  run airline problem show airline-palette
  assert_output ""
  run airline palette use light       # a shipped bare name → found in layouts/palettes
  assert_success

  mkdir -p "$BATS_TMPDIR/shadow"
  cp "$PROJECT_ROOT/layouts/palettes/default" "$BATS_TMPDIR/shadow/dark"
  printf 'set @airline-inner-bg colour42\n' >> "$BATS_TMPDIR/shadow/dark"   # same name as shipped
  airline palette register "$BATS_TMPDIR/shadow"
  airline palette use dark
  run airline palette show inner-bg
  assert_output "colour42"            # the registered dark won, not the shipped colour234
  airline palette use light
  run sopt @airline--palette
  assert_output "light"
}

# --- palette / segment (static config nouns: read-only `show`, written via set -g) --

@test "manual palette and segment inputs preserve clear provenance and show contracts" {
  airline session init
  $TMUX -L "$_bats_socket" set -g @airline-active colour201
  airline session apply
  run sopt window-status-current-format
  assert_output --partial "colour201"   # rendered into the bar (active highlight)
  airline palette use light
  $TMUX -L "$_bats_socket" set -g @airline-active colour201
  airline session apply
  run airline palette show active
  assert_output colour201
  run airline palette show name
  assert_output ""

  $TMUX -L "$_bats_socket" set -gu @airline-active
  airline session apply
  run airline palette show active
  assert_output colour201

  airline palette use light
  run airline palette show active
  assert_output colour136
  run airline palette show name
  assert_output light
  airline palette use light
  $TMUX -L "$_bats_socket" set -g @airline-active colour201

  run airline palette show active
  assert_output colour136             # setting input alone does not mutate the snapshot
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
  $TMUX -L "$_bats_socket" set -g @airline-active colour201
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

# --- adapter (dynamic: apply palette → a plugin's options) ------------------

@test "adapter catalog, application, replay, and layout replacement compose" {
  airline session init
  airline adapter use cpu
  # behaviour, not content: cpu's low-severity fg == the palette's secondary value
  run sopt @cpu_low_fg_color
  assert_output "$(airline palette show secondary)"
  airline adapter use cpu
  $TMUX -L "$_bats_socket" set -g @airline-secondary colour99
  airline adapter use cpu                   # re-run the adapter
  run sopt @cpu_low_fg_color
  assert_output "colour99"                   # picked up the new palette value
  run airline adapter use no-such-adapter
  assert_failure
  run airline adapter list
  assert_line "cpu"                     # one name per line
  assert_line "battery"
  assert_line "online"
  airline adapter use cpu battery       # multi-target
  run airline adapter show
  assert_line "cpu"                     # one name per line, script-safe (`for a in $(…)`)
  assert_line "battery"
  mkdir -p "$BATS_TMPDIR/adps"
  write_layout "$BATS_TMPDIR/adps/withcpu" '  "$declare" adapter use cpu'
  write_layout "$BATS_TMPDIR/adps/bare" '  "$declare" segment left-out "#S"'
  airline layout register "$BATS_TMPDIR/adps"
  airline layout use withcpu
  run airline adapter show
  assert_line "cpu"                     # recorded by the layout
  airline layout use bare               # applies no adapters → clears the set
  run airline adapter show
  assert_output ""                      # nothing active after the switch
  run airline palette list
  assert_line "default"                 # shipped palettes
  assert_line "dark"
  run airline layout list
  assert_line "adaptive"                # shipped layouts
  assert_line "minimal"
}

# --- layout (validated Bash declaration, captured into private state) --------

@test "layout composition preserves committed state and replaces prior declarations" {
  airline session init
  $TMUX -L "$_bats_socket" set -t bats @airline-segment-left-out "SCRATCH"
  airline layout use default
  run airline segment show left-out
  assert_output "#S"                   # composition applied
  run sopt @airline-segment-left-out
  assert_output "SCRATCH"              # layout declarations never use public staging
  run sopt @airline--layout
  assert_output "default"              # recorded active
  airline layout use default
  $TMUX -L "$_bats_socket" set -t bats @airline-segment-left-out "SCRATCH"
  airline session apply
  run airline segment show left-out
  assert_output "#S"                    # private snapshot was not replaced by staging
  mkdir -p "$BATS_TMPDIR/mylayouts"
  write_layout "$BATS_TMPDIR/mylayouts/withcpu" \
    '  "$declare" adapter use cpu
  "$declare" segment left-out "#S"'
  airline layout register "$BATS_TMPDIR/mylayouts"
  airline layout use withcpu
  run sopt @cpu_low_fg_color      # the adapter ran inside the layout
  assert_output "$(airline palette show secondary)"
  mkdir -p "$BATS_TMPDIR/switch"
  write_layout "$BATS_TMPDIR/switch/rich" '  "$declare" segment left-mid "MID"'
  write_layout "$BATS_TMPDIR/switch/lean" '  "$declare" segment left-out "OUT"'
  airline layout register "$BATS_TMPDIR/switch"
  airline layout use rich
  run airline segment show left-mid
  assert_output "MID"
  airline layout use lean                # lean never sets left-mid
  run airline segment show left-mid
  assert_output ""                       # cleared — not stale from rich
}

@test "invalid layouts are rejected atomically, reported, and recoverable" {
  airline session init
  mkdir -p "$BATS_TMPDIR/loopy"
  write_layout "$BATS_TMPDIR/loopy/rogue" \
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
  write_layout "$BATS_TMPDIR/invalid-layout/broken" \
    '  "$declare" segment nowhere "INVALID"'
  airline layout register "$BATS_TMPDIR/invalid-layout"

  run airline layout use broken
  assert_failure
  assert_output --partial "unknown segment slot 'nowhere'"
  run airline layout show name
  assert_output adaptive
  run airline problem show airline-layout
  assert_output --partial "layout 'broken' unknown segment slot 'nowhere'"

  write_layout "$BATS_TMPDIR/invalid-layout/broken" \
    '  "$declare" segment left-out "RECOVERED"'
  airline layout use broken
  run airline problem show airline-layout
  assert_output ""
  mkdir -p "$BATS_TMPDIR/ambiguous-layout"
  write_layout "$BATS_TMPDIR/ambiguous-layout/duplicate" \
    '  "$declare" segment left-out "ONE"
  "$declare" segment left-out "TWO"'
  write_layout "$BATS_TMPDIR/ambiguous-layout/noisy" \
    '  printf "not a protocol\\n"
  "$declare" segment left-out "ONE"'
  airline layout register "$BATS_TMPDIR/ambiguous-layout"

  run airline layout use duplicate
  assert_failure
  assert_output --partial "declared more than once"
  run airline layout use noisy
  assert_failure
  assert_output --partial "wrote to stdout"
  session="$($TMUX -L "$_bats_socket" display-message -p '#{session_id}')"
  mkdir -p "$BATS_TMPDIR/failing-layout"
  write_layout "$BATS_TMPDIR/failing-layout/unstable" '  return 7'
  airline layout register "$BATS_TMPDIR/failing-layout"
  run airline layout use unstable
  assert_failure
  run airline problem show airline-layout
  assert_output --partial "layout 'unstable' could not be evaluated"

  write_layout "$BATS_TMPDIR/failing-layout/unstable" \
    '  "$declare" segment left-out "RECOVERED"'
  airline layout use unstable
  run airline problem show airline-layout
  assert_output ""
}

@test "one-off layout and adapter loads replay through later palette changes" {
  airline session init
  write_layout "$BATS_TMPDIR/oneoff" '  "$declare" segment left-out "#S"'
  airline layout load "$BATS_TMPDIR/oneoff"
  run sopt @airline--layout
  assert_output --regexp '^/.*/oneoff$'   # absolute path recorded (not a bare name)
  # apply consumes globals, not temporary session staging
  $TMUX -L "$_bats_socket" set -t bats @airline-segment-left-out "SCRATCH"
  airline session apply
  run airline segment show left-out
  assert_output "#S"
  run airline layout load /no/such/layout-file
  assert_failure
  printf 'opt_set_session "$AIRLINE_SESSION" @custom_fg "${PALETTE[active]}"\n' > "$BATS_TMPDIR/oneoff-adapter"
  airline adapter load "$BATS_TMPDIR/oneoff-adapter"
  run sopt @custom_fg
  assert_output "$(airline palette show active)"   # applied the current palette
  airline palette use light
  run sopt @custom_fg
  assert_output "$(airline palette show active)"   # replayed against the new palette
  mkdir -p "$BATS_TMPDIR/pl"
  write_layout "$BATS_TMPDIR/pl/withcpu" \
    '  "$declare" adapter use cpu
  "$declare" segment left-out "#S"'
  airline layout register "$BATS_TMPDIR/pl"
  airline layout use withcpu            # cpu adapter active, coloured by the dark palette
  airline palette use light             # swap palette → must re-colour cpu
  run sopt @cpu_low_fg_color
  assert_output "$(airline palette show secondary)"   # tracks light's secondary now
  airline adapter use cpu battery       # one call, both applied
  run sopt @cpu_low_fg_color
  assert_output "$(airline palette show secondary)"
  run sopt @batt_color_full_charge
  assert_success                        # battery adapter ran too (option is set)
  refute_output ""
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
  assert_output "%Y-%m-%d %H:%M"

  airline_session "$one" adapter use cpu
  run sopt @cpu_low_fg_color -t "$one"
  assert_output "colour245"
  run sopt @cpu_low_fg_color -t "$other"
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
  $TMUX -L "$_bats_socket" set -g @airline-inner-bg colour99
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
  run get_option @airline-inner-bg
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
  assert_output --partial "/layouts/definitions/default"
  run airline layout show
  assert_output --partial "name"
  assert_output --partial "path"
}
