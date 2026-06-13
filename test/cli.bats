#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load
load helper

# The CLI is the public API. These drive ./airline against the isolated server
# via the AIRLINE_TMUX seam (see helper.bash) — the real path plugins use.

# --- status: register / list / set / clear ----------------------------------

@test "status register adds a lane and rebuilds the window format" {
  airline status register agent ⟳ 20
  run get_option window-status-format
  assert_output --partial "@airline-status-agent"
}

@test "status register is idempotent" {
  airline status register agent ⟳ 20
  airline status register agent ⟳ 20
  run airline status list
  assert_equal "$(printf '%s\n' "$output" | grep -c agent)" "1"
}

@test "status list reports lanes sorted by priority" {
  airline status register agent ⟳ 20
  airline status register ci ⚙ 10
  run airline status list
  # ci (priority 10) before agent (priority 20)
  assert_line --index 0 --partial "ci"
  assert_line --index 1 --partial "agent"
}

@test "status set lights a lane and renders its glyph in the token color" {
  init_theme dark            # so THEME matches the CLI's default (dark) rebuild
  airline status register agent ⟳ 20
  airline status set agent active
  run resolve "$(get_option window-status-format)"
  assert_output --partial "⟳"
  assert_output --partial "fg=${THEME[active]}"
}

@test "status clear removes a lane's badge from the window" {
  airline status register agent ⟳ 20
  airline status set agent active
  airline status clear agent
  run wopt @airline-status-agent
  assert_output ""
}

@test "status badges render in ascending priority order" {
  init_theme dark
  airline status register ci ⚙ 10
  airline status register agent ⟳ 20
  airline status set ci stress
  airline status set agent active
  run resolve "$(get_option window-status-format)"
  # ci's glyph appears before agent's
  [[ "$output" == *"⚙"*"⟳"* ]]
}

@test "status unregister drops the lane from the format" {
  airline status register agent ⟳ 20
  airline status unregister agent
  run airline status list
  refute_output --partial "agent"
  run get_option window-status-format
  refute_output --partial "@airline-status-agent"
}

# --- status: validation ------------------------------------------------------

@test "status set rejects an unknown token" {
  airline status register agent ⟳ 20
  run airline status set agent purple
  assert_failure
  assert_output --partial "invalid token"
}

@test "status set rejects an unregistered lane" {
  run airline status set ghost active
  assert_failure
  assert_output --partial "not registered"
}

@test "status register rejects a bad priority" {
  run airline status register agent ⟳ high
  assert_failure
  assert_output --partial "priority"
}

# --- health: keyed reduce ----------------------------------------------------

@test "health set stores a contributor and reduces to it" {
  airline health set build alert
  run wopt @airline-health
  assert_output "alert"
}

@test "health reduces multiple contributors to the max severity" {
  airline health set build alert
  airline health set ctx stress
  run wopt @airline-health
  assert_output "stress"
}

@test "health ok contributes no badge" {
  airline health set build ok
  run wopt @airline-health
  assert_output ""
}

@test "health clear lowers the reduced severity" {
  airline health set build alert
  airline health set ctx stress
  airline health clear ctx
  run wopt @airline-health
  assert_output "alert"
}

@test "health clearing the last contributor empties the gutter" {
  airline health set build alert
  airline health clear build
  run wopt @airline-health
  assert_output ""
}

@test "health list shows contributors and the reduced result" {
  airline health set build alert
  airline health set ctx stress
  run airline health list
  assert_output --partial "build	alert"
  assert_output --partial "ctx	stress"
  assert_output --partial "reduced	stress"
}

@test "health set rejects a bad severity" {
  run airline health set build warning
  assert_failure
  assert_output --partial "severity"
}

# --- dispatch ----------------------------------------------------------------

@test "unknown command fails with guidance" {
  run airline frobnicate
  assert_failure
  assert_output --partial "unknown command"
}
