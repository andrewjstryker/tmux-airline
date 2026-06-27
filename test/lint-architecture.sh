#!/usr/bin/env bash
#
# lint-architecture.sh — the build-time architecture lint (DESIGN.md §Enforcement).
#
# Bash has one global namespace and no visibility modifiers, so the layering is a
# convention. We don't enforce it at runtime; we enforce it here, with a grep,
# and gate it in CI next to shellcheck. test/architecture.bats wraps this so it
# runs in the normal `bats test/` suite; `make lint` can call it directly too.
#
# Two invariants, both grep-able:
#
#   A — only tmux.sh invokes the `tmux` binary. Allowlist: tmux.sh. Everything
#       else reaches tmux only through tmux.sh's opt_* / verb functions.
#   B — the private @airline-* collection layout has one source of truth
#       (collections.sh). Pending until collections.sh lands — see below.
#   C — data files (themes/, bundles/) stay data: no tmux, no set-option, no
#       @airline-, so a theme can't regress into a script behind the CLI.
#
# Usage: test/lint-architecture.sh [A|B|C|all]   (default: all)
# Exit:  0 = clean, 1 = violations (printed, one per line), 2 = bad usage.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Production shell sources the lint governs. Data files (themes/, bundles/) are
# inert and the test tree drives an isolated server through a shim, so neither is
# scanned. Globs that match nothing (e.g. widgets/ before it exists) drop out.
_sources () {
  shopt -s nullglob
  local f
  for f in "$ROOT"/airline "$ROOT"/airline.tmux \
           "$ROOT"/*.sh "$ROOT"/scripts/*.sh "$ROOT"/scripts/plugins/*.sh \
           "$ROOT"/widgets/*.sh; do
    printf '%s\n' "$f"
  done
}

# tmux subcommands airline actually uses. A real call is `tmux` (as its own word)
# followed by one of these, or by a flag (-g, -L, …). Prose that merely mentions
# "tmux" doesn't match — it isn't followed by a subcommand — so comments are safe
# without parsing them out.
_TMUX_VERBS='set-option|show-options|show-option|set-window-option|set-hook|show-hooks|source-file|refresh-client|display-message|bind-key|unbind-key|list-keys|kill-server|new-session|run-shell|set|show|bind|unbind'

# Invariant A — flag every direct tmux invocation outside the allowlist.
_check_a () {
  local f rc=0 hits
  while IFS= read -r f; do
    [[ "$(basename "$f")" == tmux.sh ]] && continue   # the sole allowed caller
    hits="$(grep -nE "(^|[^[:alnum:]_])tmux[[:space:]]+(-[a-zA-Z]|(${_TMUX_VERBS})([[:space:]]|$))" "$f" 2>/dev/null)" || continue
    [[ -z "$hits" ]] && continue
    while IFS= read -r line; do
      # Skip hits on full-line comments — prose may quote an example `tmux …`
      # command (the match is real, the call is not).
      [[ "${line#*:}" =~ ^[[:space:]]*# ]] && continue
      rc=1
      printf 'A: %s:%s\n' "${f#"$ROOT"/}" "$line"
    done <<< "$hits"
  done < <(_sources)
  return $rc
}

# Invariant B — the collection key scheme is built in ONE place. The telltale of
# *constructing* a key is a built name: the printf template `@airline-%s` (the
# registry/tuple builders) or an interpolated key `@airline-status-$…` /
# `@airline-health-$…`. Both belong only in collections.sh; everyone else reaches a
# key through coll_optname / coll_*. A *fixed* scalar like `@airline-health-glyph`
# is fine — it's a named constant, not a constructed key, so the pattern requires a
# `%s` or a `$` after the namespace. (Today this still flags the to-be-replaced
# scripts/record.sh — its worklist entry, green once record.sh is gone.)
_check_b () {
  local f rc=0 hits
  while IFS= read -r f; do
    [[ "$(basename "$f")" == collections.sh ]] && continue   # the one home for the scheme
    hits="$(grep -nE '@airline-(%s|(status|health)-[$])' "$f" 2>/dev/null)" || continue
    [[ -z "$hits" ]] && continue
    while IFS= read -r line; do
      [[ "${line#*:}" =~ ^[[:space:]]*# ]] && continue        # skip comment prose
      rc=1
      printf 'B: %s:%s\n' "${f#"$ROOT"/}" "$line"
    done <<< "$hits"
  done < <(_sources)
  return $rc
}

# Invariant C — data files must contain only data. Configuration flows through
# the CLI/API, so a packaged theme/bundle may not call tmux or name @airline-*.
_check_c () {
  shopt -s nullglob
  local f rc=0 hits
  for f in "$ROOT"/themes/* "$ROOT"/bundles/*; do
    [[ -f "$f" ]] || continue
    hits="$(grep -nE '(\btmux\b|set-option|@airline-)' "$f" 2>/dev/null)" || continue
    [[ -z "$hits" ]] && continue
    rc=1
    while IFS= read -r line; do
      printf 'C: %s:%s\n' "${f#"$ROOT"/}" "$line"
    done <<< "$hits"
  done
  return $rc
}

main () {
  local which="${1:-all}" rc=0
  case "$which" in
    A)   _check_a || rc=1 ;;
    B)   _check_b || rc=1 ;;
    C)   _check_c || rc=1 ;;
    all) _check_a || rc=1; _check_b || rc=1; _check_c || rc=1 ;;
    *)   printf 'usage: %s [A|B|C|all]\n' "$0" >&2; exit 2 ;;
  esac
  return $rc
}

main "$@"
