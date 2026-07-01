#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load

# The build-time architecture lint (DESIGN.md §Enforcement), surfaced in the
# normal `bats test/` run. The grep logic lives in test/lint-architecture.sh so
# `make lint` can call it too; this wraps it with didactic failure messages.
#
# Invariant A is EXPECTED RED until the rework completes: its violation list is
# the worklist (the widget adapters that still call `tmux` directly). It goes green
# file-by-file as each layer migrates onto tmux.sh's opt_* / verb functions.
# Invariant B is GREEN: the @airline- option prefix (both tiers) lives only in
# tmux.sh, behind the pub_* / prv_* accessors and prv_name builder.

LINT="$BATS_TEST_DIRNAME/lint-architecture.sh"

@test "Invariant A — only tmux.sh invokes the tmux binary" {
  run "$LINT" A
  if [[ "$status" -ne 0 ]]; then
    {
      echo "Direct \`tmux\` calls outside the tmux.sh allowlist — the rework worklist."
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
