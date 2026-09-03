#!/usr/bin/env bats

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load
load ../support/helper

# Exercise the public grammar over the in-memory tmux boundary. Unlike
# grammar.bats, these tests retain the real behavior handlers behind dispatch.
setup() {
  export AIRLINE_DIR="$PROJECT_ROOT"
  source "$PROJECT_ROOT/airline.sh"
  source "$PROJECT_ROOT/test/support/fake-tmux.sh"
}

@test "fixed-arity commands reject trailing operands" {
  local argv
  while IFS= read -r argv; do
    run main $argv
    assert_failure
  done <<'CASES'
session apply extra
session suspend extra
session resume extra
session toggle extra
palette show name extra
palette list extra
segment show left-out extra
adapter load /tmp/adapter extra
adapter show extra
adapter list extra
layout show name extra
layout list extra
classifier show basic extra
classifier list extra
filter show tap extra
filter list extra
probe show http extra
probe list extra
runner list extra
CASES
}
