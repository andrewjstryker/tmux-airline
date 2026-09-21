#!/usr/bin/env bash
#
# help.sh — render CLI help from annotated grammar sections in airline.sh.
#
# Command annotations stay beside their dispatch arms. Explicit `help:begin` and
# `help:end` markers identify each section, so help generation does not depend on
# function names, brace placement, or case indentation.
#
# Two renderings share one parse. `help_grammar` emits tab-delimited records for
# scripts/generate-completions; the `_help_usage`/`_help_entry` path formats the
# same records for people. Both split annotations through `_help_split`, so
# changing human formatting cannot change the compiled grammar.

# Raw tab-delimited command + annotation records from one marked section.
_help_records () {   # <section>
  local section="$1" line marker active="" found="" closed=""
  local arm_re='^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_-]*)\).*#[|][[:space:]]*(.*)$'

  while IFS= read -r line; do
    marker="${line#"${line%%[![:space:]]*}"}"
    if [[ "$marker" == "# help:begin $section" ]]; then
      [[ -z "$active" && -z "$found" ]] || {
        printf "airline: duplicate help section: %s\n" "$section" >&2
        return 1
      }
      active=1
      found=1
      continue
    fi
    if [[ "$marker" == "# help:end $section" ]]; then
      [[ -n "$active" ]] || {
        printf "airline: unmatched help section end: %s\n" "$section" >&2
        return 1
      }
      active=""
      closed=1
      continue
    fi
    if [[ -n "$active" && "$line" =~ $arm_re ]]; then
      printf '%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    fi
  done < "$AIRLINE_HELP_SOURCE"

  [[ -n "$found" && -n "$closed" && -z "$active" ]] || {
    printf "airline: incomplete or missing help section: %s\n" "$section" >&2
    return 1
  }
}

# Split an annotation into its syntax and prose halves. The em-dash delimiter is
# parsed in exactly one place; every consumer reads these two variables.
_help_split () {   # <annotation>; sets _HELP_USAGE and _HELP_DESCRIPTION
  if [[ "$1" == "— "* ]]; then
    _HELP_USAGE=""; _HELP_DESCRIPTION="${1#— }"
  elif [[ "$1" == *" — "* ]]; then
    _HELP_USAGE="${1%% — *}"; _HELP_DESCRIPTION="${1#* — }"
  else
    _HELP_USAGE=""; _HELP_DESCRIPTION="$1"
  fi
}

