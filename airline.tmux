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
      ;;
    "init" )
      init "$@"
      ;;
    "load" )
      load "$@"
      ;;
    "set" )
      set-option "$@"
      ;;
    "show" )
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
