#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load

# The build-time architecture lint (DESIGN.md §Enforcement), surfaced in the
# normal `bats test/` run. The grep logic lives in test/lint-architecture.sh so
# `make lint` can call it too; this wraps it with didactic failure messages.
#
# Invariant A is EXPECTED RED until the rework completes: its violation list is
# the worklist (everything in airline.tmux, scripts/record.sh, and the widget
# adapters that still call `tmux` directly). It goes green file-by-file as each
# layer migrates onto tmux.sh's opt_* / verb functions. Invariant B is dormant
# until collections.sh lands.

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

@test "Invariant B — the @airline-* collection layout has one source of truth" {
  # Dormant until collections.sh exists (see lint-architecture.sh / DESIGN.md §B).
  run "$LINT" B
  assert_success
}
