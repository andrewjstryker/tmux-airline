#!/usr/bin/env bash
#
# lint-architecture.sh — the build-time architecture lint (DESIGN.md §Enforcement).
#
# Bash has one global namespace and no visibility modifiers, so the layering is a
# convention. We don't enforce it at runtime; we enforce it here, with a grep,
# and gate it in CI next to shellcheck. test/architecture.bats wraps this so it
# runs in the normal `make test` suite; `make lint` can call it directly too.
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
#   C — each public root noun delegates to its matching cmd_<noun>, the root noun
#       set matches the help-group registry, and leaf arms delegate only to public
#       owner-prefixed behavior under lib/.
#
# Usage: test/lint-architecture.sh [A|B|C|all]   (default: all)
# Exit:  0 = clean, 1 = violations (printed, one per line), 2 = bad usage.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Application shell the lint governs — including adapters and runner catalogs
# (trusted snippets that must reach tmux only through opt_*). The installable
# `airline` shim is an external bootstrap consumer, so its one @airline-cli lookup
# is outside this layer check.
# Declarative palettes and the test tree are not scanned.
# Globs that match nothing drop out (nullglob).
_sources () {
  shopt -s nullglob
  local f
  for f in "$ROOT"/airline.tmux "$ROOT"/*.sh "$ROOT"/lib/*.sh \
    "$ROOT"/layouts/adapters/* "$ROOT"/layouts/definitions/* "$ROOT"/layouts/helpers/* \
    "$ROOT"/runners/classifiers/* "$ROOT"/runners/filters/* \
    "$ROOT"/runners/probes/* "$ROOT"/runners/definitions/*; do
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

# Read the noun registry as Bash data instead of maintaining a second list in the
# lint. Also verify that every registered noun has a dispatcher definition.
_cli_nouns () {
  AIRLINE_TMUX= AIRLINE_DIR="$ROOT" bash -c '
    source "$1/airline.sh"
    seen=" "
    for noun in $AIRLINE_NOUNS; do
      case "$seen" in
        *" $noun "*) printf "C: duplicate registered noun: %s\n" "$noun" >&2; exit 1 ;;
      esac
      seen+="$noun "
      declare -F "cmd_$noun" >/dev/null || {
        printf "C: missing dispatcher function: cmd_%s\n" "$noun" >&2
        exit 1
      }
    done
    printf "%s\n" "$AIRLINE_NOUNS"
  ' bash "$ROOT"
}

# Enforce the public root grammar without naming any forbidden commands. Between
# the explicit root markers, every ordinary word arm must be `noun) cmd_noun "$@"`.
# Help, option aliases for help, wildcard rejection, and underscore callbacks are
# the deliberate top-level exceptions.
_check_c_root () {
  local nouns line marker arm pattern body expected expected_re seen=" " active="" rc=0 lineno=0 noun
  nouns="$(_cli_nouns)" || return 1

  while IFS= read -r line; do
    (( lineno += 1 ))
    marker="${line#"${line%%[![:space:]]*}"}"
    if [[ "$marker" == '# help:begin root' ]]; then active=1; continue; fi
    if [[ "$marker" == '# help:end root' ]]; then active=""; continue; fi
    [[ -n "$active" && "$marker" == *')'* ]] || continue

    arm="$marker"
    pattern="${arm%%)*}"
    body="${arm#*)}"
    body="${body#"${body%%[![:space:]]*}"}"
    case "$pattern" in
      help|'""|-h|--help'|'*'|_*) continue ;;
    esac
    if [[ ! "$pattern" =~ ^[a-z][a-z0-9-]*$ ]]; then
      printf 'C: airline.sh:%d: invalid public root pattern: %s\n' "$lineno" "$pattern"
      rc=1
      continue
    fi
    expected="cmd_${pattern}"
    expected_re="^${expected}[[:space:]]+\"\\\$@\"[[:space:]]*;;[[:space:]]*$"
    if [[ ! "$body" =~ $expected_re ]]; then
      printf 'C: airline.sh:%d: %s must delegate exactly to %s "$@"\n' \
        "$lineno" "$pattern" "$expected"
      rc=1
    fi
    case " $nouns " in
      *" $pattern "*) ;;
      *) printf 'C: airline.sh:%d: unregistered public noun: %s\n' "$lineno" "$pattern"; rc=1 ;;
    esac
    case "$seen" in
      *" $pattern "*) printf 'C: airline.sh:%d: duplicate root noun: %s\n' "$lineno" "$pattern"; rc=1 ;;
    esac
    seen+="$pattern "
  done < "$ROOT/airline.sh"

  for noun in $nouns; do
    case "$seen" in
      *" $noun "*) ;;
      *) printf 'C: registered noun has no root dispatch: %s\n' "$noun"; rc=1 ;;
    esac
  done
  return "$rc"
}

# Invariant C — validate both delegation hops. Documented leaf arms contain
# exactly one owner-prefixed call, and the parser makes no underscore-private
# behavior calls. Internal command names do not have call syntax.
_check_c () {
  local hits arms rc=0
  _check_c_root || rc=1
  hits="$(grep -nE '(^|[^[:alnum:]_])_[a-zA-Z][a-zA-Z0-9_]*([[:space:]]|;)' "$ROOT/airline.sh" || true)"
  if [[ -n "$hits" ]]; then
    printf 'C: airline.sh:%s\n' "$hits"
    rc=1
  fi
  arms="$(grep -nE '^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_-]*\).*#\|' "$ROOT/airline.sh" \
    | grep -vE '^[0-9]+:[[:space:]]*[a-zA-Z_][a-zA-Z0-9_-]*\)[[:space:]]+((lifecycle|layout|runner)_[a-zA-Z0-9_]+|help_command)([[:space:]]+"\$@")?[[:space:]]*;;[[:space:]]*#\|' || true)"
  if [[ -n "$arms" ]]; then
    printf 'C: airline.sh:%s\n' "$arms"
    rc=1
  fi
  return "$rc"
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
