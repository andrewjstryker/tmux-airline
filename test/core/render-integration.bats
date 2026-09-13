#!/usr/bin/env bats

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load
load ../support/helper

setup() {
  $TMUX -L "$_bats_socket" -f /dev/null new-session -d -s bats -n ordinary
  $TMUX -L "$_bats_socket" new-window -t bats:1 -n previous
  $TMUX -L "$_bats_socket" new-window -t bats:2 -n current
  # An attached client renders into another session's pane. capture-pane -e then
  # exposes actual terminal colors, including tmux's native last-window styling.
  $TMUX -L "$_bats_socket" new-session -d -s screen -x 160 -y 24 \
    "env -u TMUX TERM=xterm-256color $TMUX -L $_bats_socket attach-session -t bats"
  airline session init
}

# Normalize capture-pane's SGR runs to foreground:background text. Keep the
# colors across runs: tmux only emits attributes which changed. The tests use
# the shipped 256-color palette and assert whole names, never template fragments.
_status_colors() {
  $TMUX -L "$_bats_socket" capture-pane -e -p -t screen:0 -S 23 -E 23 |
    awk '
      BEGIN { esc = sprintf("%c", 27) }
      {
        fg = bg = "default"
        count = split($0, runs, esc "\\[")
        for (i = 2; i <= count; i++) {
          end = index(runs[i], "m")
          n = split(substr(runs[i], 1, end - 1), codes, ";")
          for (j = 1; j <= n; j++) {
            if ((codes[j] == 38 || codes[j] == 48) && codes[j+1] == 5) {
              if (codes[j] == 38) fg = codes[j+2]; else bg = codes[j+2]
              j += 2
            } else if (codes[j] == 0) { fg = bg = "default" }
            else if (codes[j] == 39) fg = "default"
            else if (codes[j] == 49) bg = "default"
          }
          text = substr(runs[i], end + 1)
          if (length(text)) print fg ":" bg " " text
        }
      }'
}

_assert_name_colors() {
  local name="$1" fg="$2" bg="$3" captured=""
  # Redraws are asynchronous; poll for the visible result, with a bounded wait.
  for _ in {1..40}; do
    captured="$(_status_colors)"
    if printf '%s\n' "$captured" | awk -v color="$fg:$bg" -v name="$name" \
         '$1 == color && index($0, name) { found = 1 } END { exit !found }'; then
      return 0
    fi
    sleep 0.05
  done
  printf 'Expected %s in fg=%s bg=%s; rendered:\n%s\n' "$name" "$fg" "$bg" "$captured" >&2
  return 1
}

@test "current window highlight follows selection across existing windows" {
  _assert_name_colors 2:current 234 214
  $TMUX -L "$_bats_socket" select-window -t bats:0
  _assert_name_colors 0:ordinary 234 214
  _assert_name_colors 1:previous 250 234
}

@test "previous window name is emphasized and follows last-window navigation" {
  # This window received airline's format even before the scope regression fix.
  $TMUX -L "$_bats_socket" select-window -t bats:0
  _assert_name_colors 2:current 255 234
  $TMUX -L "$_bats_socket" last-window -t bats
  _assert_name_colors 0:ordinary 255 234
  _assert_name_colors 2:current 234 214
  _assert_name_colors 1:previous 250 234
}

@test "new windows receive current and previous highlighting immediately" {
  $TMUX -L "$_bats_socket" new-window -t bats:3 -n newly-created
  _assert_name_colors 3:newly-created 234 214
  $TMUX -L "$_bats_socket" select-window -t bats:1
  _assert_name_colors 3:newly-created 255 234
  _assert_name_colors 1:previous 234 214
}

@test "badges do not overwrite current or previous name colors" {
  pane="$($TMUX -L "$_bats_socket" display-message -p -t bats:2 '#{pane_id}')"
  airline status set -t "$pane" attention
  airline health set -t "$pane" test service warn "slow"
  _assert_name_colors 2:current 234 214
  $TMUX -L "$_bats_socket" select-window -t bats:0
  _assert_name_colors 2:current 255 234
}

@test "new window mode selectors stay live and restore previous emphasis" {
  $TMUX -L "$_bats_socket" new-window -t bats:3 -n mode-window
  $TMUX -L "$_bats_socket" copy-mode -t bats:3
  _assert_name_colors 3:mode-window 75 214
  $TMUX -L "$_bats_socket" select-window -t bats:0
  _assert_name_colors 3:mode-window 234 75
  $TMUX -L "$_bats_socket" send-keys -t bats:3 -X cancel
  _assert_name_colors 3:mode-window 255 234
}

@test "palette changes update every existing window and future windows" {
  $TMUX -L "$_bats_socket" set -t bats @airline-active colour201
  $TMUX -L "$_bats_socket" set -t bats @airline-emphasized colour200
  airline session apply
  $TMUX -L "$_bats_socket" select-window -t bats:0
  _assert_name_colors 0:ordinary 234 201
  _assert_name_colors 2:current 200 234
  $TMUX -L "$_bats_socket" new-window -t bats:3 -n new-palette
  _assert_name_colors 3:new-palette 234 201
  _assert_name_colors 0:ordinary 200 234
}
