#!/usr/bin/env bash
#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-#
# api.sh
#
# Provide an API to theme elements and templates.
#
# This API hides the implementation details of managing themes. The biggest
# benefit is that the API records when theme elements changed. Thus, the airline
# plugin only recomputes status-(left,right) when needed.
#
#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-#

#-----------------------------------------------------------------------------#
#
# Use defensive BASH settings
#
# From the Bash 3 Boilerplate project
#
#-----------------------------------------------------------------------------#

# Exit on error. Append "|| true" if you expect an error.
set -o errexit
# Exit on error inside any functions or subshells.
set -o errtrace
# Do not allow use of undefined vars. Use ${VAR:-} to use an undefined VAR
set -o nounset
# Catch the error in case mysqldump fails (but gzip succeeds) in `mysqldump |gzip`
set -o pipefail

# Define the environment variables (and their defaults) that this script depends on
LOG_LEVEL="${LOG_LEVEL:-6}" # 7 = debug -> 0 = emergency
NO_COLOR="${NO_COLOR:-}"    # true = disable color. otherwise autodetected

#-----------------------------------------------------------------------------#
#
# Define logging functions
#
# TODO: Modified from the Bash 3 Boilerplate project for Tmux logging
#
#-----------------------------------------------------------------------------#

function __b3bp_log () {
  local log_level="${1}"
  shift

  # shellcheck disable=SC2034
  local color_debug="\\x1b[35m"
  # shellcheck disable=SC2034
  local color_info="\\x1b[32m"
  # shellcheck disable=SC2034
  local color_notice="\\x1b[34m"
  # shellcheck disable=SC2034
  local color_warning="\\x1b[33m"
  # shellcheck disable=SC2034
  local color_error="\\x1b[31m"
  # shellcheck disable=SC2034
  local color_critical="\\x1b[1;31m"
  # shellcheck disable=SC2034
  local color_alert="\\x1b[1;37;41m"
  # shellcheck disable=SC2034
  local color_emergency="\\x1b[1;4;5;37;41m"

  local colorvar="color_${log_level}"

  local color="${!colorvar:-${color_error}}"
  local color_reset="\\x1b[0m"

  if [[ "${NO_COLOR:-}" = "true" ]] || { [[ "${TERM:-}" != "xterm"* ]] && [[ "${TERM:-}" != "screen"* ]]; } || [[ ! -t 2 ]]; then
    if [[ "${NO_COLOR:-}" != "false" ]]; then
      # Don't use colors on pipes or non-recognized terminals
      color=""; color_reset=""
    fi
  fi

  # all remaining arguments are to be printed
  local log_line=""

  while IFS=$'\n' read -r log_line; do
    echo -e "$(date -u +"%Y-%m-%d %H:%M:%S UTC") ${color}$(printf "[%9s]" "${log_level}")${color_reset} ${log_line}" 1>&2
  done <<< "${@:-}"
}

function emergency () {                                  __b3bp_log emergency "${@}"; exit 1; }
function alert ()     { [[ "${LOG_LEVEL:-0}" -ge 1 ]] && __b3bp_log alert "${@}"; true; }
function critical ()  { [[ "${LOG_LEVEL:-0}" -ge 2 ]] && __b3bp_log critical "${@}"; true; }
function error ()     { [[ "${LOG_LEVEL:-0}" -ge 3 ]] && __b3bp_log error "${@}"; true; }
function warning ()   { [[ "${LOG_LEVEL:-0}" -ge 4 ]] && __b3bp_log warning "${@}"; true; }
function notice ()    { [[ "${LOG_LEVEL:-0}" -ge 5 ]] && __b3bp_log notice "${@}"; true; }
function info ()      { [[ "${LOG_LEVEL:-0}" -ge 6 ]] && __b3bp_log info "${@}"; true; }
function debug ()     { [[ "${LOG_LEVEL:-0}" -ge 7 ]] && __b3bp_log debug "${@}"; true; }

#-----------------------------------------------------------------------------#
#
# Define global variables
#
#-----------------------------------------------------------------------------#

AIRLINE_API_LOADED=1

AIRLINE_PREFIX="@airline"
__airline_refresh_flag="${AIRLINE_PREFIX}-refresh"

# store default theme elements in an array:
#   - keys are the set of recognized elements
#   - values are the default value
#
# this default theme works in 16 color palette environment
declare -g -A AIRLINE_THEME_ELEMENTS
AIRLINE_THEME_ELEMENTS=([primary]="white"
                        [secondary]="grey"
                        [emphasized]="white"
                        [outer]="white"
                        [middle]="grey"
                        [inner]="black"
                        [current]="yellow"
                        [alert]="orange"
                        [stress]="red"
                        [copy]="blue"
                        [zoom]="purple"
                        [monitor]="green"
                        [special]="cyan"
                      )

declare -g -A AIRLINE_STATUS_ELEMENTS
AIRLINE_STATUS_ELEMENTS=([left-outer]=1
                         [left-middle]=1
                         [left-inner]=1
                         [right-inner]=1
                         [right-middle]=1
                         [right-outer]=1
                       )

#-----------------------------------------------------------------------------#
#
# Internal functions
#
#-----------------------------------------------------------------------------#

# We assume that any change to an airline managed value will require
# re-applying all settings. Thus, we record that 
_airline_set () {
  local key="${1}"
  local value="${2}"

  tmux set-option -gq "${key}" "${value}"
  tmux set-option -gq "${__airline_refresh_flag}" "1"
}

