#!/usr/bin/env bash
#
# Build-time architecture checks (DESIGN.md §Enforcement).
#
# A — only tmux.sh may invoke the tmux command.
# B — only tmux.sh may construct literal airline option names.
# D — module-private functions stay private and public module calls point to a
#     lower architectural layer. `command` is the shared boundary helper.

set -u

ROOT="${AIRLINE_LINT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

_sources () {
  shopt -s nullglob
  local file
  for file in "$ROOT"/airline.tmux "$ROOT"/*.sh "$ROOT"/lib/*.sh \
    "$ROOT"/layouts/adapters/* "$ROOT"/layouts/definitions/* \
    "$ROOT"/layouts/helpers/* "$ROOT"/runners/classifiers/* \
    "$ROOT"/runners/filters/* "$ROOT"/runners/probes/* \
    "$ROOT"/runners/definitions/*; do
    printf '%s\n' "$file"
  done
}

_module_sources () {
  shopt -s nullglob
  [[ ! -f "$ROOT/airline.sh" ]] || printf '%s\n' "$ROOT/airline.sh"
  printf '%s\n' "$ROOT"/lib/*.sh
}

_module_name () {
  local name="${1##*/}"
  printf '%s' "${name%.sh}"
}

# Print non-comment source hits. Patterns operate on shell identifiers or literal
# namespaces, so full-line comments are the only prose exclusion required.
_code_hits () {   # <extended-regex> <file>
  local pattern="$1" file="$2" line
  grep -nE "$pattern" "$file" 2>/dev/null | while IFS= read -r line; do
    [[ "${line#*:}" =~ ^[[:space:]]*# ]] || printf '%s\n' "$line"
  done
}

_check_a () {
  local file hits line rc=0
  while IFS= read -r file; do
    [[ "$(basename "$file")" == tmux.sh ]] && continue
    hits="$(_code_hits '(^|[^[:alnum:]_])tmux([[:space:]]|$)' "$file")"
    [[ -z "$hits" ]] && continue
    while IFS= read -r line; do
      # airline.sh may define the test/advanced tmux seam; a function definition
      # is not an invocation of the binary.
      [[ "${line#*:}" =~ ^[[:space:]]*tmux[[:space:]]*\(\) ]] && continue
      printf 'A: %s:%s\n' "${file#"$ROOT"/}" "$line"
      rc=1
    done <<< "$hits"
  done < <(_sources)
  return "$rc"
}

_check_b () {
  local file hits rc=0
  while IFS= read -r file; do
    [[ "$(basename "$file")" == tmux.sh ]] && continue
    hits="$(_code_hits '@airline--?[a-z%$]' "$file")"
    [[ -z "$hits" ]] && continue
    printf '%s\n' "$hits" | while IFS= read -r line; do
      printf 'B: %s:%s\n' "${file#"$ROOT"/}" "$line"
    done
    rc=1
  done < <(_sources)
  return "$rc"
}

_module_layer () {   # <module> -> integer; callers must be greater than providers
  case "$1" in
    tmux)                printf 0 ;;
    collections)         printf 1 ;;
    catalog|render)      printf 2 ;;
    signal)              printf 3 ;;
    layout|runner)       printf 4 ;;
    help|session|transaction) printf 5 ;;
    airline)             printf 6 ;;
    *)                   return 1 ;;
  esac
}

