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
  run "$LINT" B
  if [[ "$status" -ne 0 ]]; then
    {
      echo "The @airline-<ns> key scheme is built outside collections.sh. Reach keys"
      echo "through coll_optname / coll_* and name fixed scalars as constants instead"
      echo "(DESIGN.md §Enforcement B). Today this is the old scripts/record.sh:"
      echo
      printf '%s\n' "$output" | cut -d: -f2 | sort | uniq -c | sort -rn
      echo
      echo "Full list: test/lint-architecture.sh B"
    } >&2
    return 1
  fi
}

@test "Invariant C — data files (themes/, bundles/) stay data" {
  run "$LINT" C
  if [[ "$status" -ne 0 ]]; then
    {
      echo "Data files calling tmux / setting @airline-* — config must flow through"
      echo "the CLI/API (DESIGN.md §Configuration is API-only). Migrate these to"
      echo "semantic '<key> <value>' lines consumed by 'theme use' / 'bundle use':"
      echo
      printf '%s\n' "$output" | cut -d: -f2 | sort | uniq -c | sort -rn
      echo
      echo "Full list: test/lint-architecture.sh C"
    } >&2
    return 1
  fi
}
