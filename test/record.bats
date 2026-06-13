#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load
load helper

# The record store primitive (scripts/record.sh), exercised directly.

@test "rec_key builds primary and attribute option names" {
  load_airline
  run rec_key status agent
  assert_output "@airline-status-agent"
  run rec_key status agent glyph
  assert_output "@airline-status-agent-glyph"
}

@test "rec_set / rec_get round-trips a primary value (global)" {
  load_airline
  rec_set -g demo a "" hello
  run rec_get -g demo a ""
  assert_output "hello"
}

@test "rec_get returns the default when unset" {
  load_airline
  run rec_get -g demo missing prio 50
  assert_output "50"
}

@test "rec_set / rec_get round-trips an attribute" {
  load_airline
  rec_set -g demo a prio 20
  run rec_get -g demo a prio
  assert_output "20"
}

@test "rec_add is idempotent and preserves insertion order" {
  load_airline
  rec_add -g demo a
  rec_add -g demo b
  rec_add -g demo a
  run rec_ids -g demo
  assert_output "a b"
}

@test "rec_has reflects membership" {
  load_airline
  rec_add -g demo a
  rec_has -g demo a
  ! rec_has -g demo z
}

@test "rec_del drops from roster and unsets primary + listed attrs" {
  load_airline
  rec_set -g demo a "" v
  rec_set -g demo a prio 10
  rec_add -g demo a
  rec_add -g demo b
  rec_del -g demo a prio
  run rec_ids -g demo
  assert_output "b"
  run rec_get -g demo a ""
  assert_output ""
  run rec_get -g demo a prio 99
  assert_output "99"
}

@test "rec_sorted orders ids by ascending numeric attr (stable)" {
  load_airline
  rec_set -g demo x prio 30; rec_add -g demo x
  rec_set -g demo y prio 10; rec_add -g demo y
  rec_set -g demo z prio 10; rec_add -g demo z
  run rec_sorted -g demo prio
  # y and z tie at 10 (insertion order kept), then x
  assert_output "y
z
x"
}

@test "records can live at window scope" {
  load_airline
  rec_set -w health ctx "" stress
  rec_add -w health ctx
  run rec_get -w health ctx ""
  assert_output "stress"
  run rec_ids -w health
  assert_output "ctx"
}