_check_d () {
  local provider symbol previous file line raw caller provider_name caller_layer provider_layer rc=0
  local -a modules=()
  declare -A private_owner=() public_owner=()
  while IFS= read -r file; do modules+=("$file"); done < <(_module_sources)

  for provider in "$ROOT"/lib/*.sh; do
    [[ -f "$provider" ]] || continue
    while IFS= read -r symbol; do
      [[ -n "$symbol" ]] || continue
      previous="${private_owner[$symbol]:-}"
      if [[ -n "$previous" && "$previous" != "$provider" ]]; then
        printf 'D-private: duplicate private symbol %s in %s and %s\n' \
          "$symbol" "${previous#"$ROOT"/}" "${provider#"$ROOT"/}"
        rc=1
      fi
      private_owner[$symbol]="$provider"
    done < <(sed -nE 's/^(_[a-zA-Z][a-zA-Z0-9_]*)[[:space:]]*\(\).*/\1/p' "$provider")
    while IFS= read -r symbol; do
      [[ -n "$symbol" ]] || continue
      previous="${public_owner[$symbol]:-}"
      if [[ -n "$previous" && "$previous" != "$provider" ]]; then
        printf 'D-public: duplicate public symbol %s in %s and %s\n' \
          "$symbol" "${previous#"$ROOT"/}" "${provider#"$ROOT"/}"
        rc=1
      fi
      public_owner[$symbol]="$provider"
    done < <(sed -nE 's/^([a-zA-Z][a-zA-Z0-9_]*)[[:space:]]*\(\).*/\1/p' "$provider")
  done

  while IFS=$'\t' read -r file line symbol raw; do
    provider="${private_owner[$symbol]:-}"
    if [[ -n "$provider" && "$file" != "$provider" ]]; then
      printf 'D-private: %s defines %s; referenced by %s:%s:%s\n' \
        "${provider#"$ROOT"/}" "$symbol" "${file#"$ROOT"/}" "$line" "$raw"
      rc=1
    fi

    provider="${public_owner[$symbol]:-}"
    [[ -n "$provider" && "$file" != "$provider" ]] || continue
    caller="$(_module_name "$file")"
    provider_name="$(_module_name "$provider")"
    # CLI/context helpers are deliberately callable from every layer. Their own
    # only lower dependency is the mechanical context-resolution boundary.
    [[ "$provider_name" == command ]] && continue
    [[ "$caller" == command && "$provider_name" == tmux ]] && continue
    caller_layer="$(_module_layer "$caller")" || caller_layer=-1
    provider_layer="$(_module_layer "$provider_name")" || provider_layer=-1
    (( caller_layer > provider_layer )) && continue
    printf 'D-dependency: %s -> %s via %s at %s:%s:%s\n' \
      "$caller" "$provider_name" "$symbol" "${file#"$ROOT"/}" "$line" "$raw"
    rc=1
  done < <(awk '
    function uncomment(text,    out, i, char, previous, single, doubleq, escaped) {
      out=""
      for (i=1; i<=length(text); i++) {
        char=substr(text, i, 1)
        previous=(i == 1 ? "" : substr(text, i - 1, 1))
        if (escaped) { out=out char; escaped=0; continue }
        if (char == "\\" && !single) { out=out char; escaped=1; continue }
        if (char == "\047" && !doubleq) { single=!single; out=out char; continue }
        if (char == "\"" && !single) { doubleq=!doubleq; out=out char; continue }
        if (char == "#" && !single && !doubleq && (i == 1 || previous ~ /[[:space:];&|()]/))
          break
        out=out char
      }
      return out
    }
    {
      raw=$0
      code=uncomment(raw)
      while (match(code, /[a-zA-Z_][a-zA-Z0-9_]*/)) {
        symbol=substr(code, RSTART, RLENGTH)
        after=substr(code, RSTART + RLENGTH, 1)
        if (after == "" || after ~ /[[:space:];&|)]/)
          printf "%s\t%d\t%s\t%s\n", FILENAME, FNR, symbol, raw
        code=substr(code, RSTART + RLENGTH)
      }
    }
  ' "${modules[@]}")
  return "$rc"
}

main () {
  local which="${1:-all}" rc=0
  case "$which" in
    A) _check_a || rc=1 ;;
    B) _check_b || rc=1 ;;
    D) _check_d || rc=1 ;;
    all) _check_a || rc=1; _check_b || rc=1; _check_d || rc=1 ;;
    *) printf 'usage: %s [A|B|D|all]\n' "$0" >&2; exit 2 ;;
  esac
  return "$rc"
}

main "$@"
