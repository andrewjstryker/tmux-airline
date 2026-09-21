#!/usr/bin/env bash
#| summary: Window list and session name, nothing else
airline_layout_configure () {
  local declare="$1"
  "$declare" segment left-out "#S"
  "$declare" widget right-out problem
}
