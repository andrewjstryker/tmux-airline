#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load
load helper

# render.sh — the composition layer: the boundary validators (predicates the
# CLI calls), the palette, and the segment-bar composition. render.sh trusts
# its inputs; validation lives at the boundary, so it is exercised here only as
# the predicates the CLI will call — not as a validate-and-store path.
#
# Runs on the in-memory fake (load_render) — no tmux server, so override the
# real-server setup/teardown from helper.bash with no-ops.
setup()    { :; }
teardown() { :; }

# --- boundary validators ----------------------------------------------------

@test "_segment_slot_valid accepts the six slots and rejects others" {
  load_render
  _segment_slot_valid right-mid
  _segment_slot_valid left-out
  ! _segment_slot_valid middle
  ! _segment_slot_valid ""
}

@test "_palette_element_valid accepts palette roles and rejects others" {
  load_render
  _palette_element_valid active
  _palette_element_valid outer-bg
  ! _palette_element_valid bogus
}

# --- segment-bar composition ------------------------------------------------

# Seed a minimal palette directly through the option store, then load it — the
# composition trusts these values (no validation in this layer).
_seed_palette() {
  opt_set_global @airline-outer-bg colour238
  opt_set_global @airline-middle-bg colour236
  opt_set_global @airline-inner-bg colour234
  opt_set_global @airline-secondary colour245
  opt_set_global @airline-primary colour250
  opt_set_global @airline-emphasized colour255
  opt_set_global @airline-active colour214
  opt_set_global @airline-special colour134
  opt_set_global @airline-ok colour114
  opt_set_global @airline-alert colour208
  opt_set_global @airline-stress colour196
  opt_set_global @airline-zoom colour81
  opt_set_global @airline-copy colour75
  opt_set_global @airline-monitor colour109
  _palette_load
}

@test "left bar composes non-empty slots with their tier backgrounds" {
  load_render
  _seed_palette
  opt_set_global @airline-segment-left-out OUT
  opt_set_global @airline-segment-left-mid MID
  run _build_status_left
  assert_output --partial "bg=colour238"   # outer (left-out)
  assert_output --partial "bg=colour236"   # middle (left-mid)
  assert_output --partial " OUT "
  assert_output --partial " MID "
}

@test "empty slots are skipped, and the last left block chevrons to inner-bg" {
  load_render
  _seed_palette
  opt_set_global @airline-segment-left-out ONLY   # left-mid, left-in empty
  run _build_status_left
  assert_output --partial " ONLY "
  refute_output --partial "bg=colour236"   # no middle block
  assert_output --partial "bg=colour234"   # chevron into the inner-bg window list
}

@test "an all-empty left side composes to nothing" {
  load_render
  _seed_palette
  run _build_status_left
  assert_output ""
}

@test "right bar composes with a leading chevron from the window list" {
  load_render
  _seed_palette
  opt_set_global @airline-segment-right-out DATE
  run _build_status_right
  assert_output --partial " DATE "
  assert_output --partial "bg=colour238"   # outer (right-out)
}

@test "suspended dims the outer/middle backgrounds to inner-bg" {
  load_render
  _seed_palette
  opt_set_global @airline-segment-left-out X
  opt_set_session "$AIRLINE_SESSION" @airline--suspended 1
  _palette_load
  run _build_status_left
  refute_output --partial "bg=colour238"   # outer dimmed to inner-bg
  assert_output --partial "bg=colour234"
}

# --- window formats ---------------------------------------------------------

@test "window formats set the name template, mode expr, and base styles" {
  load_render
  _seed_palette
  set_window_formats
  run get_option window-status-format
  assert_output --partial "#I:#W"               # the name template
  assert_output --partial "window_zoomed_flag"  # the mode expression
  run get_option window-status-style
  assert_output --partial "fg=colour250"        # primary
  assert_output --partial "bg=colour234"        # inner-bg
}

# --- modes: inactive fills the background, active tints the foreground -------

@test "inactive window fills its background with the mode color" {
  load_render
  _seed_palette
  set_window_formats
  run get_option window-status-format
  # bg is a mode selector: zoom→81, copy→75, monitor→109, else inner-bg 234
  assert_output --partial "bg=#{?#{window_zoomed_flag},colour81"
  assert_output --partial "monitor-activity,colour109,colour234"   # else flat inner-bg
}

