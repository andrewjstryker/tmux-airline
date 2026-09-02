#!/usr/bin/env bash
#
# help.sh — render CLI help from annotated grammar sections in airline.sh.
#
# Command annotations stay beside their dispatch arms. Explicit `help:begin` and
# `help:end` markers identify each section, so help generation does not depend on
# function names, brace placement, or case indentation. The rendered grammar is
# also consumed by scripts/generate-completions.

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

_help_arms () {   # <section>
  local records command annotation
  records="$(_help_records "$1")" || return
  while IFS=$'\t' read -r command annotation; do
    [[ -n "$command" ]] || continue
    if [[ "$annotation" == "— "* ]]; then
      annotation="${annotation#— }"
      annotation="${annotation^}"
    fi
    printf '  %-11s %s\n' "$command" "$annotation"
  done <<< "$records"
}

_help_noun () {   # <noun>
  printf '%s:\n' "$1"
  _help_arms "$1"
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

_help_usage () {
  printf 'airline — tmux-airline CLI\n\n'
  printf 'Usage: airline <noun> <verb> [<argument>...]\n'
  printf '       airline version\n'
  printf '       airline help [<noun> [<verb>]]\n\n'
  printf 'Commands:\n'
  _help_arms root || return

  local i n
  for (( i=0; i<${#AIRLINE_HELP_GROUP_NAMES[@]}; i++ )); do
    printf '\n%s commands\n' "${AIRLINE_HELP_GROUP_NAMES[$i]}"
    for n in ${AIRLINE_HELP_GROUP_NOUNS[$i]}; do
      printf '\n'; _help_noun "$n" || return
    done
  done
  printf '\n  use loads a bare name from a registered dir; register blesses a location.\n'
  printf '  Observed status results clear when you focus away from their pane.\n'
  printf '  Health/problem reporters supply separate contributor and claim identifiers.\n'
}

help_command () {   # [<help|noun> [<verb>]]
  local first="${1:-}" second="${2:-}" annotation usage description
  (( $# <= 2 )) || command_die "help: too many command levels"
  [[ -n "$first" ]] || { _help_usage; return; }

  case " $AIRLINE_NOUNS " in
    *" $first "*)
      if [[ -z "$second" ]]; then
        printf 'Usage: airline %s <verb>\n\n' "$first"
        _help_noun "$first"
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

  if [[ "$annotation" == "— "* ]]; then
    usage=""
    description="${annotation#— }"
  elif [[ "$annotation" == *" — "* ]]; then
    usage="${annotation%% — *}"
    description="${annotation#* — }"
  else
    usage=""
    description="$annotation"
  fi
  printf 'Usage: airline %s' "$first"
  [[ -z "$second" ]] || printf ' %s' "$second"
  [[ -z "$usage" ]] || printf ' %s' "$usage"
  printf '\n\n%s\n' "$description"
}
