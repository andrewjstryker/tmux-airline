#!/usr/bin/env bash
#
# airline.tmux — TPM / run-shell entry point.
#
# Holds no logic: it locates the CLI and runs `init`. This is the adapter that
# satisfies the tmux-plugin-manager contract ("source a *.tmux file at startup");
# the real program is `airline.sh`; `airline` is the installable discovery shim.
# Nothing here depends on TPM — anyone can bootstrap the same way by hand.

CURRENT_DIR="${AIRLINE_DIR:-$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )}"

"$CURRENT_DIR/airline.sh" init

# vim: ft=bash
