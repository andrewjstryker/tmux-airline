#!/usr/bin/env bash
AIRLINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
tmux set -g @airline-suspended 1
tmux set -g prefix None
tmux set -g key-table off
source "$AIRLINE_DIR/airline.tmux"
