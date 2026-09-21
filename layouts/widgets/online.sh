#!/usr/bin/env bash
#| summary: Reachability of a chosen host through ICMP
_online_options() {
  ONLINE_HOST="$(tmux show-option -gqv @airline-widget-online-host)" || return
  ONLINE_HOST="${ONLINE_HOST:-1.1.1.1}"
  ONLINE_TIMEOUT="$(tmux show-option -gqv @airline-widget-online-timeout)" || return
  ONLINE_TIMEOUT="${ONLINE_TIMEOUT:-1}"
  ONLINE_ICON="$(tmux show-option -gqv @airline-widget-online-online-icon)" || return
  ONLINE_ICON="${ONLINE_ICON:-●}"
  OFFLINE_ICON="$(tmux show-option -gqv @airline-widget-online-offline-icon)" || return
  OFFLINE_ICON="${OFFLINE_ICON:-●}"
  [[ "$ONLINE_TIMEOUT" =~ ^[1-8]$ && "$ONLINE_HOST" =~ ^[a-zA-Z0-9][a-zA-Z0-9.:%_-]*$ ]]
}

airline_widget_available() { command -v ping >/dev/null || return 3; }
airline_widget_format() {
  local fg="$1" bg="$2"; shift 2
  local ONLINE_HOST ONLINE_TIMEOUT ONLINE_ICON OFFLINE_ICON
  _online_options || return 2
  local value
  value="$(widget_runtime --host "$ONLINE_HOST" --timeout "$ONLINE_TIMEOUT")"
  printf '#[fg=#{?#{==:%s,1},#{@airline-palette-primary},#{@airline-palette-stress}}]#{?#{==:%s,1},%s,#{?#{==:%s,0},%s,—}}#[fg=%s,bg=%s]' \
    "$value" "$value" "$(widget_text "$ONLINE_ICON")" "$value" "$(widget_text "$OFFLINE_ICON")" "$fg" "$bg"
}
