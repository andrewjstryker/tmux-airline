#!/usr/bin/env bash
#| summary: Available native widgets alongside session and date
airline_layout_configure () {
  local declare="$1"
  "$declare" segment left-out '#h:#S'
  "$declare" segment left-mid '#{E:@airline--widget-online}'
  "$declare" segment right-in '#{E:@airline--widget-prefix}'
  "$declare" segment right-mid '#{E:@airline--widget-cpu}'
  "$declare" segment right-out '%Y-%m-%d %H:%M #{E:@airline--widget-battery}#{E:@airline--widget-power} #{E:@airline--widget-problem}'
}
