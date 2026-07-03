#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load
load helper

# The CLI/API boundary (the `airline` executable) on the new layer. These drive the
# real CLI as a subprocess (the `airline()` helper points it at the isolated server
# via AIRLINE_TMUX), so they exercise the same path production uses.
#
# A clean server (-f /dev/null) so `init`'s default-seeding isn't perturbed by the
# developer's own ~/.tmux.conf (which may already configure airline).

setup() {
  $TMUX -L "$_bats_socket" -f /dev/null new-session -d -s bats
}

# --- init -------------------------------------------------------------------

@test "init publishes the CLI path as the public bootstrap handle + sets the sentinel" {
  airline init
  run get_option @airline-cli          # public (single dash) — the one published handle
  assert_output --partial "/airline"
  run get_option @airline--defaults-done
  assert_output "1"
}

@test "init applies the default palette when no palette is set" {
  airline init
  run get_option @airline-inner-bg
  assert_output "colour234"          # palette use default
  run get_option @airline--palette
  assert_output "default"            # recorded
}

@test "init applies the default layout (segments) when none is set" {
  airline init
  run get_option status-left
  assert_output --partial "#S"       # layout use default → segment use default
  run get_option @airline--layout
  assert_output "default"            # recorded, so apply re-applies it
}

@test "init does not clobber a user-set palette" {
  $TMUX -L "$_bats_socket" set -g @airline-inner-bg colour99
  airline init
  run get_option @airline-inner-bg
  assert_output "colour99"           # user value preserved; default not applied
}

@test "init is idempotent: a reload keeps runtime segment changes" {
  airline init
  $TMUX -L "$_bats_socket" set -g @airline-segment-left-out "CUSTOM"
  airline init                       # sentinel set → no re-seed
  run get_option @airline-segment-left-out
  assert_output "CUSTOM"
}

@test "init composes the bar (chrome + window formats)" {
  airline init
  run get_option status-style
  assert_output --partial "bg=colour234"
  run get_option window-status-current-format
  assert_output --partial "#I:#W"
}

# --- apply / use ------------------------------------------------------------

@test "apply renders from the current source of truth" {
  airline init
  # a palette element is source-of-truth (not layout-managed, so apply won't reset it)
  $TMUX -L "$_bats_socket" set -g @airline-active "colour201"
  airline apply
  run get_option window-status-current-format
  assert_output --partial "colour201"
}

@test "show reports the active config and recurses into the static nouns" {
  airline init
  run airline show
  assert_success
  assert_output --partial "layout"      # a top-level record
  assert_output --partial "default"     # its active value
  assert_output --partial "inner-bg"    # recursed into palette show
  assert_output --partial "left-out"    # recursed into segment show
  assert_output --partial "paths:"      # the search paths
  assert_output --partial "/palettes"   # the shipped palette dir on the path
  refute_output --partial "health"      # dynamic per-window nouns excluded from the walk
}

@test "register blesses a dir; use loads a bare name from it, then renders" {
  airline init
  mkdir -p "$BATS_TMPDIR/mypalettes"
  printf 'set -g @airline-inner-bg colour55\n' > "$BATS_TMPDIR/mypalettes/custom"
  airline palette register "$BATS_TMPDIR/mypalettes"
  airline palette use custom
  run get_option @airline-inner-bg
  assert_output "colour55"
  run get_option status-style
  assert_output --partial "bg=colour55"     # rendered with the new color
}

@test "palette use rejects an unknown name and a path (no literal-path escape)" {
  airline init
  run airline palette use no-such-palette-xyz
  assert_failure
  run airline palette use /etc/passwd        # a path is not a bare name
  assert_failure
}

@test "palette use resolves a bare name on the shipped search path" {
  airline init
  run airline palette use light       # a shipped bare name → found on the registered palettes/ dir
  assert_success
}

@test "register prepends: a registered dir shadows the shipped one" {
  airline init
  mkdir -p "$BATS_TMPDIR/shadow"
  printf 'set -g @airline-inner-bg colour42\n' > "$BATS_TMPDIR/shadow/dark"   # same name as shipped
  airline palette register "$BATS_TMPDIR/shadow"
  airline palette use dark
  run get_option @airline-inner-bg
  assert_output "colour42"            # the registered dark won, not the shipped colour234
}

