#!/usr/bin/env bats

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load
load ../support/helper

# The CLI boundary (`airline.sh`) on the real integration stack. These drive the
# CLI as a subprocess (the `airline()` helper points it at the isolated server
# via AIRLINE_TMUX), so they exercise the same path production uses.
#
# A clean server (-f /dev/null) so `init`'s default-seeding isn't perturbed by the
# developer's own ~/.tmux.conf (which may already configure airline).

setup() {
  $TMUX -L "$_bats_socket" -f /dev/null new-session -d -s bats
}

# --- init -------------------------------------------------------------------

@test "init publishes the CLI path as the public bootstrap handle + sets the sentinel" {
  airline session init
  run get_option @airline-cli          # public (single dash) — the one published handle
  assert_output --partial "/airline.sh"
  run sopt @airline--defaults-done
  assert_output "1"
}

@test "init applies the default palette when no palette is set" {
  airline session init
  run airline palette show inner-bg
  assert_output "colour234"          # palette use default
  run sopt @airline--palette
  assert_output "default"            # recorded
}

@test "init applies the adaptive layout (segments) when none is set" {
  airline session init
  run sopt status-left
  assert_output --partial "#S"       # adaptive sets left-out=#S (present with or without plugins)
  run sopt @airline--layout
  assert_output "adaptive"           # recorded, so apply re-applies it
}

@test "init does not clobber a user-set palette" {
  $TMUX -L "$_bats_socket" set -g @airline-inner-bg colour99
  airline session init
  run get_option @airline-inner-bg
  assert_output "colour99"           # user value preserved; default not applied
}

@test "init is idempotent and refreshes global segment configuration" {
  airline session init
  $TMUX -L "$_bats_socket" set -g @airline-segment-left-out "CUSTOM"
  airline session init
  run airline segment show left-out
  assert_output "CUSTOM"
  run sopt @airline-segment-left-out
  assert_output ""                  # layout staging never becomes durable public state
}

@test "init composes the bar (chrome + window formats)" {
  airline session init
  run sopt status-style
  assert_output --partial "bg=colour234"
  run get_option window-status-current-format
  assert_output --partial "#I:#W"
}

@test "the global lifecycle hook initializes sessions created after airline loads" {
  airline session init
  $TMUX -L "$_bats_socket" new-session -d -s later
  later="$($TMUX -L "$_bats_socket" display-message -p -t later '#{session_id}')"

  value=""
  # The production hook is intentionally asynchronous so creating a session is
  # never held up by palette/layout work. Allow for a loaded CI host here.
  for _ in {1..200}; do
    value="$(sopt @airline--defaults-done -t "$later")"
    [[ "$value" == 1 ]] && break
    sleep 0.05
  done
  assert_equal "$value" "1"
  run sopt @airline--palette -t "$later"
  assert_output "default"
}

# --- apply / use ------------------------------------------------------------

@test "apply renders from the current source of truth" {
  airline session init
  $TMUX -L "$_bats_socket" set -g @airline-active "colour201"
  airline session apply
  run get_option window-status-current-format
  assert_output --partial "colour201"
}

@test "show reports the active config and recurses into the static nouns" {
  airline session init
  run airline session show
  assert_success
  assert_output --partial "layout"      # a top-level record
  assert_output --partial "default"     # its active value
  assert_output --partial "inner-bg"    # recursed into palette show
  assert_output --partial "left-out"    # recursed into segment show
  assert_output --partial "paths:"      # the search paths
  assert_output --partial "/palettes"   # the shipped palette dir on the path
  refute_output --partial "health"      # dynamic per-window nouns excluded from the walk
}

@test "status and health accept a pane target and store on its containing window" {
  airline session init
  pane="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{pane_id}')"
  window="$($TMUX -L "$_bats_socket" display-message -p -t "$pane" '#{window_id}')"

  airline status set agent active -t "$pane"
  airline health set agent warn -t "$pane"

  run wopt @airline--badge-status -t "$window"
  assert_output "active"
  run wopt @airline--badge-health -t "$window"
  assert_output "warn"
}

@test "problem contributors reduce to one session badge and recover independently" {
  airline session init
  session="$($TMUX -L "$_bats_socket" display-message -p '#{session_id}')"
  airline problem set "$session" cpu warn "required program 'sensors' was not found"
  airline problem set "$session" battery fail "battery query timed out"
  run sopt @airline--badge-problem -t "$session"
  assert_output "fail"
  run $TMUX -L "$_bats_socket" display-message -p -t "$session" '#{E:status-right}'
  assert_output --partial "▲"       # the session scalar drives the extreme-right glyph

  $TMUX -L "$_bats_socket" new-session -d -s other
  other="$($TMUX -L "$_bats_socket" display-message -p -t other '#{session_id}')"
  run sopt @airline--badge-problem -t "$other"
  assert_output ""                  # no server-global leakage into another session
  run $TMUX -L "$_bats_socket" display-message -p -t "$other" '#{E:status-right}'
  refute_output --partial "▲"

  run airline problem show "$session"
  assert_output --partial "cpu"
  assert_output --partial "sensors"
  assert_output --partial "battery"
  assert_output --partial "battery query timed out"

  airline problem clear "$session" battery
  run sopt @airline--badge-problem -t "$session"
  assert_output "warn"
  airline problem clear "$session" cpu
  run sopt @airline--badge-problem -t "$session"
  assert_output ""
}

@test "bare problem show lists problems across sessions" {
  airline session init
  session="$($TMUX -L "$_bats_socket" display-message -p '#{session_id}')"
  $TMUX -L "$_bats_socket" new-session -d -s other
  other="$($TMUX -L "$_bats_socket" display-message -p -t other '#{session_id}')"
  airline problem set "$session" cpu warn "sensors missing"
  airline problem set "$other" battery fail "battery unavailable"

  run airline problem show
  assert_success
  assert_output --partial "$session:"
  assert_output --partial "cpu"
  assert_output --partial "$other:"
  assert_output --partial "battery"
}

@test "lock diagnostics are empty normally and clear rejects a missing lock" {
  airline session init
  session="$($TMUX -L "$_bats_socket" display-message -p '#{session_id}')"

  run airline lock show
  assert_success
  assert_output ""

  run airline lock clear session "$session" problem
  assert_failure
  assert_output --partial "no such outstanding transaction"
}

@test "a --transient signal arms the focus hook and clears publicly" {
  airline session init
  win="$($TMUX -L "$_bats_socket" display-message -p '#{window_id}')"
  airline status set build active                 # persistent
  airline status set review attention --transient # transient
  run get_option focus-events
  assert_output "on"
  airline signal clear-transient -t "$win"
  run wopt @airline--badge-status
  assert_output "active"             # transient 'review' gone, persistent 'build' remains
}

# --- session state (active/suspended) ---------------------------------------

@test "session suspend traps the prefix; resume restores; show reads the state" {
  airline session init
  run airline session show state
  assert_output "active"            # default
  airline session suspend
  run sopt prefix
  assert_output "None"              # prefix trapped
  run airline session show state
  assert_output "suspended"
  airline session resume
  run sopt prefix
  refute_output "None"              # released → back to default
  run airline session show state
  assert_output "active"
}
