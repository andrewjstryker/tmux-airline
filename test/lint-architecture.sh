#!/usr/bin/env bash
#
# lint-architecture.sh — the build-time architecture lint (DESIGN.md §Enforcement).
#
# Bash has one global namespace and no visibility modifiers, so the layering is a
# convention. We don't enforce it at runtime; we enforce it here, with a grep,
# and gate it in CI next to shellcheck. test/architecture.bats wraps this so it
# runs in the normal `bats test/` suite; `make lint` can call it directly too.
#
# Three invariants, all grep-able:
#
#   A — only tmux.sh invokes the `tmux` binary. Allowlist: tmux.sh. Everything
#       else reaches tmux only through tmux.sh's opt_* / verb functions.
#   B — the @airline- option prefix (both tiers, public @airline- and private
#       @airline--) lives in ONE place: tmux.sh, which owns the pub_* / prv_*
#       accessors and the prv_name builder. Everything above addresses airline
#       options by BARE key through those, so a literal @airline- option name in
#       any other source is a layering violation. (Palette/segment data files spell
#       @airline- — that is the public contract — but they aren't scanned.)
#   C — airline's parser delegates only to public api_* functions. Its own _help_*
#       helpers are parser mechanics; all other private behaviour stays in api.sh.
#
# Usage: test/lint-architecture.sh [A|B|C|all]   (default: all)
# Exit:  0 = clean, 1 = violations (printed, one per line), 2 = bad usage.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Application shell the lint governs — including adapters/* (bash snippets that must
# reach tmux only through opt_*). The installable bin/airline shim is an external
# bootstrap consumer, so its one @airline-cli lookup is outside this layer check.
# Data/interpreted files (palettes/, layouts/) and the test tree are not scanned.
# Globs that match nothing drop out (nullglob).
_sources () {
  shopt -s nullglob
  local f
  for f in "$ROOT"/airline "$ROOT"/airline.tmux "$ROOT"/*.sh "$ROOT"/adapters/*; do
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

# Invariant B — the @airline- prefix lives only in tmux.sh. The telltale of an
# option NAME (vs prose) is a key character right after the prefix: a letter, or a
# `%`/`$` for a constructed name. So the pattern is `@airline-` + an optional second
# dash (the private tier) + one of [a-z%$]:
#   matches:  @airline-inner-bg   @airline--badge-status   @airline--%s   @airline--$x
#   skips:    @airline-*  @airline-<el>  @airline--<ns>     (documentation prose)
# tmux.sh is the sole home (pub_* / prv_* / prv_name); a hit anywhere else means a
# layer spelled a prefix instead of using a bare-key accessor.
_check_b () {
  local f rc=0 hits
  while IFS= read -r f; do
    [[ "$(basename "$f")" == tmux.sh ]] && continue          # the one home for the prefix
    hits="$(grep -nE '@airline--?[a-z%$]' "$f" 2>/dev/null)" || continue
    [[ -z "$hits" ]] && continue
    while IFS= read -r line; do
      [[ "${line#*:}" =~ ^[[:space:]]*# ]] && continue        # skip comment prose
      rc=1
      printf 'B: %s:%s\n' "${f#"$ROOT"/}" "$line"
    done <<< "$hits"
  done < <(_sources)
  return $rc
}

# Invariant C — no private behaviour call from the CLI parser. Ignore the two
# parser-owned help helpers; internal command names do not have call syntax.
_check_c () {
  local hits
  hits="$(grep -nE '(^|[^[:alnum:]_])_[a-zA-Z][a-zA-Z0-9_]*([[:space:]]|;)' "$ROOT/airline" \
    | grep -vE '_help_(arms|noun)' || true)"
  [[ -z "$hits" ]] && return 0
  printf 'C: airline:%s\n' "$hits"
  return 1
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
