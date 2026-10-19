#!/usr/bin/env bash
#| summary: Dependency-free bar: session, host, and date
airline_layout_configure () {
  local declare="$1"
  "$declare" segment left-out  "#h"
  "$declare" segment left-mid  "#S"
  "$declare" segment left-in '#{E:@airline--widget-problem}'
  "$declare" segment right-out '%Y-%m-%d %H:%M'
}
