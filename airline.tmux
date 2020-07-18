#!/usr/bin/env bash
#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-#
#
# airline.tmux
#
# Initialize tmux-airline
#
# This script does the following:
#
#   - Sets the following tmux user variables for building the status line,
#     if not already defined:
#       - @airline-status-left-outer
#       - @airline-status-left-middle
#       - @airline-status-left-inner
#       - @airline-status-right-inner
#       - @airline-status-right-middle
#       - @airline-status-right-outer
#
#   - Sets the following tmux user variables for theming, if not already
#     defined:
#       - @airline-theme-outer
#       - @airline-theme-middle
#       - @airline-theme-inner
#       - @airline-theme-secondary
#       - @airline-theme-primary
#       - @airline-theme-emphasized
#       - @airline-theme-current
#       - @airline-theme-alert
#       - @airline-theme-special
#       - @airline-theme-stress
#       - @airline-theme-copy
#       - @airline-theme-zoom
#       - @airline-theme-monitor
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
# Subcommands
#
#-----------------------------------------------------------------------------#

usage () {
  cat << EOF
$0 [subcommand] [subcommand options]...

  help     Show this help command
  init     Initialize Airline's environment
  load     Load configuration from a file
  set      Set Airline configuration variables
  show     Show Airline configuration values
  update   Update Tmux to match Airline configuration values (default)
EOF
}

#-----------------------------------------------------------------------------#
#
# Main CLI
#
#-----------------------------------------------------------------------------#

airline () {
  local subcmd="${1:-update}"
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
    load ) #CLIHELP Load configuation
      airline_load "$@"
      ;;
    set )  #CLIHELP Set an airline value
      airline_set "$@"
      ;;
    show ) #CLIHELP Show an airline value
      airline_show "$@"
      ;;
    register ) # CLIHELP Register a widget
      airline_register "$@"
      ;;
    update ) #CLIHELP Update status line
      if [[ airline_init_status = "1" ]]
      then
        airline init
      fi

      source "$CURRENT_DIR/scripts/update.sh"
      update "$@"
      ;;
    * )
      usage
      exit 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" = "${0}" ]]
then
  airline "$@"
  exit "$?"
fi

export -f airline

# vim: sts=2 sw=2 et
