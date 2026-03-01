#!/usr/bin/env bash
AIRLINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
tmux set -g @airline-suspended 0
tmux set -u prefix
tmux set -u key-table
source "$AIRLINE_DIR/airline.tmux"
