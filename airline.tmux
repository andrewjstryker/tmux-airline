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

source "$CURRENT_DIR/airline-api.sh"
source "$CURRENT_DIR/scripts/shared.sh"

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
# Helper functions
#
#-----------------------------------------------------------------------------#

usage () {
  cat << EOF
$0 [subcommand] [subcommand options]...

  help     Show this help command
  init     Initialize Airline's environment (default)
  load     Load configuration from a file
  set      Set Airline configuration variables
  show     Show Airline configuration values
  update   Update Tmux to match Airline configuration values
EOF
}

#-----------------------------------------------------------------------------#
#
# Main CLI
#
#-----------------------------------------------------------------------------#

main () {
  local subcmd="${1:-update}"
  local init_needed

  init_needed="$(1)"


  case "$subcmd" in
    "help" )
      usage
      exit 0
      ;;
    version ) #CLIHELP Show version information
      cat "$CURRENT_DIR/version"
      exit 0
      ;;
  esac

  # verify that tmux is available and running
  [[ -x tmux ]] || die "tmux not on search path"
  tmux list-sessions | grep windows > /dev/null || die "Start a tmux session prior to running this script"

  exit 0

  case "$subcmd" in
    init ) #CLIHELP Initialize status line values
      init "$@"
      ;;
    load ) #CLIHELP Load a theme
      load "$@"
      ;;
    set )  #CLIHELP Set an airline value
      set-option "$@"
      ;;
    show ) #CLIHELP Show an airline value
      show-option "$@"
      ;;
    * )
      usage
      exit 1
      ;;
  esac
}

main "$@"

# vim: sts=2 sw=2 et
