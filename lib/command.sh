#!/usr/bin/env bash
#
# command.sh — small shared command-boundary utilities.
#
# These functions contain no domain behavior. They give CLI-facing modules one
# error convention, explicit current-session resolution, and consistent show rows.

# shellcheck shell=bash

command_die () { printf 'airline: %s\n' "$*" >&2; exit 2; }

# An inherited AIRLINE_SESSION is layout output, not a hidden user target seam.
command_current_session () {
  local session
  session="$(current_session)"
  [[ -n "$session" ]] || command_die "cannot resolve current session"
  printf '%s' "$session"
}

command_show_row () { printf '%-12s %s\n' "$1" "$2"; }

# vim: ft=bash
