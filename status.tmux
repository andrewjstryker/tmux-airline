#!/usr/bin/env bash
#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-#
#
# status.tmux
#
# tmux-status CLI
#
# This script is a stable command line interface for manipulating
# tmux-status
#
#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-#

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Exit on error. Append "|| true" if you expect an error.
set -o errexit
# Exit on error inside any functions or subshells.
set -o errtrace
# Do not allow use of undefined vars. Use ${VAR:-} to use an undefined VAR
set -o nounset
# Catch the error in case mysqldump fails (but gzip succeeds) in `mysqldump |gzip`
set -o pipefail

#-----------------------------------------------------------------------------#
#
# Helper functions
#
#-----------------------------------------------------------------------------#

die () {
  echo "$@"
  exit 1
}

#-----------------------------------------------------------------------------#
#
# Main CLI
#
#-----------------------------------------------------------------------------#

status () {
  local subcmd="${1:-apply}"
  shift || true

  case "$subcmd" in
    help|--help|-h ) #CLIHELP Show this help message
      usage
      exit 0
      ;;
    version ) #CLIHELP Show version information
      cat "$CURRENT_DIR/version"
      exit 0
      ;;
  esac

  # verify that tmux is available and running
  if ! hash tmux 2>/dev/null
  then 
    die "tmux not on search path"
  fi

  tmux list-sessions | grep windows > /dev/null ||
    die "Start a tmux session prior to running this script"

  source "$CURRENT_DIR/scripts/api.sh"

  case "$subcmd" in
    apply ) #CLIHELP Apply theme to status configuration
      source "${CURRENT_DIR}/scripts/update.sh"
      status_apply
      ;;

    load ) #CLIHELP Load configuation
      status_load "$@"
      ;;

    set ) #CLIHELP Set an status value
      status_set "$@"
      ;;

    show ) #CLIHELP Show an status value
      status_show "$@"
      ;;

    register ) # CLIHELP Register a widget
      status_register "$@"
      ;;

    help | --help | -h ) #CLIHELP Display this help message
      echo "Help message"
      ;;

    * )
      status help
      exit 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" = "${0}" ]]
then
  status "$@"
  exit "$?"
else
  export -f status
fi

# vim: sts=2 sw=2 et
