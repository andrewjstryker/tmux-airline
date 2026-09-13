#!/usr/bin/env bats
load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load
load ../support/helper
setup() { $TMUX -L "$_bats_socket" -f /dev/null new-session -d -s bats; }
@test "widgets compose with public palette references and recolor without observations" {
  airline session init
  cat > "$BATS_TEST_TMPDIR/layout" <<'LAYOUT'
airline_layout_configure() {
  "$1" widget left-out cpu --warn 60 --critical 90
  "$1" segment left-out ' + '
  "$1" widget left-out cpu --warn 80 --critical 95
}
LAYOUT
  airline layout load "$BATS_TEST_TMPDIR/layout"
  left="$(sopt status-left)"
  segment="$(airline segment show left-out)"
  [[ "$left" == *' + '* && "$left" == *'@airline-alert'* ]]
  ids="$(sopt @airline--widgets)"
  read -r first second <<< "$ids"
  [[ -n "$first" && -n "$second" && "$first" != "$second" ]]
  $TMUX -L "$_bats_socket" set -t bats "@airline--widget-$first-value" 75
  $TMUX -L "$_bats_socket" set -t bats "@airline--widget-$second-value" 75
  run resolve "$(sed 's/#([^)]*)//g' <<< "$left")"
  assert_success
  assert_output --partial 'CPU 75%'
  assert_output --partial "fg=$(sopt @airline-alert)"
  airline palette use light
  [[ "$(airline segment show left-out)" == "$segment" ]]
  run resolve "$(sopt status-left | sed 's/#([^)]*)//g')"
  assert_output --partial "fg=$(sopt @airline-alert)"
  base="$(sopt @airline-primary)"
  airline session suspend
  [[ "$(sopt @airline-primary)" == "$(sopt @airline-secondary)" ]]
  airline session resume
  [[ "$(sopt @airline-primary)" == "$base" ]]
}
@test "CPU runtime is instance scoped and caches observations" {
  airline session init
  export AIRLINE_CPU_STAT="$BATS_TEST_TMPDIR/stat"
  echo 'cpu 100 0 100 800 0 0 0 0' > "$AIRLINE_CPU_STAT"
  for id in $(sopt @airline--widgets); do
    [[ "$(sopt "@airline--widget-$id-name")" != cpu ]] || break
  done
  run airline widget run -t bats "$id"
  assert_success
  [[ "$(sopt "@airline--widget-$id-value")" == '?' ]]
  echo 'cpu 150 0 125 825 0 0 0 0' > "$AIRLINE_CPU_STAT"
  airline widget run -t bats "$id"
  [[ "$(sopt "@airline--widget-$id-value")" == '?' ]]
  airline layout use minimal
  run airline widget run -t bats "$id"
  assert_failure
}
@test "palette inspection never changes the live public palette and manual changes stay local" {
  airline session init
  before="$(sopt @airline-primary)"
  airline palette describe light
  [[ "$(sopt @airline-primary)" == "$before" ]]
  $TMUX -L "$_bats_socket" set -t bats @airline-primary colour99
  airline session apply
  [[ "$(sopt @airline-primary)" == colour99 ]]
  $TMUX -L "$_bats_socket" set -g @airline-primary colour88
  airline session apply
  [[ "$(sopt @airline-primary)" == colour99 ]]
}

