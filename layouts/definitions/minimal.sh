#!/usr/bin/env bash
#| summary: Window list, session name, and problem indicator
airline_layout_configure () {
  local declare="$1"
  "$declare" segment left-out "#S"
  "$declare" segment right-out '#{E:@airline--widget-problem}'
}
