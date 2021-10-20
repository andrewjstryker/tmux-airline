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
# Generate help message
#
#-----------------------------------------------------------------------------#

usage () {
  local scripname="${1:-airline.tmux}"
  sed --quiet --expression '/CLIHELP/ { s/^.*CLIHELP //; p }' $scripname
}

#-----------------------------------------------------------------------------#
#
# Main CLI
#
#-----------------------------------------------------------------------------#

airline () {
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
  if ! hash tmux 2> /dev/null
  then
    die "tmux not on search path"
  fi

  tmux list-sessions | grep windows > /dev/null ||
    die "Start a tmux session prior to running this script"

  source "$CURRENT_DIR/scripts/api.sh"

  case "$subcmd" in
    apply ) #CLIHELP Apply theme to airline configuration
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
      echo "Help message"
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
