#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load
load helper

# Executable layout behavior through the real CLI and an isolated tmux server.
# These drive the CLI as a subprocess (the `airline()` helper points it at the server
# via AIRLINE_TMUX), so they exercise the same path production uses.
#
# A clean server (-f /dev/null) so `init`'s default-seeding isn't perturbed by the
# developer's own ~/.tmux.conf (which may already configure airline).

setup() {
  $TMUX -L "$_bats_socket" -f /dev/null new-session -d -s bats
}

# --- init -------------------------------------------------------------------
@test "register blesses a dir; use loads a bare name from it, then renders" {
  airline init
  mkdir -p "$BATS_TMPDIR/mypalettes"
  cp "$PROJECT_ROOT/palettes/default" "$BATS_TMPDIR/mypalettes/custom"
  printf 'set @airline-inner-bg colour55\n' >> "$BATS_TMPDIR/mypalettes/custom"
  airline palette register "$BATS_TMPDIR/mypalettes"
  airline palette use custom
  run airline palette show inner-bg
  assert_output "colour55"
  run sopt status-style
  assert_output --partial "bg=colour55"     # rendered with the new color
}

@test "palette use rejects an unknown name and a path (no literal-path escape)" {
  airline init
  run airline palette use no-such-palette-xyz
  assert_failure
  run airline palette use /etc/passwd        # a path is not a bare name
  assert_failure
}

@test "an incomplete palette preserves the last good selection and raises a problem" {
  airline init
  session="$($TMUX -L "$_bats_socket" display-message -p '#{session_id}')"
  mkdir -p "$BATS_TMPDIR/incomplete"
  printf 'set @airline-inner-bg colour55\n' > "$BATS_TMPDIR/incomplete/broken"
  airline palette register "$BATS_TMPDIR/incomplete"

  run airline palette use broken
  assert_failure
  assert_output --partial "is incomplete"
  run airline palette show name
  assert_output default
  run airline problem show "$session" airline-palette
  assert_output "$(printf "fail\tpalette 'broken' is incomplete or could not be evaluated")"

  cp "$PROJECT_ROOT/palettes/default" "$BATS_TMPDIR/incomplete/broken"
  airline palette use broken
  run airline problem show "$session" airline-palette
  assert_output ""
}

@test "palette use resolves a bare name on the shipped search path" {
  airline init
  run airline palette use light       # a shipped bare name → found on the registered palettes/ dir
  assert_success
}

@test "register prepends: a registered dir shadows the shipped one" {
  airline init
  mkdir -p "$BATS_TMPDIR/shadow"
  cp "$PROJECT_ROOT/palettes/default" "$BATS_TMPDIR/shadow/dark"
  printf 'set @airline-inner-bg colour42\n' >> "$BATS_TMPDIR/shadow/dark"   # same name as shipped
  airline palette register "$BATS_TMPDIR/shadow"
  airline palette use dark
  run airline palette show inner-bg
  assert_output "colour42"            # the registered dark won, not the shipped colour234
}

@test "use records the active selection" {
  airline init
  airline palette use light
  run sopt @airline--palette
  assert_output "light"
}

# --- palette / segment (static config nouns: read-only `show`, written via set -g) --

@test "a directly-set color renders after apply" {
  airline init
  $TMUX -L "$_bats_socket" set -g @airline-active colour201
  airline apply
  run get_option window-status-current-format
  assert_output --partial "colour201"   # rendered into the bar (active highlight)
}

@test "a manual palette change clears provenance and remains after its global input is unset" {
  airline init
  airline palette use light
  $TMUX -L "$_bats_socket" set -g @airline-active colour201
  airline apply
  run airline palette show active
  assert_output colour201
  run airline palette show name
  assert_output ""

  $TMUX -L "$_bats_socket" set -gu @airline-active
  airline apply
  run airline palette show active
  assert_output colour201

  airline palette use light
  run airline palette show active
  assert_output colour136
  run airline palette show name
  assert_output light
}

