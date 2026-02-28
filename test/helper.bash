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

# Load the solarized theme into the isolated tmux server, then
# populate the THEME associative array from the resulting options.
init_theme() {
  load_airline
  $TMUX -L "$_bats_socket" source-file "$PROJECT_ROOT/themes/solarized"

  THEME[outer-bg]=$(get_tmux_option @airline-outer-bg "green")
  THEME[middle-bg]=$(get_tmux_option @airline-middle-bg "green")
  THEME[inner-bg]=$(get_tmux_option @airline-inner-bg "green")
  THEME[secondary]=$(get_tmux_option @airline-secondary "white")
  THEME[primary]=$(get_tmux_option @airline-primary "white")
  THEME[emphasized]=$(get_tmux_option @airline-emphasized "white")
  THEME[active]=$(get_tmux_option @airline-active "yellow")
  THEME[special]=$(get_tmux_option @airline-special "purple")
  THEME[alert]=$(get_tmux_option @airline-alert "orange")
  THEME[stress]=$(get_tmux_option @airline-stress "red")
  THEME[zoom]=$(get_tmux_option @airline-zoom "cyan")
  THEME[copy]=$(get_tmux_option @airline-copy "blue")
  THEME[monitor]=$(get_tmux_option @airline-monitor "grey")
}

# Read a global tmux option value from the isolated server
get_option() {
  $TMUX -L "$_bats_socket" show-option -gqv "$1"
}

# vim: ft=bash
