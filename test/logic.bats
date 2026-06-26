#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load
load helper

# compose.sh — the composition layer: the boundary validators (predicates the
# CLI calls), the palette, and the segment-bar composition. compose.sh trusts
# its inputs; validation lives at the boundary, so it is exercised here only as
# the predicates the CLI will call — not as a validate-and-store path.

# --- boundary validators ----------------------------------------------------

@test "_segment_slot_valid accepts the six slots and rejects others" {
  load_compose
  _segment_slot_valid right-mid
  _segment_slot_valid left-out
  ! _segment_slot_valid middle
  ! _segment_slot_valid ""
}

@test "_theme_element_valid accepts palette roles and rejects others" {
  load_compose
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
  load_compose
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
  load_compose
  _seed_palette
  opt_set_global @airline-segment-left-out ONLY   # left-mid, left-in empty
  run _build_status_left
  assert_output --partial " ONLY "
  refute_output --partial "bg=colour236"   # no middle block
  assert_output --partial "bg=colour234"   # chevron into the inner-bg window list
}

@test "an all-empty side composes to nothing" {
  load_compose
  _seed_palette
  run _build_status_left
  assert_output ""
}

@test "right bar composes with a leading chevron from the window list" {
  load_compose
  _seed_palette
  opt_set_global @airline-segment-right-out DATE
  run _build_status_right
  assert_output --partial " DATE "
  assert_output --partial "bg=colour238"   # outer (right-out)
}

@test "suspended dims the outer/middle backgrounds to inner-bg" {
  load_compose
  _seed_palette
  opt_set_global @airline-segment-left-out X
  opt_set_global @airline-suspended 1
  _palette_load
  run _build_status_left
  refute_output --partial "bg=colour238"   # outer dimmed to inner-bg
  assert_output --partial "bg=colour234"
}

# --- window formats ---------------------------------------------------------

@test "window formats set the name template, mode expr, and base styles" {
  load_compose
  _seed_palette
  set_window_formats
  run get_option window-status-format
  assert_output --partial "#I:#W"               # the name template
  assert_output --partial "window_zoomed_flag"  # the mode expression
  run get_option window-status-style
  assert_output --partial "fg=colour250"        # primary
  assert_output --partial "bg=colour234"        # inner-bg
}

@test "window current format knocks out the name in inner-bg and flanks it" {
  load_compose
  _seed_palette
  set_window_formats
  run get_option window-status-current-format
  assert_output --partial "#[fg=colour234]#I:#W"  # name knocked out in inner-bg
  assert_output --partial "window_zoomed_flag"    # highlight bg via mode/active
}

@test "window-status-format honors a custom @airline-tmpl-window" {
  load_compose
  _seed_palette
  opt_set_global @airline-tmpl-window "#W"
  set_window_formats
  run get_option window-status-format
  assert_output --partial "#[default]"
  refute_output --partial "#I:#W"
}
