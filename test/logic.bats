#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load
load helper

# render.sh — the composition layer: the boundary validators (predicates the
# CLI calls), the palette, and the segment-bar composition. render.sh trusts
# its inputs; validation lives at the boundary, so it is exercised here only as
# the predicates the CLI will call — not as a validate-and-store path.

# --- boundary validators ----------------------------------------------------

@test "_segment_slot_valid accepts the six slots and rejects others" {
  load_render
  _segment_slot_valid right-mid
  _segment_slot_valid left-out
  ! _segment_slot_valid middle
  ! _segment_slot_valid ""
}

@test "_theme_element_valid accepts palette roles and rejects others" {
  load_render
  _theme_element_valid active
  _theme_element_valid outer-bg
  ! _theme_element_valid bogus
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

@test "an all-empty side composes to nothing" {
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
  opt_set_global @airline--suspended 1
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
  assert_output --partial "●"                        # the default badge glyph
}

@test "status badge maps each semantic level to its theme color" {
  load_render
  _seed_palette
  set_window_formats
  run get_option window-status-format
  # level→color pairs unique to the status ladder (health has no result/attention)
  assert_output --partial "result},colour114"      # result → ok
  assert_output --partial "attention},colour208"   # attention → alert
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
  run status_project "$win"        # unset -> active : changed
  assert_success
  run status_project "$win"        # active -> active : no change
  assert_failure
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
  assert_output --partial "@airline--badge-health"   # the projected reduced-severity scalar
}

@test "health_project reduces contributors to the max severity scalar" {
  load_render
  win="$(current_window)"
  coll_set_window "$win" health cpu ok
  coll_set_window "$win" health disk alert
  coll_set_window "$win" health net stress
  health_project "$win"
  run opt_get_window "$win" @airline--badge-health
  assert_output "stress"
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
  coll_set_window "$win" health net stress
  run health_project "$win"        # unset -> stress : changed
  assert_success
  run health_project "$win"        # stress -> stress : no change
  assert_failure
}

@test "health_project clears the badge when the worst contributor is removed" {
  load_render
  win="$(current_window)"
  coll_set_window "$win" health net stress
  health_project "$win"
  coll_unregister_window "$win" health net
  health_project "$win"
  run opt_get_window "$win" @airline--badge-health
  assert_output ""
}

# --- render: the render step -------------------------------

@test "render bakes the chrome styles from the palette" {
  load_render
  _seed_palette
  render
  run get_option status-style
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
  render
  run get_option status-left
  assert_output --partial "LOAD"
  run get_option status-right
  assert_output --partial "TIME"
}

@test "render composes the window formats too" {
  load_render
  _seed_palette
  render
  run get_option window-status-format
  assert_output --partial "#I:#W"
}

@test "render is redraw-gated: a no-op second call reports no change" {
  load_render
  _seed_palette
  opt_set_global @airline-segment-left-out "LOAD"
  run render          # first call: everything changes
  assert_success
  run render          # identical state: nothing changes
  assert_failure
}
