#!/usr/bin/env bash
#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-#
#
# airline.tmux
#
# tmux-airline CLI
#
# This script is a stable command line interface for manipulating
# tmux-airline
#
#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-#

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

#-----------------------------------------------------------------------------#
#
# Helper functions
#
#-----------------------------------------------------------------------------#

die () {
  echo "$@" > /dev/stderr
  exit 1
}

#-----------------------------------------------------------------------------#
#
# Main CLI
#
#-----------------------------------------------------------------------------#

airline () {
  local subcmd="${1:-start}"
  shift

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
  [[ ! -x tmux ]] || die "tmux not on search path"
  tmux list-sessions | grep windows > /dev/null ||
    die "Start a tmux session prior to running this script"

  source "$CURRENT_DIR/scripts/api.sh"

  case "$subcmd" in
    apply ) #CLIHELP Apply theme to status configuration
      source "${CURRENT_DIR}/scripts/update.sh"
      airline_apply
      ;;

    load ) #CLIHELP Load configuation
      airline_load "$@"
      ;;

    set ) #CLIHELP Set an airline value
      airline_set "$@"
      ;;

    show ) #CLIHELP Show an airline value
      airline_show "$@"
      ;;

    register ) # CLIHELP Register a widget
      airline_register "$@"
      ;;

    help | --help | -h ) #CLIHELP Display this help message
      usage
      ;;

    * )
      airline help
      exit 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" = "${0}" ]]
then
  airline "$@"
  exit "$?"
else
  export -f airline
fi

# vim: sts=2 sw=2 et
