#!/usr/bin/env bash
#| summary: Available native widgets alongside session and date
airline_layout_configure () {
  "$1" segment left-out '#S'
  "$1" widget right-in prefix
  "$1" widget-optional left-mid online
  "$1" widget-optional right-mid cpu
  "$1" segment right-out '%Y-%m-%d %H:%M '
  "$1" widget-optional right-out battery
}
