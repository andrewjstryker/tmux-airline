#!/usr/bin/env bash
#
# transaction.sh — public inspection and recovery for transaction markers.
#
# tmux.sh owns transaction mechanics. This module validates the diagnostic CLI
# contract and translates mechanical return codes into user-facing errors.

# shellcheck shell=bash

transaction_show () {
  (( $# == 0 )) || command_die "transaction show: takes no arguments"
  transaction_list
}

transaction_clear_stale () {   # <global|session|window> <target> <namespace>
  local scope="${1:-}" target="${2:-}" namespace="${3:-}" rc=0
  (( $# == 3 )) || command_die \
    "transaction clear: need <global|session|window> <target> <namespace>"
  transaction_clear "$scope" "$target" "$namespace" || rc=$?
  case "$rc" in
    0) ;;
    2) command_die "transaction clear: invalid scope, target, namespace, or marker" ;;
    3) command_die "transaction clear: no such outstanding transaction" ;;
    4) command_die "transaction clear: transaction owner is still active" ;;
    *) command_die "transaction clear: recovery failed" ;;
  esac
}

# vim: ft=bash