@test "widget inspection preserves arguments and optional placement only hides unavailable capabilities" {
  airline session init
  mkdir "$BATS_TEST_TMPDIR/catalog"
  cat > "$BATS_TEST_TMPDIR/catalog/echo" <<'WIDGET'
#| summary: Echo literal arguments
airline_widget_format() { printf '%s' "$1"; }
WIDGET
  cat > "$BATS_TEST_TMPDIR/catalog/absent" <<'WIDGET'
#| summary: Unavailable fixture
airline_widget_format() { (( $# == 0 )) || return 2; printf absent; }
airline_widget_available() { return 3; }
WIDGET
  airline widget register "$BATS_TEST_TMPDIR/catalog"
  run airline widget describe echo 'argument with spaces'
  assert_success; assert_output --partial 'argument with spaces'
  run airline widget describe echo $'bad\nformat'
  assert_failure
  cat > "$BATS_TEST_TMPDIR/optional" <<'LAYOUT'
airline_layout_configure() {
  "$1" segment left-out 'before'
  "$1" widget-optional left-out absent
  "$1" segment left-out 'after'
}
LAYOUT
  airline layout load "$BATS_TEST_TMPDIR/optional"
  [[ "$(sopt status-left)" == *before*after* ]]
  run airline widget describe absent bad-argument
  assert_failure 2
}

@test "timed out widgets report failure and retired instances cannot publish" {
  airline session init
  mkdir "$BATS_TEST_TMPDIR/catalog"
  cat > "$BATS_TEST_TMPDIR/catalog/slow" <<'WIDGET'
#| summary: Slow observation
#| interval: 1
#| timeout: 1
airline_widget_format() { widget_job; }
airline_widget_sample() { sleep 5; echo 99; }
WIDGET
  airline widget register "$BATS_TEST_TMPDIR/catalog"
  cat > "$BATS_TEST_TMPDIR/slow-layout" <<'LAYOUT'
airline_layout_configure() { "$1" widget left-out slow; }
LAYOUT
  airline layout load "$BATS_TEST_TMPDIR/slow-layout"
  read -r id _ <<< "$(sopt @airline--widgets)"
  airline widget run -t bats "$id"
  [[ "$(sopt "@airline--widget-$id-value")" == '?' ]]
  run airline problem show airline-widget "$id"
  assert_output --partial 'sample failed'
  airline layout use minimal
  run airline problem show airline-widget "$id"
  assert_output ''
  run airline widget run -t bats "$id"
  assert_failure
  [[ -z "$(sopt "@airline--widget-$id-value")" ]]
}

@test "tmux jobs publish to their owning session and repeated requests never overlap" {
  airline session init
  mkdir "$BATS_TEST_TMPDIR/catalog"
  cat > "$BATS_TEST_TMPDIR/catalog/owner" <<'WIDGET'
#| summary: Owning session observation
#| interval: 10
#| timeout: 2
airline_widget_format() { widget_job; widget_reading; }
airline_widget_sample() {
  printf x >> "$AIRLINE_WIDGET_STATE_DIR/calls"
  sleep 0.2
  printf '%s:%s' "$AIRLINE_WIDGET_SESSION" "$1"
}
WIDGET
  airline widget register "$BATS_TEST_TMPDIR/catalog"
  cat > "$BATS_TEST_TMPDIR/layout" <<'LAYOUT'
airline_layout_configure() { "$1" widget left-out owner "argument with ' quotes"; }
LAYOUT
  airline layout load "$BATS_TEST_TMPDIR/layout"
  owner="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{session_id}')"
  id="$(sopt @airline--widgets -t "$owner")"
  $TMUX -L "$_bats_socket" new-session -d -s other
  airline_session other session init
  format="$(sopt status-left -t "$owner")"
  # display-message alone has no status client and does not start #() jobs.
  mkfifo "$BATS_TEST_TMPDIR/client-input"
  exec {client_input}<>"$BATS_TEST_TMPDIR/client-input"
  TERM=xterm-256color script -q -c "$TMUX -L $_bats_socket attach-session -t bats" /dev/null \
    < "$BATS_TEST_TMPDIR/client-input" > "$BATS_TEST_TMPDIR/client-output" 2>&1 3>&- & client=$!
  for _ in {1..100}; do
    $TMUX -L "$_bats_socket" display-message -p -t bats "$format" >/dev/null
    [[ "$(sopt "@airline--widget-$id-value" -t "$owner")" == "$owner:argument with ' quotes" ]] && break
    sleep 0.05
  done
  assert_equal "$(sopt "@airline--widget-$id-value" -t "$owner")" "$owner:argument with ' quotes"
  [[ -z "$(sopt "@airline--widget-$id-value" -t other)" ]]
  airline widget run -t "$owner" "$id" & one=$!
  airline widget run -t "$owner" "$id" & two=$!
  wait "$one"; wait "$two"
  load_tmux
  root="$(widget_cache_root)"
  assert_equal "$(cat "$root/${owner#\$}/$id/calls")" x
  $TMUX -L "$_bats_socket" detach-client -s bats
  wait "$client"
  exec {client_input}>&-
}

@test "replacement rejects late observations and slot overrides retire only their own instances" {
  airline session init
  mkdir "$BATS_TEST_TMPDIR/catalog"
  cat > "$BATS_TEST_TMPDIR/catalog/slow" <<'WIDGET'
#| summary: Retirement race
#| interval: 2
#| timeout: 2
airline_widget_format() { widget_job; }
airline_widget_sample() { touch "$1"; sleep 0.5; printf late; }
WIDGET
  airline widget register "$BATS_TEST_TMPDIR/catalog"
  export WIDGET_STARTED="$BATS_TEST_TMPDIR/started"
  cat > "$BATS_TEST_TMPDIR/layout" <<'LAYOUT'
airline_layout_configure() {
  "$1" widget left-out slow "$WIDGET_STARTED"
  "$1" widget right-out prefix
}
LAYOUT
  airline layout load "$BATS_TEST_TMPDIR/layout"
  read -r old keep <<< "$(sopt @airline--widgets)"
  airline widget run -t bats "$old" >/dev/null & worker=$!
  for _ in {1..100}; do [[ -e "$WIDGET_STARTED" ]] && break; sleep 0.01; done
  [[ -e "$WIDGET_STARTED" ]]
  $TMUX -L "$_bats_socket" set -g @airline-segment-left-out replacement
  airline session apply
  wait "$worker" || true
  assert_equal "$(sopt @airline--widgets)" "$keep"
  [[ -z "$(sopt "@airline--widget-$old-value")" ]]
  run airline problem show airline-widget "$old"
  assert_output ''
}

@test "session cleanup removes departed caches and leaves live session state" {
  airline session init
  load_tmux
  root="$(widget_cache_root)"
  session="$(resolve_session_target bats)"
  mkdir -p "$root/${session#\$}/retained" "$root/999999/old"
  source "$PROJECT_ROOT/lib/widget.sh"
  widget_collect
  [[ -d "$root/${session#\$}/retained" && ! -e "$root/999999" ]]
  widget_cleanup '$999999'
  [[ -d "$root/${session#\$}/retained" ]]
}
