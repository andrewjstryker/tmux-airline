#!/usr/bin/env bash
#| summary: Host, session, native status widgets, and date
airline_layout_configure () {
  local declare="$1"
  "$declare" segment left-out  "#h"
  "$declare" segment left-mid  "#S"
  "$declare" segment left-in '#{E:@airline--widget-problem}'
  "$declare" segment right-in '#{E:@airline--widget-prefix}'
  "$declare" segment right-mid '#{E:@airline--widget-online} #{E:@airline--widget-cpu} #{E:@airline--widget-power}'
  "$declare" segment right-out '%Y-%m-%d %H:%M'
}
