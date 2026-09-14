#!/usr/bin/env bash
#| summary: Linux battery capacity (first system battery)
#| usage: [--display <compact|both>] [--charging-icon <text>] [--discharging-icon <text>]
#| options: display charging-icon discharging-icon
#| default-display: compact
#| default-charging-icon: ⚡
#| default-discharging-icon: 🔋
_battery_options() {
  BATTERY_DISPLAY=compact BATTERY_CHARGING_ICON=⚡ BATTERY_DISCHARGING_ICON=🔋
  while (( $# )); do
    case "$1" in
      --display) [[ $# -ge 2 ]] || return 2; BATTERY_DISPLAY="$2"; shift 2 ;;
      --charging-icon) [[ $# -ge 2 ]] || return 2; BATTERY_CHARGING_ICON="$2"; shift 2 ;;
      --discharging-icon) [[ $# -ge 2 ]] || return 2; BATTERY_DISCHARGING_ICON="$2"; shift 2 ;;
      *) return 2 ;;
    esac
  done
  [[ "$BATTERY_DISPLAY" == compact || "$BATTERY_DISPLAY" == both ]]
}
airline_widget_available() {
  local device type
  for device in "${AIRLINE_POWER_SUPPLY:-/sys/class/power_supply}"/*; do
    [[ -r "$device/type" && -r "$device/capacity" ]] || continue
    read -r type < "$device/type"; [[ "$type" == Battery ]] && return 0
  done
  return 3
}
airline_widget_format() {
  local fg="$1" bg="$2"; shift 2
  _battery_options "$@" || return 2
  local reading value meter='▁' tier power status charging discharging
  reading="$(widget_runtime)"
  value="#{s/[^0-9].*//:$reading}"
  for tier in '6 ▂' '20 ▃' '35 ▄' '50 ▅' '65 ▆' '80 ▇' '95 █'; do
    meter="#{?#{e|>=:$value,${tier%% *}},${tier#* },$meter}"
  done
  charging="$(widget_text "$BATTERY_CHARGING_ICON")"
  discharging="$(widget_text "$BATTERY_DISCHARGING_ICON")"
  power="#{m:*:charging,$reading}"
  status="#[fg=#{?#{m:*:charging,$reading},#{@airline-palette-active},#{?#{m:*:discharging,$reading},#{@airline-palette-emphasized},#{@airline-palette-primary}}}]#{?#{m:*:discharging,$reading},$discharging,#{?${power},$charging,}}"
  if [[ "$BATTERY_DISPLAY" == both ]]; then
    printf '%s%s#[fg=%s,bg=%s]' "#[fg=#{@airline-palette-primary}]$meter" "$status" "$fg" "$bg"
  else
    printf '%s#[fg=%s,bg=%s]' "#{?$power,$status,#[fg=#{@airline-palette-primary}]$meter}" "$fg" "$bg"
  fi
}