# Collapse runs of whitespace to single spaces, matching what wrapping produces.
_help_squeeze () {   # <text>
  local -a words=()
  read -r -a words <<< "$1"
  (( ${#words[@]} )) || return 0
  printf '%s' "${words[*]}"
}

# Keep syntax and prose separate, with hanging indents for wrapped lines.
_help_wrap () {   # <first-prefix> <continuation-prefix> <text>
  local line="$1" continuation="$2" word
  local -a words
  read -r -a words <<< "$3"
  for word in "${words[@]}"; do
    if (( ${#line} + ${#word} + 1 > 80 )); then
      printf '%s\n' "${line% }"
      line="$continuation"
    fi
    [[ -z "$line" || "$line" == *' ' ]] || line+=' '
    line+="$word"
  done
  printf '%s\n' "${line% }"
}

_help_entry () {   # <prefix> <annotation> [leaf]
  local prefix="$1" usage description
  _help_split "$2"
  usage="$_HELP_USAGE"; description="$_HELP_DESCRIPTION"
  _help_wrap "$prefix" '    ' "$usage"
  if [[ "${3:-}" == leaf ]]; then
    printf '\n'
    _help_wrap '' '' "${description^}"
  else
    _help_wrap '      ' '      ' "${description^}"
  fi
}

_help_arms () {   # <section>
  local records command annotation
  records="$(_help_records "$1")" || return
  while IFS=$'\t' read -r command annotation; do
    [[ -n "$command" ]] || continue
    _help_entry "  $command" "$annotation"
  done <<< "$records"
}

_help_noun () {   # <noun>
  printf '%s:\n' "$1"
  _help_arms "$1" || return
  case "$1" in
    palette|layout)
      printf '\nNotes:\n  use loads a bare name from a registered dir; register adds a search directory.\n'
      ;;
    status)
      printf '\nNotes:\n  Observed status results clear when you focus away from their pane.\n'
      ;;
    health|problem)
      printf '\nNotes:\n  Reporters supply separate contributor and claim identifiers.\n'
      ;;
  esac
}

_help_annotation () {   # <noun-or-empty> <command>
  local section="${1:-root}" wanted="$2" records command annotation
  records="$(_help_records "$section")" || return
  while IFS=$'\t' read -r command annotation; do
    [[ "$command" == "$wanted" ]] || continue
    printf '%s' "$annotation"
    return 0
  done <<< "$records"
  return 1
}

# One machine-readable record per command path: path<TAB>usage<TAB>description,
# with `@none` standing in for an absent usage. Noun records follow the leaves, in
# command-family order. This is the compilation target for the completion scripts;
# they never read rendered help, so prose formatting is free to change.
_help_grammar_arms () {   # <section> [<path-prefix>]
  local records command annotation usage description
  records="$(_help_records "$1")" || return
  while IFS=$'\t' read -r command annotation; do
    [[ -n "$command" ]] || continue
    _help_split "$annotation"
    usage="$(_help_squeeze "$_HELP_USAGE")"
    description="$(_help_squeeze "$_HELP_DESCRIPTION")"
    # Descriptions are sentences wherever they are shown, here and in help.
    printf '%s\t%s\t%s\n' "${2:+$2 }$command" "${usage:-@none}" "${description^}"
  done <<< "$records"
}

help_grammar () {
  local i n
  _help_grammar_arms root || return
  for (( i=0; i<${#AIRLINE_HELP_GROUP_NOUNS[@]}; i++ )); do
    for n in ${AIRLINE_HELP_GROUP_NOUNS[$i]}; do
      _help_grammar_arms "$n" "$n" || return
    done
  done
  for (( i=0; i<${#AIRLINE_HELP_GROUP_NOUNS[@]}; i++ )); do
    for n in ${AIRLINE_HELP_GROUP_NOUNS[$i]}; do
      printf '%s\t@none\t%s commands\n' "$n" "$n"
    done
  done
}

# Short descriptions for command families; leaf descriptions come from annotations.
_help_summary () {   # <noun>
  case "$1" in
    session) printf '%s' 'Initialize, apply, and suspend session configuration' ;;
    palette) printf '%s' 'Choose and inspect colour palettes' ;;
    segment) printf '%s' 'Inspect status-line segments' ;;
    widget) printf '%s' 'Discover and inspect status-line widgets' ;;
    layout) printf '%s' 'Choose and inspect status-line layouts' ;;
    classifier) printf '%s' 'Discover and inspect result classifiers' ;;
    filter) printf '%s' 'Discover and inspect output filters' ;;
    probe) printf '%s' 'Discover and inspect condition probes' ;;
    runner) printf '%s' 'Discover and launch commands and probes' ;;
    process) printf '%s' 'Inspect and stop active invocations' ;;
    status) printf '%s' 'Manage pane workflow status' ;;
    health) printf '%s' 'Report and inspect pane health' ;;
    problem) printf '%s' 'Track and resolve problem claims' ;;
    transaction) printf '%s' 'Inspect and recover configuration transactions' ;;
  esac
}

_help_usage () {
  printf 'airline — tmux-airline CLI\n\n'
  printf 'Usage: airline <command> [<argument>...]\n\n'
  printf 'Commands:\n'

  local n records command annotation
  for n in $AIRLINE_NOUNS; do
    printf '  %-12s %s\n' "$n" "$(_help_summary "$n")"
  done
  records="$(_help_records root)" || return
  while IFS=$'\t' read -r command annotation; do
    [[ -n "$command" ]] || continue
    _help_split "$annotation"
    printf '  %-12s %s\n' "$command" "${_HELP_DESCRIPTION^}"
  done <<< "$records"
  printf '\nRun airline help <command> for details; for example: airline help session.\n'
}

help_command () {   # [<help|noun> [<verb>]]
  local first="${1:-}" second="${2:-}" annotation usage
  (( $# <= 2 )) || command_die "help: too many command levels"
  # Private build-time entry point: the compiled grammar behind the completions.
  if [[ "$first" == _grammar ]]; then
    (( $# == 1 )) || command_die "help: _grammar takes no arguments"
    help_grammar
    return
  fi
  [[ -n "$first" ]] || { _help_usage; return; }

  case " $AIRLINE_NOUNS " in
    *" $first "*)
      if [[ -z "$second" ]]; then
        printf 'Usage: airline %s <verb> [<argument>...]\n\n' "$first"
        _help_noun "$first" || return
        printf '\nRun airline help %s <verb> for details.\n' "$first"
        return
      fi
      annotation="$(_help_annotation "$first" "$second")" || \
        command_die "help: unknown command '$first $second'"
      ;;
    *)
      [[ -z "$second" ]] || command_die "help: '$first' has no subcommands"
      annotation="$(_help_annotation "" "$first")" || command_die "help: unknown command '$first'"
      ;;
  esac

  usage="Usage: airline $first"
  [[ -z "$second" ]] || usage+=" $second"
  _help_entry "$usage" "$annotation" leaf
}
