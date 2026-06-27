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

# Source tmux.sh standalone, with the `tmux` command pointed at the isolated
# server. Lets the mechanical layer be exercised on its own.
load_tmux() {
  tmux() { $TMUX -L "$_bats_socket" "$@"; }
  export -f tmux
  source "$PROJECT_ROOT/tmux.sh"
}

# Source the collections layer (collections.sh) on top of the mechanical layer
# (tmux.sh), with the `tmux` command pointed at the isolated server.
load_collections() {
  tmux() { $TMUX -L "$_bats_socket" "$@"; }
  export -f tmux
  source "$PROJECT_ROOT/tmux.sh"
  source "$PROJECT_ROOT/collections.sh"
}

# Source the logic layer (compose.sh) on top of the mechanical layer (tmux.sh),
# with the `tmux` command pointed at the isolated server.
load_compose() {
  export AIRLINE_DIR="$PROJECT_ROOT"
  tmux() { $TMUX -L "$_bats_socket" "$@"; }
  export -f tmux
  source "$PROJECT_ROOT/tmux.sh"
  source "$PROJECT_ROOT/compose.sh"
}

# Source airline.tmux in test mode (no side effects). THEME and
# AIRLINE_PALETTE_TOKENS are declared -g in airline.tmux, so they stay global
# even though we source from inside this function.
load_airline() {
  export AIRLINE_TESTING=1
  export AIRLINE_DIR="$PROJECT_ROOT"
  # Override tmux to target our isolated server
  tmux() { $TMUX -L "$_bats_socket" "$@"; }
  export -f tmux
  source "$PROJECT_ROOT/airline.tmux"
}

# Source airline, then populate THEME via airline's own load_theme — the same
# path production uses — so tests exercise the real population logic.
# Usage: init_theme [theme_name]   (defaults to "solarized-dark")
init_theme() {
  load_airline
  load_theme "${1:-solarized-dark}"
}

# Read a global tmux option value from the isolated server
get_option() {
  $TMUX -L "$_bats_socket" show-option -gqv "$1"
}

# Read a window option from the isolated server (current window unless a target
# follows, e.g. wopt @airline-health -t @2)
wopt() {
  local name="$1"; shift
  $TMUX -L "$_bats_socket" show-options -wqv "$@" "$name"
}

# Resolve a built section through the isolated tmux server. Section templates
# are now live #{?...} references, so tests assert on what tmux actually renders
# rather than on the pre-expansion format string.
resolve() {
  $TMUX -L "$_bats_socket" display-message -p "$1"
}

# Run the airline CLI against the isolated server. The CLI is an executed
# process, so the helper's exported tmux() function does not reach it; point it
# at the bats socket via the AIRLINE_TMUX seam instead.
airline() {
  AIRLINE_DIR="$PROJECT_ROOT" AIRLINE_TMUX="$TMUX -L $_bats_socket" \
    "$PROJECT_ROOT/airline" "$@"
}

# vim: ft=bash
