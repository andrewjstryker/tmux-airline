#!/usr/bin/env bash
#| summary: Native prefix, copy, sync, and key-table badges
_prefix_badge() {
  # Conditional branches cannot contain unescaped style commas.
  printf '#[fg=#{@airline-palette-inner-bg}]#[bg=#{@airline-palette-%s}][%s]#[fg=%s]#[bg=%s]' "$1" "$2" "$3" "$4"
}
airline_widget_available() { return 0; }
airline_widget_format() {
  local fg="$1" bg="$2"; shift 2
  local show_copy show_sync fallback
  show_copy="$(tmux show-option -gqv @airline-widget-prefix-show-copy)" || return
  show_sync="$(tmux show-option -gqv @airline-widget-prefix-show-sync)" || return
  show_copy="${show_copy:-on}"; show_sync="${show_sync:-on}"
  [[ "$show_copy" == on || "$show_copy" == off ]] || return 2
  [[ "$show_sync" == on || "$show_sync" == off ]] || return 2
  fallback="#{?#{&&:#{!=:#{client_key_table},},#{!=:#{client_key_table},root}},$(_prefix_badge active '#{client_key_table}' "$fg" "$bg"),}"
  [[ "$show_sync" == off ]] || fallback="#{?synchronize-panes,$(_prefix_badge special Sync "$fg" "$bg"),$fallback}"
  [[ "$show_copy" == off ]] || fallback="#{?pane_in_mode,$(_prefix_badge copy Copy "$fg" "$bg"),$fallback}"
  # client_prefix is also true for custom key tables; name those below.
  printf '#{?#{&&:#{client_prefix},#{==:#{client_key_table},prefix}},%s,%s}#[fg=%s,bg=%s]' "$(_prefix_badge active Prefix "$fg" "$bg")" "$fallback" "$fg" "$bg"
}