@test "inactive name knocks out over a filled block, else stays primary" {
  load_render
  _seed_palette
  set_window_formats
  run get_option window-status-format
  # fg: inner-bg knockout when in any mode, primary (250) when flat
  assert_output --partial "#[fg=#{?#{window_zoomed_flag},colour234"
  assert_output --partial "monitor-activity,colour234,colour250"
}

@test "active window keeps a constant active-color highlight block" {
  load_render
  _seed_palette
  set_window_formats
  run get_option window-status-current-format
  assert_output --partial "bg=colour214"          # active highlight, not a mode selector
  refute_output --partial "bg=#{?#{window_zoomed_flag}"  # active bg never varies with mode
}

@test "active window tints the name foreground by mode (knockout when none)" {
  load_render
  _seed_palette
  set_window_formats
  run get_option window-status-current-format
  # name fg is the mode color, falling back to inner-bg knockout
  assert_output --partial "#[fg=#{?#{window_zoomed_flag},colour81"
  assert_output --partial "monitor-activity,colour109,colour234"   # monitor tint, else knockout
  assert_output --partial "]#I:#W"                                  # …applied to the name
}

# --- badges: status (left) + health (right) ---------------------------------

@test "status badge renders a selector over the projected status scalar" {
  load_render
  _seed_palette
  set_window_formats
  run get_option window-status-format
  assert_output --partial "@airline--badge-status"   # the projected reduced-level scalar
  assert_output --partial "●"                        # a badge glyph (result level)
}

@test "status badge maps each semantic level to its palette color" {
  load_render
  _seed_palette
  set_window_formats
  run get_option window-status-format
  # level→color pairs unique to the status ladder (health has no result/attention)
  assert_output --partial "result},colour114"      # result → ok
  assert_output --partial "attention},colour208"   # attention → alert
}

@test "status badge maps each level to a distinct glyph; active blinks" {
  load_render
  _seed_palette
  set_window_formats
  run get_option window-status-format
  assert_output --partial "active},○"          # a shape per level, redundant with color
  assert_output --partial "result},●"
  assert_output --partial "attention},◆"
  assert_output --partial "active},#[blink]"   # active = watchable
}

@test "health badge maps each level to a distinct glyph; fail blinks" {
  load_render
  _seed_palette
  set_window_formats
  run get_option window-status-format
  assert_output --partial "warn},△"
  assert_output --partial "fail},▲"
  assert_output --partial "fail},#[blink]"
}

@test "window-status-format places status left of the name and health right" {
  load_render
  _seed_palette
  set_window_formats
  run get_option window-status-format
  [[ "$output" == *"@airline--badge-status"*"#I:#W"*"@airline--badge-health"* ]]
}

@test "status_project reduces contributors to the highest level" {
  load_render
  win="$(current_window)"
  coll_set_window "$win" status build  active
  coll_set_window "$win" status test   result
  coll_set_window "$win" status review attention
  status_project "$win"
  run opt_get_window "$win" @airline--badge-status
  assert_output "attention"
}

@test "status_project leaves a blank badge when nothing reports" {
  load_render
  win="$(current_window)"
  status_project "$win" || true   # returns 1 = nothing to render (redraw-gate signal)
  run opt_get_window "$win" @airline--badge-status
  assert_output ""
}

@test "status_project signals change via exit status (gate a redraw)" {
  load_render
  win="$(current_window)"
  coll_set_window "$win" status build active
  # Call directly (not via `run`) so the badge write persists in this shell; capture
  # status with `|| rc=$?` to keep bats' errexit from aborting on the no-change 1.
  rc=0; status_project "$win" || rc=$?   # unset -> active : changed
  assert_equal "$rc" 0
  rc=0; status_project "$win" || rc=$?   # active -> active : no change
  assert_equal "$rc" 1
}

@test "status_project clears the badge when the top contributor is removed" {
  load_render
  win="$(current_window)"
  coll_set_window "$win" status review attention
  status_project "$win"
  coll_unregister_window "$win" status review
  status_project "$win"
  run opt_get_window "$win" @airline--badge-status
  assert_output ""
}

@test "health badge renders a selector over the projected reduced scalar" {
  load_render
  _seed_palette
  set_window_formats
  run get_option window-status-format
  assert_output --partial "@airline--badge-health"   # the projected reduced-level scalar
}

@test "health_project reduces contributors to the worst level scalar" {
  load_render
  win="$(current_window)"
  coll_set_window "$win" health cpu ok
  coll_set_window "$win" health disk warn
  coll_set_window "$win" health net fail
  health_project "$win"
  run opt_get_window "$win" @airline--badge-health
  assert_output "fail"
}

