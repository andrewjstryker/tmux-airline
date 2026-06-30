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

@test "init publishes the CLI path and sets the first-run sentinel" {
  airline init
  run get_option @airline--cli
  assert_output --partial "/airline"
  run get_option @airline--defaults-done
  assert_output "1"
}

@test "init seeds the default theme when no palette is set" {
  airline init
  run get_option @airline-inner-bg
  assert_output "colour234"          # from themes/dark
}

@test "init seeds dependency-free default segments" {
  airline init
  run get_option status-left
  assert_output --partial "#S"       # the session-name segment from bundles/default
}

@test "init does not clobber a user-set palette" {
  $TMUX -L "$_bats_socket" set -g @airline-inner-bg colour99
  airline init
  run get_option @airline-inner-bg
  assert_output "colour99"           # user value preserved; dark not sourced
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
  $TMUX -L "$_bats_socket" set -g @airline-segment-right-out "ZZZ"
  airline apply
  run get_option status-right
  assert_output --partial "ZZZ"
}

@test "theme use sources a tmux file then renders" {
  airline init
  printf 'set -g @airline-inner-bg colour55\n' > "$BATS_TMPDIR/airline-use-theme"
  airline theme use "$BATS_TMPDIR/airline-use-theme"
  run get_option @airline-inner-bg
  assert_output "colour55"
  run get_option status-style
  assert_output --partial "bg=colour55"     # rendered with the new color
}

@test "theme use rejects an unknown name" {
  airline init
  run airline theme use no-such-theme-xyz
  assert_failure
}

# --- theme / segment (static nouns: set X / clear X / show [X], staged) ------

@test "theme set stages a color; apply renders it" {
  airline init
  airline theme set active colour201
  run get_option @airline-active
  assert_output "colour201"             # staged public option, no render yet
  airline apply
  run get_option window-status-current-format
  assert_output --partial "colour201"   # rendered into the bar (active highlight)
}

@test "theme show X prints one element; theme show prints all" {
  airline init
  airline theme set active colour201
  run airline theme show active
  assert_output "colour201"
  run airline theme show
  assert_output --partial "active"
  assert_output --partial "inner-bg"
}

@test "theme set rejects an unknown element" {
  airline init
  run airline theme set bogus colour1
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

# --- suspend / resume -------------------------------------------------------

@test "suspend sets the flag and traps the prefix; resume restores" {
  airline init
  airline suspend
  run get_option @airline--suspended
  assert_output "1"
  run get_option prefix
  assert_output "None"
  airline resume
  run get_option @airline--suspended
  assert_output "0"
  run get_option prefix
  refute_output "None"              # prefix unset → back to default
}

# --- help -------------------------------------------------------------------

@test "help prints usage" {
  run airline help
  assert_output --partial "airline init"
  assert_output --partial "set <key>"
}
