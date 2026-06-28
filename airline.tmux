#!/usr/bin/env bash
#
# airline.tmux — TPM / run-shell entry point.
#
# Holds no logic: it locates the CLI and runs `init`. This is the adapter that
# satisfies the tmux-plugin-manager contract ("source a *.tmux file at startup");
# the real program is the `airline` CLI + the layers it drives (tmux.sh,
# collections.sh, compose.sh). Nothing here depends on TPM — anyone can bootstrap
# the same way by hand: `run-shell "/path/to/airline init"`.

CURRENT_DIR="${AIRLINE_DIR:-$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )}"

"$CURRENT_DIR/airline" init

# vim: ft=bash
