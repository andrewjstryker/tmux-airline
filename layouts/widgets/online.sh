#!/usr/bin/env bash
#| summary: NetworkManager connection type and external connectivity

airline_widget_available() {
  command -v nmcli >/dev/null 2>&1 && command -v ip >/dev/null 2>&1 || return 3
}
airline_widget_format() {
  local fg="$1" bg="$2" value state health color icon wired=LAN wireless=WiFi offline=OFF
  if [[ "${AIRLINE_WIDGET_NERD_FONTS:-off}" == on ]]; then
    wired=$'\U000f0200'; wireless=$'\U000f05a9'; offline=$'\U000f0319'
  fi
  value="$(widget_runtime)"
  state="#{s/ .*//:$value}"
  health="#{s/.* //:$value}"
  color="#{?#{==:$state,disconnected},#{@airline-palette-stress},#{?#{==:$health,limited},#{@airline-palette-alert},#{@airline-palette-primary}}}"
  icon="#{?#{==:$state,wired},$wired,#{?#{==:$state,wireless},$wireless,#{?#{==:$state,disconnected},$offline,—}}}"
  printf '#[fg=%s]%s#[fg=%s,bg=%s]' "$color" "$icon" "$fg" "$bg"
}
