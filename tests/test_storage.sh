#! /usr/bin/env bash
#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-#
# test_storage.sh
#
# Test that airline sets and gets variables correctly.
#
#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-#

test_theme_element () {
  local element="${1:-outer}"
  local value="${2:-red}"
  local result

  airline set theme "${element}" "${value}"
  result="$(airline show theme "${element}"

  [[ "${value}" = "${result}" ]]
}

if [[ "${BASH_SOURCE[0]}" = "${0}" ]]
then
  test_theme_element
  exit "$?"
fi

export -f test_theme_element

# vim: sts=2 sw=2 et
