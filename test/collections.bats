#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load
load helper

# collections.sh — the dynamic keyed-tuple store for status and health, exercised
# directly against an isolated server. Mechanical and domain-free: ns and the
# severity ordering are arguments, so the tests drive it with arbitrary names.

# --- registry / membership --------------------------------------------------

@test "register adds keys in order; members lists them; has tests membership" {
  load_collections
  coll_register_global status build
  coll_register_global status deploy
  run coll_members_global status
  assert_output "build deploy"
  coll_has_global status build
  ! coll_has_global status nope
}

@test "register is idempotent" {
  load_collections
  coll_register_global status build
  coll_register_global status build
  run coll_members_global status
  assert_output "build"
}

@test "members is empty for an untouched collection" {
  load_collections
  run coll_members_global status
  assert_output ""
}

# --- tuples -----------------------------------------------------------------

@test "set auto-registers and round-trips a multi-field tab tuple" {
  load_collections
  coll_set_global status build "●" 20
  coll_has_global status build               # set implies membership
  run coll_get_global status build
  # fields are tab-joined
  assert_output "$(printf '●\t20')"
  # and split back by index
  IFS=$'\t' read -r glyph prio <<< "$(coll_get_global status build)"
  [ "$glyph" = "●" ]
  [ "$prio" = "20" ]
}

@test "get is empty for an unset key" {
  load_collections
  run coll_get_global status missing
  assert_output ""
}

@test "a key may contain dashes" {
  load_collections
  coll_set_global health agent-7 alert
  run coll_members_global health
  assert_output "agent-7"
  run coll_get_global health agent-7
  assert_output "alert"
}

@test "set overwrites the whole tuple" {
  load_collections
  coll_set_global status build "●" 20
  coll_set_global status build "▲" 50
  run coll_get_global status build
  assert_output "$(printf '▲\t50')"
}

# --- unregister -------------------------------------------------------------

@test "unregister drops the key from the registry and unsets its tuple" {
  load_collections
  coll_set_global status build "●" 20
  coll_set_global status deploy "■" 30
  coll_unregister_global status build
  run coll_members_global status
  assert_output "deploy"
  run coll_get_global status build
  assert_output ""
  ! coll_has_global status build
}

@test "unregistering the last key clears the registry option" {
  load_collections
  coll_set_global status build "●" 20
  coll_unregister_global status build
  run coll_members_global status
  assert_output ""
}

# --- scope independence -----------------------------------------------------

@test "global and window collections are independent" {
  load_collections
  win="$(current_window)"
  coll_set_global status build "●" 20
  coll_set_window "$win" status build ok
  run coll_members_global status
  assert_output "build"
  run coll_get_global status build
  assert_output "$(printf '●\t20')"
  run coll_get_window "$win" status build
  assert_output "ok"
}

# --- reduce (max by supplied ordering) --------------------------------------

@test "reduce returns the highest-ranked first field per the given order" {
  load_collections
  win="$(current_window)"
  coll_set_window "$win" health cpu ok
  coll_set_window "$win" health disk alert
  coll_set_window "$win" health net stress
  run coll_reduce_window "$win" health "ok alert stress"
  assert_output "stress"
}

@test "reduce ignores values absent from the order, picks max of the rest" {
  load_collections
  win="$(current_window)"
  coll_set_window "$win" health cpu ok
  coll_set_window "$win" health disk weird   # not in the ranking
  coll_set_window "$win" health net alert
  run coll_reduce_window "$win" health "ok alert stress"
  assert_output "alert"
}

@test "reduce is empty when no member carries a ranked value" {
  load_collections
  win="$(current_window)"
  coll_set_window "$win" health cpu unknown
  run coll_reduce_window "$win" health "ok alert stress"
  assert_output ""
}

@test "reduce reads only the first tuple field" {
  load_collections
  win="$(current_window)"
  # second field is a transient flag; ranking must ignore it
  coll_set_window "$win" health cpu ok 1
  coll_set_window "$win" health net alert
  run coll_reduce_window "$win" health "ok alert stress"
  assert_output "alert"
}