@test "a named layout consumes a pending manual color without obscuring its own provenance" {
  airline init
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
}

@test "a manual segment change clears layout provenance and remains after input is unset" {
  airline init
  airline layout use full
  $TMUX -L "$_bats_socket" set -g @airline-segment-right-out MANUAL
  airline apply
  run airline segment show right-out
  assert_output MANUAL
  run airline layout show name
  assert_output ""

  $TMUX -L "$_bats_socket" set -gu @airline-segment-right-out
  airline apply
  run airline segment show right-out
  assert_output MANUAL
}

@test "palette show X prints one element; palette show prints all" {
  airline init
  $TMUX -L "$_bats_socket" set -g @airline-active colour201
  airline apply
  run airline palette show active
  assert_output "colour201"
  run airline palette show
  assert_output --partial "active"
  assert_output --partial "inner-bg"
}

@test "palette show rejects an unknown element" {
  airline init
  run airline palette show bogus
  assert_failure
}

@test "segment show reads back a directly-set slot option" {
  $TMUX -L "$_bats_socket" set -g @airline-segment-left-out "#H"   # the only write path
  airline init
  run airline segment show left-out
  assert_output "#H"
}

@test "segment show rejects an unknown slot" {
  airline init
  run airline segment show middle
  assert_failure
}

# --- adapter (dynamic: apply palette → a plugin's options) ------------------

@test "adapter use applies the current palette to the plugin's options" {
  airline init
  airline adapter use cpu
  # behaviour, not content: cpu's low-severity fg == the palette's secondary value
  run sopt @cpu_low_fg_color
  assert_output "$(airline palette show secondary)"
}

@test "adapter use re-applies literal colours on a palette change" {
  airline init
  airline adapter use cpu
  $TMUX -L "$_bats_socket" set -g @airline-secondary colour99
  airline adapter use cpu                   # re-run the adapter
  run sopt @cpu_low_fg_color
  assert_output "colour99"                   # picked up the new palette value
}

@test "adapter use rejects an unknown name" {
  airline init
  run airline adapter use no-such-adapter
  assert_failure
}

@test "adapter available lists the catalog on the path (what you can use)" {
  airline init
  run airline adapter available
  assert_line "cpu"                     # one name per line
  assert_line "battery"
  assert_line "online"
}

@test "adapter use records the applied adapter; adapter show reads the active set raw" {
  airline init
  airline adapter use cpu battery       # multi-target
  run airline adapter show
  assert_line "cpu"                     # one name per line, script-safe (`for a in $(…)`)
  assert_line "battery"
}

@test "a layout switch clears the previous layout's adapter set (clean slate)" {
  airline init
  mkdir -p "$BATS_TMPDIR/adps"
  printf '#!/usr/bin/env bash\nairline adapter use cpu\n' > "$BATS_TMPDIR/adps/withcpu"
  printf '#!/usr/bin/env bash\n$AIRLINE_TMUX set -t "$AIRLINE_SESSION" @airline-segment-left-out "#S"\n' > "$BATS_TMPDIR/adps/bare"
  airline layout register "$BATS_TMPDIR/adps"
  airline layout use withcpu
  run airline adapter show
  assert_line "cpu"                     # recorded by the layout
  airline layout use bare               # applies no adapters → clears the set
  run airline adapter show
  assert_output ""                      # nothing active after the switch
}

@test "available is uniform across the loadable kinds (palette, layout)" {
  airline init
  run airline palette available
  assert_line "default"                 # shipped palettes
  assert_line "dark"
  run airline layout available
  assert_line "adaptive"                # shipped layouts
  assert_line "minimal"
}

# --- layout (dynamic: a composition script, stored + re-applied) ------------

@test "layout use runs the composition script and records the active layout" {
  airline init
  $TMUX -L "$_bats_socket" set -t bats @airline-segment-left-out "SCRATCH"
  airline layout use default
  run airline segment show left-out
  assert_output "#S"                   # composition applied
  run sopt @airline-segment-left-out
  assert_output ""                     # public session staging was removed
  run sopt @airline--layout
  assert_output "default"              # recorded active
}