@test "health_project leaves a blank badge when only ok reports" {
  load_render
  win="$(current_window)"
  coll_set_window "$win" health cpu ok
  health_project "$win" || true   # returns 1 = nothing to render (redraw-gate signal)
  run opt_get_window "$win" @airline--badge-health
  assert_output ""
}

@test "health_project signals change via exit status (gate a redraw)" {
  load_render
  win="$(current_window)"
  coll_set_window "$win" health net fail
  rc=0; health_project "$win" || rc=$?   # unset -> fail : changed
  assert_equal "$rc" 0
  rc=0; health_project "$win" || rc=$?   # fail -> fail : no change
  assert_equal "$rc" 1
}

@test "health_project clears the badge when the worst contributor is removed" {
  load_render
  win="$(current_window)"
  coll_set_window "$win" health net fail
  health_project "$win"
  coll_unregister_window "$win" health net
  health_project "$win"
  run opt_get_window "$win" @airline--badge-health
  assert_output ""
}

# --- session problems: contributors reduce to one overall badge -------------

@test "problem badge is renderer-owned at the extreme right" {
  load_render
  _seed_palette
  opt_set_global @airline-segment-right-out OUT
  run _build_status_right
  [[ "$output" == *" OUT "*"@airline--badge-problem"* ]]
  assert_output --partial "bg=colour238"   # inherits the final outer block
  assert_output --partial "warn},△"
  assert_output --partial "fail},▲"
  assert_output --partial "fail},#[blink]"
}

@test "problem_project reduces session contributors to the worst level" {
  load_render
  session="$(current_session)"
  coll_set_session "$session" problem cpu warn "sensors missing"
  coll_set_session "$session" problem battery fail "query timed out"
  problem_project "$session"
  run opt_get_session "$session" @airline--badge-problem
  assert_output "fail"
}

@test "problem_project downgrades and clears as problems recover" {
  load_render
  session="$(current_session)"
  coll_set_session "$session" problem cpu warn "sensors missing"
  coll_set_session "$session" problem battery fail "query timed out"
  problem_project "$session"
  coll_unregister_session "$session" problem battery
  problem_project "$session"
  run opt_get_session "$session" @airline--badge-problem
  assert_output "warn"
  coll_unregister_session "$session" problem cpu
  problem_project "$session"
  run opt_get_session "$session" @airline--badge-problem
  assert_output ""
}

@test "identical problem reports and absent clears do not redraw" {
  load_api
  session="$(current_session)"

  _problem_set "$session" cpu warn "sensors missing"
  assert_equal "$_FAKE_REDRAWS" 1
  _problem_set "$session" cpu warn "sensors missing"
  assert_equal "$_FAKE_REDRAWS" 1

  _problem_clear "$session" cpu
  assert_equal "$_FAKE_REDRAWS" 2
  _problem_clear "$session" cpu
  assert_equal "$_FAKE_REDRAWS" 2
}

# --- render: the render step -------------------------------

@test "render bakes the chrome styles from the palette" {
  load_render
  _seed_palette
  render "$AIRLINE_SESSION"
  run sopt status-style
  assert_output --partial "fg=colour245"   # secondary
  assert_output --partial "bg=colour234"   # inner-bg
  run get_option pane-active-border-style
  assert_output --partial "colour214"      # active
  run get_option clock-mode-color
  assert_output "colour134"                 # special
}

@test "render writes status-left/right from registered segments" {
  load_render
  _seed_palette
  opt_set_global @airline-segment-left-out "LOAD"
  opt_set_global @airline-segment-right-out "TIME"
  render "$AIRLINE_SESSION"
  run sopt status-left
  assert_output --partial "LOAD"
  run sopt status-right
  assert_output --partial "TIME"
}

@test "render composes the window formats too" {
  load_render
  _seed_palette
  render "$AIRLINE_SESSION"
  run get_option window-status-format
  assert_output --partial "#I:#W"
}

@test "render is redraw-gated: a no-op second call reports no change" {
  load_render
  _seed_palette
  opt_set_global @airline-segment-left-out "LOAD"
  rc=0; render "$AIRLINE_SESSION" || rc=$?   # first call: everything changes
  assert_equal "$rc" 0
  rc=0; render "$AIRLINE_SESSION" || rc=$?   # identical state: nothing changes
  assert_equal "$rc" 1
}
