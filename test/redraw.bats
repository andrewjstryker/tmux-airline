#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load
load helper

# The change-check: airline writes — and redraws — only when the value the bar
# renders actually moves ("the stored option is the cache"). The final option
# state is covered by cli.bats; here we assert the *redraw* is skipped on a no-op,
# which is the whole point and otherwise invisible. These drive the airline_*
# functions directly (sourced via load_airline) and stub _redraw to count it.
# register/_airline_rebuild and the transient hook don't call _redraw, so only a
# real set/clear can move the counter.

# Reset the counter and install the stub. _redraw is resolved by name at call
# time, so redefining it after load_airline reaches the airline_* functions.
spy_reset() { _REDRAWS=0; _redraw() { _REDRAWS=$((_REDRAWS + 1)); }; }

@test "status set: redraws on a new token, not on a repeat" {
  load_airline
  airline_status_register agent ●
  spy_reset
  airline_status_set agent monitor
  [ "$_REDRAWS" -eq 1 ]
  airline_status_set agent monitor      # same token → no write, no redraw
  [ "$_REDRAWS" -eq 1 ]
  airline_status_set agent alert        # changed → redraw
  [ "$_REDRAWS" -eq 2 ]
}

@test "status set: a transient-only change does not redraw" {
  load_airline
  airline_status_register agent ●
  spy_reset
  airline_status_set agent ok
  [ "$_REDRAWS" -eq 1 ]
  airline_status_set agent ok --transient   # same glyph, only transient differs
  [ "$_REDRAWS" -eq 1 ]
}

@test "status clear: redraws only when a badge was lit" {
  load_airline
  airline_status_register agent ●
  spy_reset
  airline_status_clear agent            # already clear → no redraw
  [ "$_REDRAWS" -eq 0 ]
  airline_status_set agent monitor      # +1
  airline_status_clear agent            # cleared a lit badge → +1
  [ "$_REDRAWS" -eq 2 ]
}

@test "health set: redraws when the reduced severity moves, not on a repeat" {
  load_airline
  spy_reset
  airline_health_set ctx alert
  [ "$_REDRAWS" -eq 1 ]
  airline_health_set ctx alert          # unchanged → no redraw
  [ "$_REDRAWS" -eq 1 ]
  airline_health_set ctx stress         # worse → redraw
  [ "$_REDRAWS" -eq 2 ]
}

@test "health set: a contributor that doesn't change the max does not redraw" {
  load_airline
  spy_reset
  airline_health_set ctx stress         # reduced = stress → redraw
  [ "$_REDRAWS" -eq 1 ]
  airline_health_set cpu alert          # max still stress → no redraw
  [ "$_REDRAWS" -eq 1 ]
}