@test "apply ignores temporary session staging and preserves the committed layout" {
  airline init
  airline layout use default
  $TMUX -L "$_bats_socket" set -t bats @airline-segment-left-out "SCRATCH"
  airline apply
  run airline segment show left-out
  assert_output "#S"                    # private snapshot was not replaced by staging
}

@test "a layout may apply an adapter; palette drives its colours" {
  airline init
  mkdir -p "$BATS_TMPDIR/mylayouts"
  printf '#!/usr/bin/env bash\nairline adapter use cpu\n$AIRLINE_TMUX set -t "$AIRLINE_SESSION" @airline-segment-left-out "#S"\n' \
    > "$BATS_TMPDIR/mylayouts/withcpu"
  airline layout register "$BATS_TMPDIR/mylayouts"
  airline layout use withcpu
  run sopt @cpu_low_fg_color      # the adapter ran inside the layout
  assert_output "$(airline palette show secondary)"
}

@test "a layout switch clears the previous layout's slots (clean slate)" {
  airline init
  mkdir -p "$BATS_TMPDIR/switch"
  printf '#!/usr/bin/env bash\n$AIRLINE_TMUX set -t "$AIRLINE_SESSION" @airline-segment-left-mid "MID"\n' > "$BATS_TMPDIR/switch/rich"
  printf '#!/usr/bin/env bash\n$AIRLINE_TMUX set -t "$AIRLINE_SESSION" @airline-segment-left-out "OUT"\n' > "$BATS_TMPDIR/switch/lean"
  airline layout register "$BATS_TMPDIR/switch"
  airline layout use rich
  run airline segment show left-mid
  assert_output "MID"
  airline layout use lean                # lean never sets left-mid
  run airline segment show left-mid
  assert_output ""                       # cleared — not stale from rich
}

@test "a layout cannot recursively change the selected palette" {
  airline init
  mkdir -p "$BATS_TMPDIR/loopy"
  printf '#!/usr/bin/env bash\nairline palette use light\n$AIRLINE_TMUX set -t "$AIRLINE_SESSION" @airline-segment-left-out "#S"\n' \
    > "$BATS_TMPDIR/loopy/rogue"
  airline layout register "$BATS_TMPDIR/loopy"
  run airline layout use rogue
  assert_failure
  assert_output --partial "layout evaluation cannot invoke palette use"
  run airline palette show name
  assert_output "default"
}

@test "a failed layout registers an internal session problem and a retry clears it" {
  airline init
  session="$($TMUX -L "$_bats_socket" display-message -p '#{session_id}')"
  mkdir -p "$BATS_TMPDIR/failing-layout"
  printf '#!/usr/bin/env bash\nexit 7\n' > "$BATS_TMPDIR/failing-layout/unstable"
  airline layout register "$BATS_TMPDIR/failing-layout"
  run airline layout use unstable
  assert_failure
  run airline problem show "$session" airline-layout
  assert_output "$(printf "fail\tlayout 'unstable' could not be applied")"

  printf '#!/usr/bin/env bash\n$AIRLINE_TMUX set -t "$AIRLINE_SESSION" @airline-segment-left-out "RECOVERED"\n' \
    > "$BATS_TMPDIR/failing-layout/unstable"
  airline layout use unstable
  run airline problem show "$session" airline-layout
  assert_output ""
}

@test "layout load runs a one-off by path and records its absolute provenance" {
  airline init
  printf '#!/usr/bin/env bash\n$AIRLINE_TMUX set -t "$AIRLINE_SESSION" @airline-segment-left-out "#S"\n' > "$BATS_TMPDIR/oneoff"
  airline layout load "$BATS_TMPDIR/oneoff"
  run sopt @airline--layout
  assert_output --regexp '^/.*/oneoff$'   # absolute path recorded (not a bare name)
  # apply consumes globals, not temporary session staging
  $TMUX -L "$_bats_socket" set -t bats @airline-segment-left-out "SCRATCH"
  airline apply
  run airline segment show left-out
  assert_output "#S"
}

