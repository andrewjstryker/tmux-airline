#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load

# The build-time architecture lint (DESIGN.md §Enforcement), surfaced in the
# normal `make test` run. The grep logic lives in test/lint-architecture.sh so
# `make lint` can call it too; this wraps it with didactic failure messages.
#
# The invariants are GREEN. A — every `tmux` call goes through tmux.sh; the plugin
# adapters (`layouts/adapters/*`) set their options via opt_*, not raw tmux. B — the
# @airline- option prefix (both tiers) lives only in tmux.sh, behind the pub_* /
# prv_* accessors and the prv_name builder. These are now regression guards, not a
# worklist: a red here means a new violation crept in.

LINT="$BATS_TEST_DIRNAME/lint-architecture.sh"

@test "Invariant A — only tmux.sh invokes the tmux binary" {
  run "$LINT" A
  if [[ "$status" -ne 0 ]]; then
    {
      echo "Direct \`tmux\` calls outside tmux.sh violate its mechanical ownership."
      echo "Each must move onto a tmux.sh function (opt_*, redraw, hook_*, key_*, …):"
      echo
      printf '%s\n' "$output" | cut -d: -f2 | sort | uniq -c | sort -rn
      echo
      echo "Full list: test/lint-architecture.sh A"
    } >&2
    return 1
  fi
}

@test "Invariant B — the @airline- prefix has one source of truth" {
  run "$LINT" B
  if [[ "$status" -ne 0 ]]; then
    {
      echo "An @airline- option name is spelled outside tmux.sh. Address airline"
      echo "options by BARE key through the tmux.sh accessors — pub_* (public),"
      echo "prv_* (private), or prv_name to build a name (DESIGN.md §Enforcement B):"
      echo
      printf '%s\n' "$output" | cut -d: -f2 | sort | uniq -c | sort -rn
      echo
      echo "Full list: test/lint-architecture.sh B"
    } >&2
    return 1
  fi
}

@test "Invariant D — private symbols and downward module layers are enforced" {
  run "$LINT" D
  if [[ "$status" -ne 0 ]]; then
    {
      echo "A module referenced another module's private function or called across"
      echo "an upward or same-layer dependency:"
      echo
      printf '%s\n' "$output"
    } >&2
    return 1
  fi
}

@test "Invariant A catches an unknown future tmux subcommand" {
  local fixture="$BATS_TEST_TMPDIR/a"
  mkdir -p "$fixture/lib"
  printf 'probe () { tmux future-command; }\n' > "$fixture/lib/probe.sh"

  run env AIRLINE_LINT_ROOT="$fixture" "$LINT" A
  assert_failure
  assert_output --partial "future-command"
}

@test "Invariant D catches private leakage and a forbidden dependency edge" {
  local fixture="$BATS_TEST_TMPDIR/d"
  mkdir -p "$fixture/lib"
  printf '_render_secret () { :; }\nrender_api () { :; }\nsession_api\n' \
    > "$fixture/lib/render.sh"
  printf 'session_api () { :; }\n' > "$fixture/lib/session.sh"
  printf '_render_secret\n' > "$fixture/lib/layout.sh"

  run env AIRLINE_LINT_ROOT="$fixture" "$LINT" D
  assert_failure
  assert_output --partial "D-private"
  assert_output --partial "D-dependency"
}

@test "Invariant D catches duplicate public symbols in the sourced namespace" {
  local fixture="$BATS_TEST_TMPDIR/d-public"
  mkdir -p "$fixture/lib"
  printf 'shared_service () { :; }\n' > "$fixture/lib/catalog.sh"
  printf 'shared_service () { :; }\n' > "$fixture/lib/render.sh"

  run env AIRLINE_LINT_ROOT="$fixture" "$LINT" D
  assert_failure
  assert_output --partial "D-public: duplicate public symbol shared_service"
}

@test "Invariant D permits a new public call when it still points downward" {
  local fixture="$BATS_TEST_TMPDIR/d-downward"
  mkdir -p "$fixture/lib"
  printf 'session_api () { signal_api; }\n' > "$fixture/lib/session.sh"
  printf 'signal_api () { :; }\n' > "$fixture/lib/signal.sh"

  run env AIRLINE_LINT_ROOT="$fixture" "$LINT" D
  assert_success
}
