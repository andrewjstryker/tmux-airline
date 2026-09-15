#!/usr/bin/env bash
#| summary: Reachability of a chosen host through ICMP
#| usage: [--host <host>] [--timeout <seconds>] [--online-icon <text>] [--offline-icon <text>]
#| options: host timeout online-icon offline-icon
#| default-host: 1.1.1.1
#| default-timeout: 1
#| default-online-icon: ●
#| default-offline-icon: ●
_online_options() {
  ONLINE_HOST=1.1.1.1 ONLINE_TIMEOUT=1 ONLINE_ICON=● OFFLINE_ICON=●
  while (( $# )); do
    case "$1" in
      --host) [[ $# -ge 2 ]] || return 2; ONLINE_HOST="$2"; shift 2 ;;
      --timeout) [[ $# -ge 2 ]] || return 2; ONLINE_TIMEOUT="$2"; shift 2 ;;
      --online-icon) [[ $# -ge 2 ]] || return 2; ONLINE_ICON="$2"; shift 2 ;;
      --offline-icon) [[ $# -ge 2 ]] || return 2; OFFLINE_ICON="$2"; shift 2 ;;
      *) return 2 ;;
    esac
  done
  [[ "$ONLINE_TIMEOUT" =~ ^[1-8]$ && "$ONLINE_HOST" =~ ^[a-zA-Z0-9][a-zA-Z0-9.:%_-]*$ ]]
}
airline_widget_available() { command -v ping >/dev/null || return 3; }
airline_widget_format() {
  local fg="$1" bg="$2"; shift 2
  _online_options "$@" || return 2
  local value
  value="$(widget_runtime --host "$ONLINE_HOST" --timeout "$ONLINE_TIMEOUT")"
  printf '#[fg=#{?#{==:%s,1},#{@airline-palette-primary},#{@airline-palette-stress}}]#{?#{==:%s,1},%s,#{?#{==:%s,0},%s,—}}#[fg=%s,bg=%s]' \
    "$value" "$value" "$(widget_text "$ONLINE_ICON")" "$value" "$(widget_text "$OFFLINE_ICON")" "$fg" "$bg"
}
