#!/usr/bin/env bats

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load
load ../support/helper

# collections.sh — the dynamic keyed-tuple store. Mechanical and domain-free: ns
# and severity ordering are arguments, so tests drive it with arbitrary names.
#
# Runs on the in-memory fake (load_collections) — no tmux server, so override the
# real-server setup/teardown from helper.bash with no-ops.
setup()    { :; }
teardown() { :; }

# --- registry / membership --------------------------------------------------

@test "register adds keys in order and members lists them" {
  load_collections
  session="$(current_session)"
  coll_register session "$session" status build
  coll_register session "$session" status deploy
  run coll_members session "$session" status
  assert_output "build deploy"
}

@test "prepend adds to the front; register to the tail" {
  load_collections
  session="$(current_session)"
  coll_register session "$session" status build      # tail
  coll_prepend session  "$session" status deploy     # head
  run coll_members session "$session" status
  assert_output "deploy build"
}

@test "register is idempotent" {
  load_collections
  session="$(current_session)"
  coll_register session "$session" status build
  coll_register session "$session" status build
  run coll_members session "$session" status
  assert_output "build"
}

@test "members is empty for an untouched collection" {
  load_collections
  run coll_members session "$(current_session)" status
  assert_output ""
}

# --- tuples -----------------------------------------------------------------

@test "set auto-registers and round-trips a multi-field tab tuple" {
  load_collections
  session="$(current_session)"
  coll_set session "$session" status build "●" 20
  run coll_members session "$session" status
  assert_output build                                     # set implies membership
  run coll_get session "$session" status build
  # fields are tab-joined
  assert_output "$(printf '●\t20')"
  # and split back by index
  IFS=$'\t' read -r glyph prio <<< "$(coll_get session "$session" status build)"
  [ "$glyph" = "●" ]
  [ "$prio" = "20" ]
}

@test "get is empty for an unset key" {
  load_collections
  run coll_get session "$(current_session)" status missing
  assert_output ""
}

@test "a key may use a contributor-qualified path" {
  load_collections
  session="$(current_session)"
  coll_set session "$session" health example-agent/context alert
  run coll_members session "$session" health
  assert_output "example-agent/context"
  run coll_get session "$session" health example-agent/context
  assert_output "alert"
}

@test "set overwrites the whole tuple" {
  load_collections
  session="$(current_session)"
  coll_set session "$session" status build "●" 20
  coll_set session "$session" status build "▲" 50
  run coll_get session "$session" status build
  assert_output "$(printf '▲\t50')"
}

# --- unregister -------------------------------------------------------------

@test "unregister drops the key from the registry and unsets its tuple" {
  load_collections
  session="$(current_session)"
  coll_set session "$session" status build "●" 20
  coll_set session "$session" status deploy "■" 30
  coll_unregister session "$session" status build
  run coll_members session "$session" status
  assert_output "deploy"
  run coll_get session "$session" status build
  assert_output ""
}

@test "unregistering the last key clears the registry option" {
  load_collections
  session="$(current_session)"
  coll_set session "$session" status build "●" 20
  coll_unregister session "$session" status build
  run coll_members session "$session" status
  assert_output ""
}

# --- scope independence -----------------------------------------------------

@test "session and window collections are independent" {
  load_collections
  win="$(current_window)"
  session="$(current_session)"
  coll_set session "$session" status build stress "session problem"
  coll_set window "$win" status build ok
  run coll_get session "$session" status build
  assert_output "$(printf 'stress\tsession problem')"
  run coll_get window "$win" status build
  assert_output "ok"
}

@test "global collections retain server-wide ledger state" {
  load_collections
  coll_set global server problem cpu fail active fail "sensors missing"
  run coll_get global server problem cpu
  assert_output "$(printf 'fail\tactive\tfail\tsensors missing')"
  run coll_reduce global server problem "ok warn fail"
  assert_output fail
  coll_unregister global server problem cpu
  run coll_members global server problem
  assert_output ""
}

@test "the same reduction operation accepts session scope" {
  load_collections
  session="$(current_session)"
  coll_set session "$session" sample cpu warn "sensors missing"
  coll_set session "$session" sample battery fail "query timed out"
  run coll_reduce session "$session" sample "ok warn fail"
  assert_output fail

  run coll_reduce invalid owner sample "ok warn fail"
  assert_failure 2
  run coll_reduce global "" sample "ok warn fail"
  assert_failure 2
  run coll_reduce window "" sample "ok warn fail"
  assert_failure 2
}

# --- reduce (max by supplied ordering) --------------------------------------

@test "reduce returns the highest-ranked first field per the given order" {
  load_collections
  win="$(current_window)"
  coll_set window "$win" health cpu ok
  coll_set window "$win" health disk warn
  coll_set window "$win" health net fail
  run coll_reduce window "$win" health "ok warn fail"
  assert_output "fail"
}

@test "reduce ignores values absent from the order, picks max of the rest" {
  load_collections
  win="$(current_window)"
  coll_set window "$win" health cpu ok
  coll_set window "$win" health disk weird   # not in the ranking
  coll_set window "$win" health net warn
  run coll_reduce window "$win" health "ok warn fail"
  assert_output "warn"
}

@test "reduce is empty when no member carries a ranked value" {
  load_collections
  win="$(current_window)"
  coll_set window "$win" health cpu unknown
  run coll_reduce window "$win" health "ok warn fail"
  assert_output ""
}

@test "reduce reads only the first tuple field" {
  load_collections
  win="$(current_window)"
  # second field is a transient flag; ranking must ignore it
  coll_set window "$win" health cpu ok 1
  coll_set window "$win" health net warn
  run coll_reduce window "$win" health "ok warn fail"
  assert_output "warn"
}