_airline_get () {
  local key="${1}"

  tmux show-option -gqv "${key}"
}

airline_set_theme_element () {
  local element="${AIRLINE_PREFIX}-theme-$1"
  local value="$2"

  debug "Setting theme ${element} to ${value}"

  _airline_set "${element}" "${value}"
}

# Use when caller wants to handle unset values
_airline_get_theme_element () {
  local element="${AIRLINE_PREFIX}-theme-${1}"

  tmux show-option -gqv "${element}"
}

airline_get_theme_element () {
  local element="${1}"
  local value

  value="$(_airline_get_theme_element "${element}")"

  if [[ -z $value ]]
  then
    warning "Airline theme element not set: $element"
  fi

  echo "$value"
}

airline_set_status_element () {
  local element="${AIRLINE_PREFIX}-status-${1}"
  local value="${2}"

  debug "Setting status ${element} to ${value}"

  _airline_set "${element}" "${value}"
}

# Use when caller wants to handle unset values
_airline_get_status_element () {
  local element="${AIRLINE_PREFIX}-status-${1}"

  tmux show-option -gqv "${element}"
}

airline_get_status_element () {
  local element="${1}"
  local value

  value="$(_airline_get_status_element "${element}")"

  if [[ -z $value ]]
  then
    warning "Airline status element not set: $element"
  fi

  echo "$value"
}

_airline_get_interpolations () {
  local element="${AIRLINE_PREFIX}-interpolations"

  tmux show-option -gqv "${element}"
}
  

#-----------------------------------------------------------------------------#
#
# Refresh and lock flags
#
#-----------------------------------------------------------------------------#

# TODO: acquire and release lock functions

airline_refresh_needed () {
  local refresh

  refresh="$(tmux show-option -gqv "${__airline_refresh_flag}")"

  if [[ -z ${refresh} ]]
  then
    __airline_refresh_flag=1
  fi

  [[ ${refresh} = 1 ]]
}

_airline_refresh_clear () {
  tmux set-option -gq "${__airline_refresh_flag}" "0"
}

#-----------------------------------------------------------------------------#
#
# Helper functions
#
#-----------------------------------------------------------------------------#

verify_theme_element () {
  local element="$1"

  [[ -v "AIRLINE_THEME_ELEMENTS[$element]" ]] ||
    echo "Unsupported theme element type: $element"
}

verify_status_element () {
  local element="$1"

  [[ -v "AIRLINE_STATUS_ELEMENTS[$element]" ]] ||
    echo "Unsupported status element type: $element"
}

#-----------------------------------------------------------------------------#
#
# Sub-subcommands
#
#-----------------------------------------------------------------------------#

airline_load () {
  local config="$1"

  # config a readable file?
  if [[ -r "$config" && -f "$config" ]]
  then
    source "$config"
    return
  fi

  # config part of airline's default configs?
  local target="$CURRENT_DIR/configs/$config"
  if [[ -r "$target" && -f "$target" ]]
  then
    source "$target"
    return
  fi

  # could not load config
  exit 1
}

_airline_get_interpolations () {
  local element="${AIRLINE_PREFIX}-interpolations"

  tmux show-option -gqv "${element}"
}

airline_register () {
  local widget="${1}"
  local path="${2}"

  debug "Registering widget ${widget} to ${path}"

  _airline_set "${AIRLINE_PREFIX}-${widget}" "${path}"
  _airline_set "${AIRLINE_PREFIX}-interpolations" \
    "$(_airline_get_interpolations) ${widget}"
}

airline_show () {
  local group="${1:-all}"
  local element="${2:-}"

  debug "Showing $group $element"

  case "$group" in
    prefix )
      echo "${AIRLINE_PREFIX}"
      ;;
    theme )
      if [[ -n "${element}" ]]
      then
        verify_theme_element "$element" &&
          airline_get_theme_element "$element"
        return
      fi

      for element in "${!AIRLINE_THEME_ELEMENTS[@]}"
      do
        airline_show theme "${element}"
      done
      ;;
    status )
      if [[ -n "${element}" ]]
      then
        verify_status_element "$element" &&
          airline_get_status_element "$element"
        return
      fi

      for element in "${!AIRLINE_STATUS_ELEMENTS[@]}"
      do
        airline_show status "${element}"
      done
      ;;
    widget )
      if [[ -n "${element}" ]]
      then
        airline_get_widget_mapping "${element}"
        return
      fi

      for element in 
      ;;
    all )
      airline_show prefix
      airline_show status
      airline_show theme
      airline_show widget
      ;;

    help | --help | -h )
      cat << EOF
$0: Show values
EOF
      ;;
    * )
      airline_show "help"
      exit 1
      ;;
  esac
}

airline_set () {
  local group="$1"
  local element="$2"
  local value="$3"

  debug "Setting $group $element: $value"

  # TODO: check for correct number of args

  case "$group" in
    theme )
      # verify element name
      airline_set_theme_element "$element" "$value"
      ;;
    status )
      # verify element name
      airline_set_status_element "$element" "$value"
      ;;
    help | --help | -h )
      cat << EOF
$0: set option
EOF
      ;;
    * )
      airline_set "help"
      exit 1
      ;;
  esac

}

# vim: sts=2 sw=2 et
#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-#
