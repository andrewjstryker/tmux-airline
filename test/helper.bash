#!/usr/bin/env bash

# Shared test helpers for tmux-airline BATS tests

TMUX=/usr/bin/tmux
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

_bats_socket="bats-airline-$$-${BATS_TEST_NUMBER}"

setup() {
  $TMUX -L "$_bats_socket" new-session -d -s bats
}

teardown() {
  $TMUX -L "$_bats_socket" kill-server 2>/dev/null || true
}

# Source airline.tmux in test mode (no side effects).
# Note: declare -A THEME in airline.tmux becomes local when sourced from
# inside a function, so we re-declare it globally afterward.
load_airline() {
  export AIRLINE_TESTING=1
  export AIRLINE_DIR="$PROJECT_ROOT"
  # Override tmux to target our isolated server
  tmux() { $TMUX -L "$_bats_socket" "$@"; }
  export -f tmux
  source "$PROJECT_ROOT/airline.tmux"
  # Re-declare THEME as a global associative array (the declare -A in
  # airline.tmux was local to this function scope)
  unset THEME
  declare -gA THEME
}

# Load a theme into the isolated tmux server, then populate the THEME
# associative array from the resulting options.
# Usage: init_theme [theme_name]   (defaults to "solarized-dark")
init_theme() {
  local theme="${1:-solarized-dark}"
  load_airline
  $TMUX -L "$_bats_socket" source-file "$PROJECT_ROOT/themes/$theme"

  THEME[outer-bg]=$(get_tmux_option @airline-outer-bg)
  THEME[middle-bg]=$(get_tmux_option @airline-middle-bg)
  THEME[inner-bg]=$(get_tmux_option @airline-inner-bg)
  THEME[secondary]=$(get_tmux_option @airline-secondary)
  THEME[primary]=$(get_tmux_option @airline-primary)
  THEME[emphasized]=$(get_tmux_option @airline-emphasized)
  THEME[active]=$(get_tmux_option @airline-active)
  THEME[special]=$(get_tmux_option @airline-special)
  THEME[alert]=$(get_tmux_option @airline-alert)
  THEME[stress]=$(get_tmux_option @airline-stress)
  THEME[zoom]=$(get_tmux_option @airline-zoom)
  THEME[copy]=$(get_tmux_option @airline-copy)
  THEME[monitor]=$(get_tmux_option @airline-monitor)
}

# Read a global tmux option value from the isolated server
get_option() {
  $TMUX -L "$_bats_socket" show-option -gqv "$1"
}

# vim: ft=bash
