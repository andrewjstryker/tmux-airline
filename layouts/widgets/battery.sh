#!/usr/bin/env bash
#| summary: Linux battery capacity meter (first system battery)
airline_widget_available() {
  local device type
  for device in "${AIRLINE_POWER_SUPPLY:-/sys/class/power_supply}"/*; do
    [[ -r "$device/type" && -r "$device/capacity" ]] || continue
    read -r type < "$device/type"; [[ "$type" == Battery ]] && return 0
  done
  return 3
}
airline_widget_format() {
  local fg="$1" bg="$2" value meter='▁' tier valid color
  value="$(widget_runtime)"
  for tier in '6 ▂' '20 ▃' '35 ▄' '50 ▅' '65 ▆' '80 ▇' '95 █'; do
    meter="#{?#{e|>=:$value,${tier%% *}},${tier#* },$meter}"
  done
  # A nonempty value is the runtime's validated numeric observation.
  valid="#{!=:$value,}"
  color="#{?#{e|<:$value,20},#{@airline-palette-stress},#{?#{e|<:$value,50},#{@airline-palette-alert},#{?#{e|<:$value,80},#{@airline-palette-emphasized},#{@airline-palette-primary}}}}"
  printf '%s#[fg=%s,bg=%s]' "#{?$valid,#[fg=$color]$meter,#[fg=#{@airline-palette-primary}]—}" "$fg" "$bg"
}