@test "use records the active selection" {
  airline init
  airline palette use light
  run get_option @airline--palette
  assert_output "light"
}

# --- palette / segment (static nouns: set X / clear X / show [X], staged) ------

@test "palette set stages a color; apply renders it" {
  airline init
  airline palette set active colour201
  run get_option @airline-active
  assert_output "colour201"             # staged public option, no render yet
  airline apply
  run get_option window-status-current-format
  assert_output --partial "colour201"   # rendered into the bar (active highlight)
}

@test "palette show X prints one element; palette show prints all" {
  airline init
  airline palette set active colour201
  run airline palette show active
  assert_output "colour201"
  run airline palette show
  assert_output --partial "active"
  assert_output --partial "inner-bg"
}

@test "palette set rejects an unknown element" {
  airline init
  run airline palette set bogus colour1
  assert_failure
}

@test "segment set stages a slot; show reads it back" {
  airline init
  airline segment set left-out "#H"
  run airline segment show left-out
  assert_output "#H"
}

@test "segment set rejects an unknown slot" {
  airline init
  run airline segment set middle nope
  assert_failure
}

# --- adapter (dynamic: apply palette → a plugin's options) ------------------

@test "adapter use applies the current palette to the plugin's options" {
  airline init
  airline adapter use cpu
  # behaviour, not content: cpu's low-severity fg == the palette's secondary value
  run get_option @cpu_low_fg_color
  assert_output "$(get_option @airline-secondary)"
}

@test "adapter use re-applies literal colours on a palette change" {
  airline init
  airline adapter use cpu
  airline palette set secondary colour99   # move the role
  airline adapter use cpu                   # re-run the adapter
  run get_option @cpu_low_fg_color
  assert_output "colour99"                   # picked up the new palette value
}

@test "adapter use rejects an unknown name" {
  airline init
  run airline adapter use no-such-adapter
  assert_failure
}

# --- layout (dynamic: a composition script, stored + re-applied) ------------

@test "layout use runs the composition and records the active layout" {
  airline init
  $TMUX -L "$_bats_socket" set -g @airline-segment-left-out "SCRATCH"   # perturb
  airline layout use default          # its `segment use default` resets the slots
  run get_option @airline-segment-left-out
  assert_output "#S"                   # composition applied
  run get_option @airline--layout
  assert_output "default"              # recorded active
}

@test "apply re-runs the stored layout" {
  airline init
  airline layout use default
  $TMUX -L "$_bats_socket" set -g @airline-segment-left-out "SCRATCH"   # perturb after
  airline apply                        # re-runs default → segment use default
  run get_option @airline-segment-left-out
  assert_output "#S"                    # restored by the re-run
}

@test "a layout may apply an adapter; palette drives its colours" {
  airline init
  mkdir -p "$BATS_TMPDIR/mylayouts"
  printf 'adapter use cpu\nsegment use default\n' > "$BATS_TMPDIR/mylayouts/withcpu"
  airline layout register "$BATS_TMPDIR/mylayouts"
  airline layout use withcpu
  run get_option @cpu_low_fg_color      # the adapter ran inside the layout
  assert_output "$(get_option @airline-secondary)"
}

@test "a layout rejects non-composition commands (palette/lifecycle)" {
  airline init
  mkdir -p "$BATS_TMPDIR/badlayouts"
  printf 'palette use light\n' > "$BATS_TMPDIR/badlayouts/sneaky"
  airline layout register "$BATS_TMPDIR/badlayouts"
  run airline layout use sneaky
  assert_failure                        # only adapter/segment allowed
}

@test "layout load runs a one-off by path and records the ABSOLUTE path for re-apply" {
  airline init
  printf 'segment use default\n' > "$BATS_TMPDIR/oneoff"
  airline layout load "$BATS_TMPDIR/oneoff"
  run get_option @airline--layout
  assert_output --regexp '^/.*/oneoff$'   # absolute path recorded (not a bare name)
  # apply re-runs the loaded layout (resets a perturbed slot)
  airline segment set left-out "SCRATCH"
  airline apply
  run get_option @airline-segment-left-out
  assert_output "#S"
}

