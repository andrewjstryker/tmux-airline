#! /usr/bin/env bash
#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-#
#
# Initialize airline
#
# This consists of:
#   1. Loading a user specified theme or the default
#   2. Loading a user specified status configuration or the default
#   3. Launching a job that periodically updates Tmux
#
#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-#


init () {
  local group="${1:-all}"
  local config="${2:-default}"

  debug "Call init for ${group}: $*"

  case "${group}" in
    theme )
      [[ -z "$(airline show theme)" ]] && airline load theme "${config}"
      ;;

    status )
      [[ -z "$(airline show status)" ]] && airline load status "${config}"
      ;;

    all )
      init "theme"
      init "status"
      ;;

    help | --help | -h )
      echo "Help message"
      ;;

    * )
      init help
      exit 2
      ;;
  esac
}

# vim: sts=2 sw=2 et
