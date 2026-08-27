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

# Read-only root command. VERSION is also the source used to create release tags,
# so the public CLI and packaged release cannot acquire independent values.
command_version () {
  (( $# == 0 )) || command_die "version: takes no arguments"
  local version
  IFS= read -r version < "$AIRLINE_DIR/VERSION" || command_die "version: cannot read VERSION"
  printf '%s\n' "$version"
}

# vim: ft=bash
