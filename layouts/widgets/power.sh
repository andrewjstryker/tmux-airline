#!/usr/bin/env bash
#| summary: Linux battery power source (first system battery)
#| usage: [--battery-icon <text>] [--connected-icon <text>]
#| options: battery-icon connected-icon
#| default-battery-icon: 🔋
#| default-connected-icon: ⚡
_power_options() {
  POWER_BATTERY_ICON=🔋 POWER_CONNECTED_ICON=⚡
  while (( $# )); do
    case "$1" in
      --battery-icon) [[ $# -ge 2 ]] || return 2; POWER_BATTERY_ICON="$2"; shift 2 ;;
      --connected-icon) [[ $# -ge 2 ]] || return 2; POWER_CONNECTED_ICON="$2"; shift 2 ;;
      *) return 2 ;;
    esac
  done
}
airline_widget_available() {
  local device type
  for device in "${AIRLINE_POWER_SUPPLY:-/sys/class/power_supply}"/*; do
    [[ -r "$device/type" ]] || continue
    read -r type < "$device/type"; [[ "$type" == Battery ]] && return 0
  done
  return 3
}
airline_widget_format() {
  local fg="$1" bg="$2" value battery connected
  shift 2
  _power_options "$@" || return 2
  value="$(widget_runtime)"
  battery="$(widget_text "$POWER_BATTERY_ICON")"
  connected="$(widget_text "$POWER_CONNECTED_ICON")"
  printf '#[fg=#{?#{==:%s,connected},#{@airline-palette-active},#{?#{==:%s,battery},#{@airline-palette-emphasized},#{@airline-palette-primary}}}]#{?#{==:%s,connected},%s,#{?#{==:%s,battery},%s,—}}#[fg=%s,bg=%s]' \
    "$value" "$value" "$value" "$connected" "$value" "$battery" "$fg" "$bg"
}
