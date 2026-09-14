#!/usr/bin/env bash
#| summary: Current CPU usage reduced to low, medium, or high
#| usage: [--medium <percent>] [--high <percent>] [--low-icon <text>] [--medium-icon <text>] [--high-icon <text>]
#| options: medium high low-icon medium-icon high-icon
#| default-medium: 60
#| default-high: 85
#| default-low-icon: =
#| default-medium-icon: ≡
#| default-high-icon: ≣
_cpu_options() {
  CPU_MEDIUM=60 CPU_HIGH=85 CPU_LOW_ICON='=' CPU_MEDIUM_ICON='≡' CPU_HIGH_ICON='≣'
  while (( $# )); do
    case "$1" in
      --medium) [[ $# -ge 2 ]] || return 2; CPU_MEDIUM="$2"; shift 2 ;;
      --high) [[ $# -ge 2 ]] || return 2; CPU_HIGH="$2"; shift 2 ;;
      --low-icon) [[ $# -ge 2 ]] || return 2; CPU_LOW_ICON="$2"; shift 2 ;;
      --medium-icon) [[ $# -ge 2 ]] || return 2; CPU_MEDIUM_ICON="$2"; shift 2 ;;
      --high-icon) [[ $# -ge 2 ]] || return 2; CPU_HIGH_ICON="$2"; shift 2 ;;
      *) return 2 ;;
    esac
  done
  [[ "$CPU_MEDIUM" =~ ^[0-9]{1,3}$ && "$CPU_HIGH" =~ ^[0-9]{1,3}$ ]] || return 2
  (( 10#$CPU_MEDIUM <= 10#$CPU_HIGH && 10#$CPU_HIGH <= 100 ))
}
airline_widget_format() {
  local fg="$1" bg="$2"; shift 2
  _cpu_options "$@" || return 2
  if ! command -v top >/dev/null 2>&1; then
    if [[ -n "${AIRLINE_WIDGET_SESSION:-}" && "${AIRLINE_WIDGET_INSTANCE:-}" != inspect ]]; then
      signal_problem_report "${AIRLINE_WIDGET_SESSION:-}" airline-widget "${AIRLINE_WIDGET_INSTANCE:-cpu}" warn 'cpu widget requires top'
    fi
    return 0
  fi
  local value
  value="$(widget_runtime)"
  printf '#[fg=#{?#{e|>=:%s,%s},#{@airline-palette-stress},#{?#{e|>=:%s,%s},#{@airline-palette-alert},#{@airline-palette-primary}}}]#{?#{e|>=:%s,%s},%s,#{?#{e|>=:%s,%s},%s,%s}}#[fg=%s,bg=%s]' \
    "$value" "$CPU_HIGH" "$value" "$CPU_MEDIUM" "$value" "$CPU_HIGH" "$(widget_text "$CPU_HIGH_ICON")" "$value" "$CPU_MEDIUM" "$(widget_text "$CPU_MEDIUM_ICON")" "$(widget_text "$CPU_LOW_ICON")" "$fg" "$bg"
}
