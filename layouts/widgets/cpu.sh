#!/usr/bin/env bash
#| summary: Current CPU usage reduced to low, medium, or high
_cpu_options() {
  CPU_MEDIUM="$(tmux show-option -gqv @airline-widget-cpu-medium)" || return
  CPU_MEDIUM="${CPU_MEDIUM:-60}"
  CPU_HIGH="$(tmux show-option -gqv @airline-widget-cpu-high)" || return
  CPU_HIGH="${CPU_HIGH:-85}"
  [[ "$CPU_MEDIUM" =~ ^[0-9]{1,3}$ && "$CPU_HIGH" =~ ^[0-9]{1,3}$ ]] || return 2
  (( 10#$CPU_MEDIUM <= 10#$CPU_HIGH && 10#$CPU_HIGH <= 100 ))
}

airline_widget_available() { command -v top >/dev/null 2>&1 || return 3; }
airline_widget_format() {
  local fg="$1" bg="$2"; shift 2
  local CPU_MEDIUM CPU_HIGH icon=CPU
  _cpu_options || return 2
  local value
  value="$(widget_runtime)"
  [[ "${AIRLINE_WIDGET_NERD_FONTS:-off}" != on ]] || icon=$'\uf4bc'
  printf '#[fg=#{?#{e|>=:%s,%s},#{@airline-palette-stress},#{?#{e|>=:%s,%s},#{@airline-palette-alert},#{@airline-palette-primary}}}]%s#[fg=%s,bg=%s]' \
    "$value" "$CPU_HIGH" "$value" "$CPU_MEDIUM" "$icon" "$fg" "$bg"
}
