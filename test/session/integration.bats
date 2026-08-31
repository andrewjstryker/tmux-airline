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

@test "init publishes its contract, defaults, layout, and rendered bar" {
  airline session init
  run get_option @airline-cli          # public (single dash) — the one published handle
  assert_output --partial "/airline.sh"
  run sopt @airline--defaults-done
  assert_output "1"
  run airline palette show inner-bg
  assert_output "colour234"          # palette use default
  run sopt @airline--palette
  assert_output "default"            # recorded
  run sopt status-left
  assert_output --partial "#S"       # adaptive sets left-out=#S (present with or without plugins)
  run sopt @airline--layout
  assert_output "adaptive"           # recorded, so apply re-applies it

  run sopt status-style
  assert_output --partial "bg=colour234"
  run sopt window-status-current-format
  assert_output --partial "#I:#W"

  run airline session show
  assert_success
  assert_output --partial "layout"      # a top-level record
  assert_output --partial "adaptive"    # active layout remains named
  assert_output --partial "inner-bg"    # recursed into palette show
  assert_output --partial "left-out"    # recursed into segment show
  assert_output --partial "paths:"      # the search paths
  assert_output --partial "/palettes"   # the shipped palette dir on the path
  refute_output --partial "health"      # dynamic per-window nouns excluded from the walk
}

@test "init preserves user configuration and is idempotent" {
  $TMUX -L "$_bats_socket" set -g @airline-inner-bg colour99
  airline session init
  run get_option @airline-inner-bg
  assert_output "colour99"           # user value preserved; default not applied
  $TMUX -L "$_bats_socket" set -g @airline-segment-left-out "CUSTOM"
  airline session init
  run airline segment show left-out
  assert_output "CUSTOM"
  run sopt @airline-segment-left-out
  assert_output ""                  # layout staging never becomes durable public state
}

@test "the global session hook initializes sessions created after airline loads" {
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

@test "rendered palette output remains owned by each session and its windows" {
  $TMUX -L "$_bats_socket" new-session -d -s other
  airline_session bats session init
  airline_session other session init

  airline_session bats palette use dark
  airline_session other palette use light

  bats_session="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{session_id}')"
  other_session="$($TMUX -L "$_bats_socket" display-message -p -t other '#{session_id}')"
  bats_window="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{window_id}')"
  other_window="$($TMUX -L "$_bats_socket" display-message -p -t other '#{window_id}')"

  run sopt window-status-current-format -t "$bats_session"
  assert_output --partial "colour214"
  run sopt window-status-current-format -t "$other_session"
  assert_output --partial "colour136"
  run wopt pane-border-style -t "$bats_window"
  assert_output "fg=colour250"
  run wopt pane-active-border-style -t "$other_window"
  assert_output "fg=colour136"
  run wopt clock-mode-colour -t "$other_window"
  assert_output "colour128"

  new_window="$($TMUX -L "$_bats_socket" new-window -d -P -F '#{window_id}' -t bats:)"
  run wopt pane-border-style -t "$new_window"
  assert_output "fg=colour250"
  run wopt pane-active-border-style -t "$new_window"
  assert_output "fg=colour214"
  run wopt clock-mode-colour -t "$new_window"
  assert_output "colour134"

  # Re-rendering either session must not replace the other's native output.
  airline_session other session apply
  run sopt window-status-current-format -t "$bats_session"
  assert_output --partial "colour214"
  run wopt pane-active-border-style -t "$new_window"
  assert_output "fg=colour214"
}

# --- apply / use ------------------------------------------------------------

@test "apply renders current inputs and show reports the resulting configuration" {
  airline session init
  $TMUX -L "$_bats_socket" set -g @airline-active "colour201"
  airline session apply
  run sopt window-status-current-format
  assert_output --partial "colour201"
  run airline session show
  assert_success
  assert_output --partial "layout"      # a top-level record
  assert_output --partial "adaptive"    # active layout remains named
  assert_output --partial "inner-bg"    # recursed into palette show
  assert_output --partial "left-out"    # recursed into segment show
  assert_output --partial "paths:"      # the search paths
  assert_output --partial "/palettes"   # the shipped palette dir on the path
  refute_output --partial "health"      # dynamic per-window nouns excluded from the walk
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
