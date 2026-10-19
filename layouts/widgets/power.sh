#!/usr/bin/env bash
#| summary: Linux power state icon colored by battery charge (first system battery)
_power_options() {
  POWER_BATTERY_ICON="$(tmux show-option -gqv @airline-widget-power-battery-icon)" || return
  POWER_BATTERY_ICON="${POWER_BATTERY_ICON:-🔋}"
  POWER_CHARGING_ICON="$(tmux show-option -gqv @airline-widget-power-charging-icon)" || return
  POWER_CHARGING_ICON="${POWER_CHARGING_ICON:-⚡}"
  POWER_CONNECTED_ICON="$(tmux show-option -gqv @airline-widget-power-connected-icon)" || return
  POWER_CONNECTED_ICON="${POWER_CONNECTED_ICON:-🔌}"
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
  local fg="$1" bg="$2" value state capacity battery charging connected color icon charge_color
  shift 2
  local POWER_BATTERY_ICON POWER_CHARGING_ICON POWER_CONNECTED_ICON
  _power_options || return 2
  value="$(widget_runtime)"
  state="#{s/ .*//:$value}"
  capacity="#{s/.* //:$value}"
  battery="$(widget_text "$POWER_BATTERY_ICON")"
  charging="$(widget_text "$POWER_CHARGING_ICON")"
  connected="$(widget_text "$POWER_CONNECTED_ICON")"
  charge_color="#{?#{e|>=:$capacity,90},#{@airline-palette-primary},#{@airline-palette-emphasized}}"
  color="#{?#{==:$state,battery},#{?#{e|<:$capacity,20},#{@airline-palette-stress},#{?#{e|<:$capacity,50},#{@airline-palette-alert},$charge_color}},#{?#{||:#{==:$state,charging},#{==:$state,connected}},$charge_color,#{@airline-palette-primary}}}"
  icon="#{?#{==:$state,battery},$battery,#{?#{==:$state,charging},$charging,#{?#{==:$state,connected},$connected,—}}}"
  printf '#[fg=%s]%s#[fg=%s,bg=%s]' "$color" "$icon" "$fg" "$bg"
}
