#!/usr/bin/env bash

# Shared test helpers for tmux-airline BATS tests

TMUX=/usr/bin/tmux
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

_bats_socket="bats-airline-$$-${BATS_TEST_NUMBER}"

setup() {
  $TMUX -L "$_bats_socket" new-session -d -s bats
}

teardown() {
  $TMUX -L "$_bats_socket" kill-server 2>/dev/null || true
  rm -f "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/$_bats_socket" 2>/dev/null || true  # don't leak the socket file
}

# Source tmux.sh standalone, with the `tmux` command pointed at the isolated
# server. Lets the mechanical layer be exercised on its own.
load_tmux() {
  tmux() { $TMUX -L "$_bats_socket" "$@"; }
  export -f tmux
  source "$PROJECT_ROOT/lib/tmux.sh"
  # The test process may itself live in an unrelated tmux server. Give the
  # isolated server's native pane context to functions that resolve "current".
  TMUX_PANE="$(tmux display-message -p -t bats '#{pane_id}')"
  export TMUX_PANE
}

# Source the collections layer (collections.sh) on the in-memory fake — no tmux
# server. collections.sh is pure logic over tmux.sh's opt_*; the fake provides
# those leaves (tmux.bats proves the real ones match), so the store round-trips
# without a process. get_option/wopt are redirected to the in-process store.
load_collections() {
  export AIRLINE_DIR="$PROJECT_ROOT"
  source "$PROJECT_ROOT/test/support/fake-tmux.sh"
  source "$PROJECT_ROOT/lib/command.sh"
  source "$PROJECT_ROOT/lib/collections.sh"
  _use_fake_readback
}

# Source the render layer (render.sh) on the in-memory fake — no tmux server.
load_render() {
  export AIRLINE_DIR="$PROJECT_ROOT"
  export AIRLINE_SESSION='s1'
  source "$PROJECT_ROOT/test/support/fake-tmux.sh"
  source "$PROJECT_ROOT/lib/command.sh"
  source "$PROJECT_ROOT/lib/collections.sh"
  source "$PROJECT_ROOT/lib/render.sh"
  _use_fake_readback
}

# Source the signal services over the in-memory store and renderer.
load_signal() {
  load_render
  source "$PROJECT_ROOT/lib/signal.sh"
}

# Source the complete behavior stack on the fake store for session coordination tests.
load_session() {
  export AIRLINE_DIR="$PROJECT_ROOT"
  export AIRLINE_SESSION='s1'
  source "$PROJECT_ROOT/test/support/fake-tmux.sh"
  source "$PROJECT_ROOT/lib/command.sh"
  source "$PROJECT_ROOT/lib/collections.sh"
  source "$PROJECT_ROOT/lib/render.sh"
  source "$PROJECT_ROOT/lib/catalog.sh"
  source "$PROJECT_ROOT/lib/signal.sh"
  source "$PROJECT_ROOT/lib/runner.sh"
  source "$PROJECT_ROOT/lib/layout.sh"
  source "$PROJECT_ROOT/lib/session.sh"
  source "$PROJECT_ROOT/lib/transaction.sh"
  _use_fake_readback
}

# Point the readback helpers at the in-process fake store. The real get_option/wopt
# (below) shell out to a tmux server; on the fake path there is none, so a layer
# test reads the very options the code under test just wrote, through tmux.sh's own
# getters. Same call sites in the .bats files, no server.
_use_fake_readback() {
  get_option() { opt_get_global "$1"; }
  wopt() {
    local name="$1"; shift
    local win="$_FAKE_WIN"
    [[ "${1:-}" == -t ]] && { win="$2"; shift 2; }
    opt_get_window "$win" "$name"
  }
  popt() {
    local name="$1"; shift
    local pane="$_FAKE_PANE"
    [[ "${1:-}" == -t ]] && { pane="$2"; shift 2; }
    opt_get_pane "$pane" "$name"
  }
  sopt() {
    local name="$1"; shift
    local session="$_FAKE_SESSION"
    [[ "${1:-}" == -t ]] && { session="$2"; shift 2; }
    opt_get_session "$session" "$name"
  }
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

# Read a pane option from the isolated server.
popt() {
  local name="$1"; shift
  $TMUX -L "$_bats_socket" show-options -pqv "$@" "$name"
}

# Read a session option from the isolated server (current session unless a target
# follows, e.g. sopt @airline--badge-problem -t '$2').
sopt() {
  local name="$1"; shift
  $TMUX -L "$_bats_socket" show-options -qv "$@" "$name"
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
  local pane
  pane="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{pane_id}')"
  TMUX_PANE="$pane" AIRLINE_DIR="$PROJECT_ROOT" AIRLINE_TMUX="$TMUX -L $_bats_socket" \
    "$PROJECT_ROOT/airline.sh" "$@"
}

# Run the public CLI through a selective tmux failure shim. The shim remains a
# process boundary, so these tests cover the exit status an external caller sees.
airline_with_tmux_failure() {
  local failure="$1" pane; shift
  pane="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{pane_id}')"
  TMUX_PANE="$pane" AIRLINE_DIR="$PROJECT_ROOT" \
    AIRLINE_TMUX="bash $PROJECT_ROOT/test/support/tmux-fail.sh" \
    AIRLINE_TEST_REAL_TMUX="$TMUX" AIRLINE_TEST_TMUX_SOCKET="$_bats_socket" \
    AIRLINE_TEST_TMUX_FAILURE="$failure" \
    "$PROJECT_ROOT/airline.sh" "$@"
}

# Run a config/control-plane command from a pane in an explicit session. TMUX_PANE is
# the same native context tmux supplies to real pane child processes.
airline_session() {
  local session="$1"; shift
  local pane
  pane="$($TMUX -L "$_bats_socket" display-message -p -t "$session" '#{pane_id}')"
  TMUX_PANE="$pane" AIRLINE_DIR="$PROJECT_ROOT" AIRLINE_TMUX="$TMUX -L $_bats_socket" \
    "$PROJECT_ROOT/airline.sh" "$@"
}

# vim: ft=bash