@test "layout load rejects a missing file (no path walk, but must exist)" {
  airline init
  run airline layout load /no/such/layout-file
  assert_failure
}

@test "adapter load records a one-off adapter for palette replay" {
  airline init
  printf 'opt_set_session "$AIRLINE_SESSION" @custom_fg "${PALETTE[active]}"\n' > "$BATS_TMPDIR/oneoff-adapter"
  airline adapter load "$BATS_TMPDIR/oneoff-adapter"
  run sopt @custom_fg
  assert_output "$(airline palette show active)"   # applied the current palette
  airline palette use light
  run sopt @custom_fg
  assert_output "$(airline palette show active)"   # replayed against the new palette
}

@test "palette use replays the active adapters against the new palette" {
  airline init
  mkdir -p "$BATS_TMPDIR/pl"
  printf '#!/usr/bin/env bash\nairline adapter use cpu\n$AIRLINE_TMUX set -t "$AIRLINE_SESSION" @airline-segment-left-out "#S"\n' \
    > "$BATS_TMPDIR/pl/withcpu"
  airline layout register "$BATS_TMPDIR/pl"
  airline layout use withcpu            # cpu adapter active, coloured by the dark palette
  airline palette use light             # swap palette → must re-colour cpu
  run sopt @cpu_low_fg_color
  assert_output "$(airline palette show secondary)"   # tracks light's secondary now
}

@test "adapter use applies multiple plugins in one call (multi-target)" {
  airline init
  airline adapter use cpu battery       # one call, both applied
  run sopt @cpu_low_fg_color
  assert_output "$(airline palette show secondary)"
  run sopt @batt_color_full_charge
  assert_success                        # battery adapter ran too (option is set)
  refute_output ""
}

# --- session isolation ------------------------------------------------------

@test "palette, layout, and adapter state are isolated by session" {
  airline init
  one="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{session_id}')"
  $TMUX -L "$_bats_socket" new-session -d -s other
  other="$($TMUX -L "$_bats_socket" display-message -p -t other '#{session_id}')"
  airline_session "$other" init

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
}

@test "global user configuration is inherited without becoming mutable runtime state" {
  for element in outer-bg middle-bg inner-bg secondary primary emphasized active \
    special ok alert stress zoom copy monitor; do
    $TMUX -L "$_bats_socket" set -g "@airline-$element" colour99
  done
  $TMUX -L "$_bats_socket" set -g @airline-inner-bg colour99
  $TMUX -L "$_bats_socket" set -g @airline-segment-left-out GLOBAL
  airline init
  one="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{session_id}')"
  $TMUX -L "$_bats_socket" new-session -d -s other
  other="$($TMUX -L "$_bats_socket" display-message -p -t other '#{session_id}')"
  airline_session "$other" init

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

@test "AIRLINE_SESSION cannot override tmux's native pane context" {
  airline init
  one="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{session_id}')"
  pane="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{pane_id}')"
  $TMUX -L "$_bats_socket" new-session -d -s other
  other="$($TMUX -L "$_bats_socket" display-message -p -t other '#{session_id}')"
  airline_session "$other" init

  AIRLINE_SESSION="$other" TMUX_PANE="$pane" AIRLINE_DIR="$PROJECT_ROOT" \
    AIRLINE_TMUX="$TMUX -L $_bats_socket" "$PROJECT_ROOT/airline.sh" palette use light

  run airline_session "$one" palette show inner-bg
  assert_output "colour231"
  run airline_session "$other" palette show inner-bg
  assert_output "colour234"
}

@test "palette show name reads the active palette through the CLI" {
  airline init
  airline palette use light
  run airline palette show name
  assert_output "light"
}

@test "layout show exposes its summary and raw name/path fields" {
  airline init
  airline layout use default
  run airline layout show name
  assert_output "default"
  run airline layout show path
  assert_output --partial "/layouts/default"
  run airline layout show
  assert_output --partial "name"
  assert_output --partial "path"
}
