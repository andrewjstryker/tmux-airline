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
# Subcommands
#
#-----------------------------------------------------------------------------#

load () {
  echo "loading $#"
}

usage () {
  cat << EOF
$0 [subcommand] [subcommand options]...

  help
  init
  load
  set
  show
  update
EOF
}

#-----------------------------------------------------------------------------#
#
# Helper functions
#
#-----------------------------------------------------------------------------#

is-tmux-running () {
  source "$CURRENT_DIR/scripts/verify-tmux.sh"
  verify
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

  # tmux running required below
  if ! is-tmux-running
  then
    echo "tmux must be installed and on the search path"
    exit 1
  fi

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
