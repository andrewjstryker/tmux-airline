#!/usr/bin/env bash
#| summary: Global problem indicator

airline_widget_available() { return 0; }

airline_widget_format() {
  local fg="$1" bg="$2" value color glyph blink
  value="$(widget_runtime)"
  color='#{@airline-palette-primary}'
  color="#{?#{==:$value,warn},#{@airline-palette-alert},$color}"
  color="#{?#{==:$value,fail},#{@airline-palette-stress},$color}"
  glyph='▲'
  glyph="#{?#{==:$value,warn},△,$glyph}"
  blink="#{?#{==:$value,fail},#[blink],}"
  printf '#{?%s,#[fg=%s]#[bg=%s]%s%s#[noblink] ,}#[fg=%s,bg=%s]' \
    "#{||:#{==:$value,warn},#{==:$value,fail}}" "$color" "$bg" "$blink" "$glyph" "$fg" "$bg"
}
