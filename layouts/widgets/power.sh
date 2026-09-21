#!/usr/bin/env bash
#| summary: Linux battery power source (first system battery)
_power_options() {
  POWER_BATTERY_ICON="$(tmux show-option -gqv @airline-widget-power-battery-icon)" || return
  POWER_BATTERY_ICON="${POWER_BATTERY_ICON:-🔋}"
  POWER_CONNECTED_ICON="$(tmux show-option -gqv @airline-widget-power-connected-icon)" || return
  POWER_CONNECTED_ICON="${POWER_CONNECTED_ICON:-⚡}"
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
  local POWER_BATTERY_ICON POWER_CONNECTED_ICON
  _power_options || return 2
  value="$(widget_runtime)"
  battery="$(widget_text "$POWER_BATTERY_ICON")"
  connected="$(widget_text "$POWER_CONNECTED_ICON")"
  printf '#[fg=#{?#{==:%s,connected},#{@airline-palette-active},#{?#{==:%s,battery},#{@airline-palette-emphasized},#{@airline-palette-primary}}}]#{?#{==:%s,connected},%s,#{?#{==:%s,battery},%s,—}}#[fg=%s,bg=%s]' \
    "$value" "$value" "$value" "$connected" "$value" "$battery" "$fg" "$bg"
}
