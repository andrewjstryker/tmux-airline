#!/usr/bin/env bash
#| summary: Current CPU usage reduced to low, medium, or high
_cpu_options() {
  CPU_MEDIUM="$(tmux show-option -gqv @airline-widget-cpu-medium)" || return
  CPU_MEDIUM="${CPU_MEDIUM:-60}"
  CPU_HIGH="$(tmux show-option -gqv @airline-widget-cpu-high)" || return
  CPU_HIGH="${CPU_HIGH:-85}"
  CPU_LOW_ICON="$(tmux show-option -gqv @airline-widget-cpu-low-icon)" || return
  CPU_LOW_ICON="${CPU_LOW_ICON:-=}"
  CPU_MEDIUM_ICON="$(tmux show-option -gqv @airline-widget-cpu-medium-icon)" || return
  CPU_MEDIUM_ICON="${CPU_MEDIUM_ICON:-≡}"
  CPU_HIGH_ICON="$(tmux show-option -gqv @airline-widget-cpu-high-icon)" || return
  CPU_HIGH_ICON="${CPU_HIGH_ICON:-≣}"
  [[ "$CPU_MEDIUM" =~ ^[0-9]{1,3}$ && "$CPU_HIGH" =~ ^[0-9]{1,3}$ ]] || return 2
  (( 10#$CPU_MEDIUM <= 10#$CPU_HIGH && 10#$CPU_HIGH <= 100 ))
}

airline_widget_available() { command -v top >/dev/null 2>&1 || return 3; }
airline_widget_format() {
  local fg="$1" bg="$2"; shift 2
  local CPU_MEDIUM CPU_HIGH CPU_LOW_ICON CPU_MEDIUM_ICON CPU_HIGH_ICON
  _cpu_options || return 2
  local value
  value="$(widget_runtime)"
  printf '#[fg=#{?#{e|>=:%s,%s},#{@airline-palette-stress},#{?#{e|>=:%s,%s},#{@airline-palette-alert},#{@airline-palette-primary}}}]#{?#{e|>=:%s,%s},%s,#{?#{e|>=:%s,%s},%s,%s}}#[fg=%s,bg=%s]' \
    "$value" "$CPU_HIGH" "$value" "$CPU_MEDIUM" "$value" "$CPU_HIGH" "$(widget_text "$CPU_HIGH_ICON")" "$value" "$CPU_MEDIUM" "$(widget_text "$CPU_MEDIUM_ICON")" "$(widget_text "$CPU_LOW_ICON")" "$fg" "$bg"
}
