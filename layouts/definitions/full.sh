#!/usr/bin/env bash
#| summary: Available native widgets alongside session and date
airline_layout_configure () {
  local declare="$1"
  "$declare" segment left-out '#h:#S'
  "$declare" segment right-in '#{E:@airline--widget-prefix}'
  "$declare" segment right-mid '#{E:@airline--widget-online} #{E:@airline--widget-cpu} #{E:@airline--widget-power}'
  "$declare" segment right-out '%Y-%m-%d %H:%M #{E:@airline--widget-problem}'
}
