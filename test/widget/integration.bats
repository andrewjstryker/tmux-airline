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
  assert_output --partial "fg=$(sopt @airline-alert)]≡"
  assert_output --partial "fg=$(sopt @airline-secondary)]≡"
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

@test "unchanged readings preserve sampling cadence and report failure and recovery" {
  airline session init
  mkdir "$BATS_TEST_TMPDIR/catalog"
  cat > "$BATS_TEST_TMPDIR/catalog/steady" <<'WIDGET'
#| summary: Same reading on success and failure
#| interval: 3600
#| timeout: 1
airline_widget_format() { widget_reading; }
airline_widget_sample() {
  printf x >> "$AIRLINE_WIDGET_STATE_DIR/calls"
  printf '?'
  [[ "$(cat "$1")" == ok ]]
}
WIDGET
  airline widget register "$BATS_TEST_TMPDIR/catalog"
  local policy="$BATS_TEST_TMPDIR/policy" id session root dir
  printf 'ok\n' > "$policy"
  printf 'airline_layout_configure() { "$1" widget left-out steady %q; }\n' "$policy" \
    > "$BATS_TEST_TMPDIR/layout"
  airline layout load "$BATS_TEST_TMPDIR/layout"
  id="$(sopt @airline--widgets)"
  load_tmux
  session="$(current_session)"
  root="$(widget_cache_root)"; dir="$root/${session#\$}/$id"

  airline widget run -t bats "$id"
  assert_equal "$(sopt "@airline--widget-$id-value")" '?'
  airline widget run -t bats "$id"
  assert_equal "$(cat "$dir/calls")" x

  # Expire only the sampling cache; keep the published reading unchanged.
  printf '0\n' > "$dir/stamp"
  printf 'fail\n' > "$policy"
  airline widget run -t bats "$id"
  assert_equal "$(sopt "@airline--widget-$id-value")" '?'
  run airline problem show airline-widget "$id"
  assert_success
  assert_output --partial 'sample failed'
  airline widget run -t bats "$id"
  assert_equal "$(cat "$dir/calls")" xx

  printf '0\n' > "$dir/stamp"
  printf 'ok\n' > "$policy"
  airline widget run -t bats "$id"
  assert_equal "$(sopt "@airline--widget-$id-value")" '?'
  assert_equal "$(cat "$dir/calls")" xxx
  run airline problem show airline-widget "$id"
  assert_success
  assert_output ''
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

@test "native widget icons render reading tiers, battery states, and unknown observations" {
  load_tmux
  source "$PROJECT_ROOT/lib/widget.sh"
  AIRLINE_WIDGET_INSTANCE=icons
  widget_job() { :; }
  for role in primary secondary emphasized alert stress active; do
    $TMUX -L "$_bats_socket" set -t bats "@airline-$role" "$role"
  done
  source "$PROJECT_ROOT/layouts/widgets/cpu"
  format="$(airline_widget_format --warn 60 --critical 90)"
  for example in '0 secondary =' '29 secondary =' '30 secondary ≡' '59 secondary ≡' '60 alert ≡' '79 alert ≡' '80 alert ≣' '89 alert ≣' '90 stress ≣' '100 stress ≣'; do
    read -r value color icon <<< "$example"
    $TMUX -L "$_bats_socket" set -t bats @airline--widget-icons-value "$value"
    run resolve "$format"
    assert_success; assert_output "#[fg=$color]$icon"
  done
  for value in '' '?'; do
    $TMUX -L "$_bats_socket" set -t bats @airline--widget-icons-value "$value"
    run resolve "$format"
    assert_output --partial ']—'
  done
  source "$PROJECT_ROOT/layouts/widgets/battery"
  format="$(airline_widget_format)"
  for example in '0 stress ▁' '5 stress ▁' '6 stress ▂' '19 stress ▂' '20 alert ▃' '34 alert ▃' '35 alert ▄' '49 alert ▄' '50 emphasized ▅' '64 emphasized ▅' '65 emphasized ▆' '79 emphasized ▆' '80 primary ▇' '94 primary ▇' '95 primary █' '100 primary █'; do
    read -r value color icon <<< "$example"
    $TMUX -L "$_bats_socket" set -t bats @airline--widget-icons-value "$value:discharging"
    run resolve "$format"
    assert_success; assert_output "#[fg=$color]$icon"
  done
  for example in 'charging active ⚡' 'full primary ⚡' 'attached primary ⚡' 'unknown primary █'; do
    read -r state color icon <<< "$example"
    $TMUX -L "$_bats_socket" set -t bats @airline--widget-icons-value "100:$state"
    run resolve "$format"
    assert_output "#[fg=$color]$icon"
  done
  $TMUX -L "$_bats_socket" set -t bats @airline--widget-icons-value '50:discharging'
  run resolve "$(airline_widget_format --display both)"
  assert_output '#[fg=emphasized]▅#[fg=emphasized]🔋'
  for value in '' '?'; do
    $TMUX -L "$_bats_socket" set -t bats @airline--widget-icons-value "$value"
    run resolve "$format"
    assert_output --partial ']—'
    refute_output --partial '⚡'; refute_output --partial '🔋'
  done
  source "$PROJECT_ROOT/layouts/widgets/online"
  format="$(airline_widget_format)"
  for example in '1 primary ●' '0 stress ●' '? stress —'; do
    read -r value color icon <<< "$example"
    $TMUX -L "$_bats_socket" set -t bats @airline--widget-icons-value "$value"
    run resolve "$format"
    assert_output "#[fg=$color]$icon"
  done
}

@test "prefix badges preserve state precedence and use the effective palette" {
  load_tmux
  source "$PROJECT_ROOT/layouts/widgets/prefix"
  for role in inner-bg active copy special; do
    $TMUX -L "$_bats_socket" set -t bats "@airline-$role" "$role"
  done
  $TMUX -L "$_bats_socket" set -t bats prefix C-a
  format="$(airline_widget_format)"
  # Supply client state explicitly; this detached test has no status client.
  format="${format//client_prefix/@test-prefix}"
  format="${format//client_key_table/@test-table}"
  $TMUX -L "$_bats_socket" set -t bats @test-table root
  run resolve "$format"; assert_output ''
  $TMUX -L "$_bats_socket" set -t bats @test-table custom
  run resolve "$format"; assert_output '#[fg=inner-bg]#[bg=active][custom]'
  $TMUX -L "$_bats_socket" set -w -t bats synchronize-panes on
  run resolve "$format"; assert_output '#[fg=inner-bg]#[bg=special][Sync]'
  $TMUX -L "$_bats_socket" copy-mode -t bats
  run resolve "$format"; assert_output '#[fg=inner-bg]#[bg=copy][Copy]'
  $TMUX -L "$_bats_socket" set -t bats @test-prefix 1
  run resolve "$format"; assert_output '#[fg=inner-bg]#[bg=active][C-a]'
  $TMUX -L "$_bats_socket" set -t bats @airline-active colour123
  run resolve "$format"; assert_output '#[fg=inner-bg]#[bg=colour123][C-a]'
  disabled="$(airline_widget_format --show-copy off --show-sync off)"
  run resolve "$disabled"; assert_output ''
}

@test "widget policy is captured per instance and inspection reports effective arguments" {
  airline session init
  mkdir "$BATS_TEST_TMPDIR/policy"
  cat > "$BATS_TEST_TMPDIR/policy/echo" <<'WIDGET'
#| summary: Captured policy fixture
#| options: message
#| default-message: built in
#| interval: 1
#| timeout: 1
airline_widget_format() { widget_job; widget_literal "$2"; }
airline_widget_sample() { printf '%s' "$2"; }
WIDGET
  airline widget register "$BATS_TEST_TMPDIR/policy"
  $TMUX -L "$_bats_socket" set -g @airline-widget-echo-message 'global value'
  cat > "$BATS_TEST_TMPDIR/policy-layout" <<'LAYOUT'
airline_layout_configure() {
  "$1" widget left-out echo
  "$1" widget right-out echo --message 'placement value'
}
LAYOUT
  airline layout load "$BATS_TEST_TMPDIR/policy-layout"
  read -r first second <<< "$(sopt @airline--widgets)"
  $TMUX -L "$_bats_socket" set -g @airline-widget-echo-message 'changed value'
  airline widget run -t bats "$first"
  airline widget run -t bats "$second"
  assert_equal "$(sopt "@airline--widget-$first-value")" 'global value'
  assert_equal "$(sopt "@airline--widget-$second-value")" 'placement value'
  run airline widget describe echo
  assert_success; assert_output --partial 'effective-arguments'; assert_output --partial "'changed value'"
  assert_equal "$(sopt @airline--widgets)" "$first $second"
  airline layout load "$BATS_TEST_TMPDIR/policy-layout"
  read -r replacement _ <<< "$(sopt @airline--widgets)"
  airline widget run -t bats "$replacement"
  assert_equal "$(sopt "@airline--widget-$replacement-value")" 'changed value'
  before="$(sopt status-left)"
  $TMUX -L "$_bats_socket" set -g @airline-widget-cpu-warn broken
  run airline layout use adaptive
  assert_failure
  assert_equal "$(sopt status-left)" "$before"
}

@test "configured icons remain literal inside native conditionals" {
  load_tmux
  source "$PROJECT_ROOT/lib/widget.sh"
  source "$PROJECT_ROOT/layouts/widgets/cpu"
  AIRLINE_WIDGET_INSTANCE=literal
  widget_job() { :; }
  $TMUX -L "$_bats_socket" set -t bats @airline--widget-literal-value 0
  run resolve "$(airline_widget_format --low-icon 'a,b}#{pane_id}')"
  assert_success; assert_output --partial 'a,b}#{pane_id}'
}
