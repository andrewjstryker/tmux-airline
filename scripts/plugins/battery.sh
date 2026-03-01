#!/usr/bin/env bash

configure_battery () {
  if ! is_battery_installed; then
    return
  fi

  local bg="${THEME[outer-bg]}"

  tmux set -g @batt_color_full_charge "#[fg=${THEME[emphasized]}]"
  tmux set -g @batt_color_high_charge "#[fg=${THEME[primary]}]"
  tmux set -g @batt_color_medium_charge "#[fg=${THEME[alert]}]"
  tmux set -g @batt_color_low_charge "#[fg=${THEME[stress]}]"

  # use theme colors
  tmux set -g @batt_color_charge_primary_tier8 "${THEME[primary]}"
  tmux set -g @batt_color_charge_primary_tier7 "${THEME[primary]}"
  tmux set -g @batt_color_charge_primary_tier6 "${THEME[emphasized]}"
  tmux set -g @batt_color_charge_primary_tier5 "${THEME[emphasized]}"
  tmux set -g @batt_color_charge_primary_tier4 "${THEME[alert]}"
  tmux set -g @batt_color_charge_primary_tier3 "${THEME[alert]}"
  tmux set -g @batt_color_charge_primary_tier2 "${THEME[stress]}"
  tmux set -g @batt_color_charge_primary_tier1 "${THEME[stress]}"

  # icons to show when discharging the battery
  tmux set -g @batt_icon_charge_tier8 '█'
  tmux set -g @batt_icon_charge_tier7 '▇'
  tmux set -g @batt_icon_charge_tier6 '▆'
  tmux set -g @batt_icon_charge_tier5 '▅'
  tmux set -g @batt_icon_charge_tier4 '▄'
  tmux set -g @batt_icon_charge_tier3 '▃'
  tmux set -g @batt_icon_charge_tier2 '▂'
  tmux set -g @batt_icon_charge_tier1 '▁'

  # icons to show charging status
  tmux set -g @batt_icon_status_charged '⚡'
  tmux set -g @batt_icon_status_charging '⚡'
  tmux set -g @batt_icon_status_discharging '🔋'
  tmux set -g @batt_icon_status_attached '⚡'
  tmux set -g @batt_icon_status_unknown ' '
  tmux set -g @batt_color_status_primary_charged "${THEME[primary]}"
  tmux set -g @batt_color_status_primary_charging "${THEME[active]}"
  tmux set -g @batt_color_status_primary_discharging "${THEME[emphasized]}"
  tmux set -g @batt_color_status_primary_attached "${THEME[primary]}"
  tmux set -g @batt_color_status_primary_unknown "${THEME[stress]}"

  echo "#{battery_color_fg}#[bg=$bg]#{battery_icon}#{battery_color_status_fg}#{battery_status}"
}
