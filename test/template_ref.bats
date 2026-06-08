#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load
load helper

# tmpl_ref builds a live #{?option,#{E:option},default} reference so a template
# option is resolved on every redraw instead of snapshotted at load.

@test "tmpl_ref wraps the option in a conditional with E: expansion" {
  load_airline
  run tmpl_ref @airline_tmpl_right_middle "DEFAULT"
  assert_output '#{?@airline_tmpl_right_middle,#{E:@airline_tmpl_right_middle},DEFAULT}'
}

@test "tmpl_ref escapes commas in the default so they don't split the conditional" {
  load_airline
  run tmpl_ref @airline_tmpl_right_middle '#[fg=red,bg=blue]X'
  assert_output '#{?@airline_tmpl_right_middle,#{E:@airline_tmpl_right_middle},#[fg=red#,bg=blue]X}'
}

@test "tmpl_ref: empty default yields an empty false-branch" {
  load_airline
  run tmpl_ref @airline_tmpl_left_outer ""
  assert_output '#{?@airline_tmpl_left_outer,#{E:@airline_tmpl_left_outer},}'
}

@test "tmpl_ref resolves to the option value when set" {
  init_theme
  $TMUX -L "$_bats_socket" set -g @t_opt 'CHOSEN'
  run resolve "$(tmpl_ref @t_opt 'FALLBACK')"
  assert_output "CHOSEN"
}

@test "tmpl_ref resolves to the default when the option is unset" {
  init_theme
  run resolve "$(tmpl_ref @t_missing 'FALLBACK')"
  assert_output "FALLBACK"
}

@test "tmpl_ref default with escaped commas renders real commas" {
  init_theme
  run resolve "$(tmpl_ref @t_missing '#[fg=colour1,bg=colour8]')"
  assert_output '#[fg=colour1,bg=colour8]'
}