@test "layout load rejects a missing file (no path walk, but must exist)" {
  airline init
  run airline layout load /no/such/layout-file
  assert_failure
}

@test "adapter load applies a one-off adapter script (palette-driven, not recorded)" {
  airline init
  printf 'opt_set_global @custom_fg "${PALETTE[active]}"\n' > "$BATS_TMPDIR/oneoff-adapter"
  airline adapter load "$BATS_TMPDIR/oneoff-adapter"
  run get_option @custom_fg
  assert_output "$(get_option @airline-active)"   # applied the current palette
}

@test "palette use re-applies the active layout's adapters to the new palette" {
  airline init
  mkdir -p "$BATS_TMPDIR/pl"
  printf 'adapter use cpu\nsegment use default\n' > "$BATS_TMPDIR/pl/withcpu"
  airline layout register "$BATS_TMPDIR/pl"
  airline layout use withcpu            # cpu adapter active, coloured by the dark palette
  airline palette use light             # swap palette → must re-colour cpu
  run get_option @cpu_low_fg_color
  assert_output "$(get_option @airline-secondary)"   # tracks light's secondary now
}

# --- status (dynamic noun) --------------------------------------------------

@test "status set lights the badge; clear removes it" {
  airline init
  airline status set build active
  run wopt @airline--badge-status
  assert_output "active"
  airline status clear build
  run wopt @airline--badge-status
  assert_output ""
}

@test "status set reduces multiple contributors by precedence" {
  airline init
  airline status set build active
  airline status set review attention
  run wopt @airline--badge-status
  assert_output "attention"          # attention outranks active
}

@test "status set rejects an invalid level" {
  airline init
  run airline status set x bogus
  assert_failure
}

@test "status show lists contributors; status show X prints one level" {
  airline init
  airline status set build active
  run airline status show
  assert_output --partial "build"
  assert_output --partial "active"
  run airline status show build
  assert_output "active"
}

# --- health (dynamic noun) --------------------------------------------------

@test "health set/clear drives the health badge" {
  airline init
  airline health set cpu alert
  run wopt @airline--badge-health
  assert_output "alert"
  airline health clear cpu
  run wopt @airline--badge-health
  assert_output ""
}

@test "health set rejects an invalid severity" {
  airline init
  run airline health set disk warpspeed
  assert_failure
}

# --- transient (consume-on-view) --------------------------------------------

@test "a --transient signal arms the focus hook and clears on _unfocus" {
  airline init
  win="$($TMUX -L "$_bats_socket" display-message -p '#{window_id}')"
  airline status set build active                 # persistent
  airline status set review attention --transient # transient
  run get_option focus-events
  assert_output "on"
  airline _unfocus "$win"
  run wopt @airline--badge-status
  assert_output "active"             # transient 'review' gone, persistent 'build' remains
}

# --- state (active/suspended) -----------------------------------------------

@test "state suspend traps the prefix; resume restores; show reads the state" {
  airline init
  run airline state show
  assert_output "active"            # default
  airline state suspend
  run get_option prefix
  assert_output "None"              # prefix trapped
  run airline state show
  assert_output "suspended"
  airline state resume
  run get_option prefix
  refute_output "None"              # released → back to default
  run airline state show
  assert_output "active"
}

@test "state toggle flips between active and suspended" {
  airline init
  airline state toggle
  run airline state show
  assert_output "suspended"
  airline state toggle
  run airline state show
  assert_output "active"
}

@test "palette current reads the active palette via the API (not a private option)" {
  airline init
  airline palette use light
  run airline palette current
  assert_output "light"
}

# --- help -------------------------------------------------------------------

@test "help is self-documenting: extracted verbs, iterate + recurse into nouns" {
  run airline help
  assert_success
  assert_output --partial "init"                    # a top-level command (from the dispatcher)
  assert_output --partial "palette:"                # recursed into a noun
  assert_output --partial "<element> <color>"       # a verb's extracted #| help
  refute_output --partial "#|"                      # the marker itself is stripped
}

@test "<noun> help prints just that noun" {
  run airline palette help
  assert_success
  assert_output --partial "palette:"
  assert_output --partial "register"
  refute_output --partial "segment:"                # scoped to the one noun
}
