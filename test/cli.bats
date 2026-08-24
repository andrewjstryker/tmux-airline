#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load
load helper

# The CLI/API boundary (the `airline` executable) on the new layer. These drive the
# real CLI as a subprocess (the `airline()` helper points it at the isolated server
# via AIRLINE_TMUX), so they exercise the same path production uses.
#
# A clean server (-f /dev/null) so `init`'s default-seeding isn't perturbed by the
# developer's own ~/.tmux.conf (which may already configure airline).

setup() {
  $TMUX -L "$_bats_socket" -f /dev/null new-session -d -s bats
}

# --- init -------------------------------------------------------------------

@test "init publishes the CLI path as the public bootstrap handle + sets the sentinel" {
  airline init
  run get_option @airline-cli          # public (single dash) — the one published handle
  assert_output --partial "/airline"
  run sopt @airline--defaults-done
  assert_output "1"
}

@test "init applies the default palette when no palette is set" {
  airline init
  run sopt @airline-inner-bg
  assert_output "colour234"          # palette use default
  run sopt @airline--palette
  assert_output "default"            # recorded
}

@test "init applies the adaptive layout (segments) when none is set" {
  airline init
  run sopt status-left
  assert_output --partial "#S"       # adaptive sets left-out=#S (present with or without plugins)
  run sopt @airline--layout
  assert_output "adaptive"           # recorded, so apply re-applies it
}

@test "init does not clobber a user-set palette" {
  $TMUX -L "$_bats_socket" set -g @airline-inner-bg colour99
  airline init
  run get_option @airline-inner-bg
  assert_output "colour99"           # user value preserved; default not applied
}

@test "init is idempotent: a reload keeps runtime segment changes" {
  airline init
  $TMUX -L "$_bats_socket" set -t bats @airline-segment-left-out "CUSTOM"
  airline init                       # sentinel set → no re-seed
  run sopt @airline-segment-left-out
  assert_output "CUSTOM"
}

@test "init composes the bar (chrome + window formats)" {
  airline init
  run sopt status-style
  assert_output --partial "bg=colour234"
  run get_option window-status-current-format
  assert_output --partial "#I:#W"
}

@test "the global lifecycle hook initializes sessions created after airline loads" {
  airline init
  $TMUX -L "$_bats_socket" new-session -d -s later
  later="$($TMUX -L "$_bats_socket" display-message -p -t later '#{session_id}')"

  value=""
  # The production hook is intentionally asynchronous so creating a session is
  # never held up by palette/layout work. Allow for a loaded CI host here.
  for _ in {1..200}; do
    value="$(sopt @airline--defaults-done -t "$later")"
    [[ "$value" == 1 ]] && break
    sleep 0.05
  done
  assert_equal "$value" "1"
  run sopt @airline--palette -t "$later"
  assert_output "default"
}

# --- apply / use ------------------------------------------------------------

@test "apply renders from the current source of truth" {
  airline init
  # a palette element is source-of-truth (not layout-managed, so apply won't reset it)
  $TMUX -L "$_bats_socket" set -t bats @airline-active "colour201"
  airline apply
  run get_option window-status-current-format
  assert_output --partial "colour201"
}

@test "show reports the active config and recurses into the static nouns" {
  airline init
  run airline show
  assert_success
  assert_output --partial "layout"      # a top-level record
  assert_output --partial "default"     # its active value
  assert_output --partial "inner-bg"    # recursed into palette show
  assert_output --partial "left-out"    # recursed into segment show
  assert_output --partial "paths:"      # the search paths
  assert_output --partial "/palettes"   # the shipped palette dir on the path
  refute_output --partial "health"      # dynamic per-window nouns excluded from the walk
}

@test "register blesses a dir; use loads a bare name from it, then renders" {
  airline init
  mkdir -p "$BATS_TMPDIR/mypalettes"
  printf 'set @airline-inner-bg colour55\n' > "$BATS_TMPDIR/mypalettes/custom"
  airline palette register "$BATS_TMPDIR/mypalettes"
  airline palette use custom
  run sopt @airline-inner-bg
  assert_output "colour55"
  run sopt status-style
  assert_output --partial "bg=colour55"     # rendered with the new color
}

@test "palette use rejects an unknown name and a path (no literal-path escape)" {
  airline init
  run airline palette use no-such-palette-xyz
  assert_failure
  run airline palette use /etc/passwd        # a path is not a bare name
  assert_failure
}

@test "palette use resolves a bare name on the shipped search path" {
  airline init
  run airline palette use light       # a shipped bare name → found on the registered palettes/ dir
  assert_success
}

@test "register prepends: a registered dir shadows the shipped one" {
  airline init
  mkdir -p "$BATS_TMPDIR/shadow"
  printf 'set @airline-inner-bg colour42\n' > "$BATS_TMPDIR/shadow/dark"   # same name as shipped
  airline palette register "$BATS_TMPDIR/shadow"
  airline palette use dark
  run sopt @airline-inner-bg
  assert_output "colour42"            # the registered dark won, not the shipped colour234
}

@test "use records the active selection" {
  airline init
  airline palette use light
  run sopt @airline--palette
  assert_output "light"
}

# --- palette / segment (static config nouns: read-only `show`, written via set -g) --

@test "a directly-set color renders after apply" {
  airline init
  $TMUX -L "$_bats_socket" set -t bats @airline-active colour201
  airline apply
  run get_option window-status-current-format
  assert_output --partial "colour201"   # rendered into the bar (active highlight)
}

@test "palette show X prints one element; palette show prints all" {
  airline init
  $TMUX -L "$_bats_socket" set -t bats @airline-active colour201
  run airline palette show active
  assert_output "colour201"
  run airline palette show
  assert_output --partial "active"
  assert_output --partial "inner-bg"
}

@test "palette show rejects an unknown element" {
  airline init
  run airline palette show bogus
  assert_failure
}

@test "segment show reads back a directly-set slot option" {
  $TMUX -L "$_bats_socket" set -g @airline-segment-left-out "#H"   # the only write path
  airline init
  run airline segment show left-out
  assert_output "#H"
}

@test "segment show rejects an unknown slot" {
  airline init
  run airline segment show middle
  assert_failure
}

# --- adapter (dynamic: apply palette → a plugin's options) ------------------

@test "adapter use applies the current palette to the plugin's options" {
  airline init
  airline adapter use cpu
  # behaviour, not content: cpu's low-severity fg == the palette's secondary value
  run sopt @cpu_low_fg_color
  assert_output "$(sopt @airline-secondary)"
}

@test "adapter use re-applies literal colours on a palette change" {
  airline init
  airline adapter use cpu
  $TMUX -L "$_bats_socket" set -t bats @airline-secondary colour99
  airline adapter use cpu                   # re-run the adapter
  run sopt @cpu_low_fg_color
  assert_output "colour99"                   # picked up the new palette value
}

@test "adapter use rejects an unknown name" {
  airline init
  run airline adapter use no-such-adapter
  assert_failure
}

@test "adapter available lists the catalog on the path (what you can use)" {
  airline init
  run airline adapter available
  assert_line "cpu"                     # one name per line
  assert_line "battery"
  assert_line "online"
}

@test "adapter use records the applied adapter; adapter show reads the active set raw" {
  airline init
  airline adapter use cpu battery       # multi-target
  run airline adapter show
  assert_line "cpu"                     # one name per line, script-safe (`for a in $(…)`)
  assert_line "battery"
}

@test "a layout switch clears the previous layout's adapter set (clean slate)" {
  airline init
  mkdir -p "$BATS_TMPDIR/adps"
  printf '#!/usr/bin/env bash\nairline adapter use cpu\n' > "$BATS_TMPDIR/adps/withcpu"
  printf '#!/usr/bin/env bash\n$AIRLINE_TMUX set -t "$AIRLINE_SESSION" @airline-segment-left-out "#S"\n' > "$BATS_TMPDIR/adps/bare"
  airline layout register "$BATS_TMPDIR/adps"
  airline layout use withcpu
  run airline adapter show
  assert_line "cpu"                     # recorded by the layout
  airline layout use bare               # applies no adapters → clears the set
  run airline adapter show
  assert_output ""                      # nothing active after the switch
}

@test "available is uniform across the loadable kinds (palette, layout)" {
  airline init
  run airline palette available
  assert_line "default"                 # shipped palettes
  assert_line "dark"
  run airline layout available
  assert_line "adaptive"                # shipped layouts
  assert_line "minimal"
}

# --- layout (dynamic: a composition script, stored + re-applied) ------------

@test "layout use runs the composition script and records the active layout" {
  airline init
  $TMUX -L "$_bats_socket" set -t bats @airline-segment-left-out "SCRATCH"
  airline layout use default          # its `set -g @airline-segment-left-out "#S"` resets the slot
  run sopt @airline-segment-left-out
  assert_output "#S"                   # composition applied
  run sopt @airline--layout
  assert_output "default"              # recorded active
}

@test "apply re-runs the stored layout" {
  airline init
  airline layout use default
  $TMUX -L "$_bats_socket" set -t bats @airline-segment-left-out "SCRATCH"
  airline apply                        # re-runs default → sets @airline-segment-left-out
  run sopt @airline-segment-left-out
  assert_output "#S"                    # restored by the re-run
}

@test "a layout may apply an adapter; palette drives its colours" {
  airline init
  mkdir -p "$BATS_TMPDIR/mylayouts"
  printf '#!/usr/bin/env bash\nairline adapter use cpu\n$AIRLINE_TMUX set -t "$AIRLINE_SESSION" @airline-segment-left-out "#S"\n' \
    > "$BATS_TMPDIR/mylayouts/withcpu"
  airline layout register "$BATS_TMPDIR/mylayouts"
  airline layout use withcpu
  run sopt @cpu_low_fg_color      # the adapter ran inside the layout
  assert_output "$(sopt @airline-secondary)"
}

@test "a layout switch clears the previous layout's slots (clean slate)" {
  airline init
  mkdir -p "$BATS_TMPDIR/switch"
  printf '#!/usr/bin/env bash\n$AIRLINE_TMUX set -t "$AIRLINE_SESSION" @airline-segment-left-mid "MID"\n' > "$BATS_TMPDIR/switch/rich"
  printf '#!/usr/bin/env bash\n$AIRLINE_TMUX set -t "$AIRLINE_SESSION" @airline-segment-left-out "OUT"\n' > "$BATS_TMPDIR/switch/lean"
  airline layout register "$BATS_TMPDIR/switch"
  airline layout use rich
  run sopt @airline-segment-left-mid
  assert_output "MID"
  airline layout use lean                # lean never sets left-mid
  run sopt @airline-segment-left-mid
  assert_output ""                       # cleared — not stale from rich
}

@test "a layout that sets the palette does not loop (re-entrancy guard)" {
  airline init
  mkdir -p "$BATS_TMPDIR/loopy"
  printf '#!/usr/bin/env bash\nairline palette use light\n$AIRLINE_TMUX set -t "$AIRLINE_SESSION" @airline-segment-left-out "#S"\n' \
    > "$BATS_TMPDIR/loopy/rogue"
  airline layout register "$BATS_TMPDIR/loopy"
  run timeout 20 env AIRLINE_TMUX="$TMUX -L $_bats_socket" AIRLINE_DIR="$PROJECT_ROOT" \
    "$PROJECT_ROOT/airline" layout use rogue
  assert_success                         # returns (no apply→layout→apply fork-bomb)
  run sopt @airline--applying
  assert_output "0"                      # guard cleaned up
}

@test "a failed layout registers an internal session problem and a retry clears it" {
  airline init
  session="$($TMUX -L "$_bats_socket" display-message -p '#{session_id}')"
  mkdir -p "$BATS_TMPDIR/failing-layout"
  printf '#!/usr/bin/env bash\nexit 7\n' > "$BATS_TMPDIR/failing-layout/unstable"
  airline layout register "$BATS_TMPDIR/failing-layout"
  airline layout use unstable             # failure is contained so airline remains usable
  run airline problem show "$session" airline-layout
  assert_output "$(printf "fail\tlayout 'unstable' exited with status 7")"

  printf '#!/usr/bin/env bash\n$AIRLINE_TMUX set -t "$AIRLINE_SESSION" @airline-segment-left-out "RECOVERED"\n' \
    > "$BATS_TMPDIR/failing-layout/unstable"
  airline apply
  run airline problem show "$session" airline-layout
  assert_output ""
}

@test "layout load runs a one-off by path and records the ABSOLUTE path for re-apply" {
  airline init
  printf '#!/usr/bin/env bash\n$AIRLINE_TMUX set -t "$AIRLINE_SESSION" @airline-segment-left-out "#S"\n' > "$BATS_TMPDIR/oneoff"
  airline layout load "$BATS_TMPDIR/oneoff"
  run sopt @airline--layout
  assert_output --regexp '^/.*/oneoff$'   # absolute path recorded (not a bare name)
  # apply re-runs the loaded layout (resets a perturbed slot)
  $TMUX -L "$_bats_socket" set -t bats @airline-segment-left-out "SCRATCH"
  airline apply
  run sopt @airline-segment-left-out
  assert_output "#S"
}

@test "layout load rejects a missing file (no path walk, but must exist)" {
  airline init
  run airline layout load /no/such/layout-file
  assert_failure
}

@test "adapter load applies a one-off adapter script (palette-driven, not recorded)" {
  airline init
  printf 'opt_set_session "$AIRLINE_SESSION" @custom_fg "${PALETTE[active]}"\n' > "$BATS_TMPDIR/oneoff-adapter"
  airline adapter load "$BATS_TMPDIR/oneoff-adapter"
  run sopt @custom_fg
  assert_output "$(sopt @airline-active)"   # applied the current palette
}

@test "palette use re-applies the active layout's adapters to the new palette" {
  airline init
  mkdir -p "$BATS_TMPDIR/pl"
  printf '#!/usr/bin/env bash\nairline adapter use cpu\n$AIRLINE_TMUX set -t "$AIRLINE_SESSION" @airline-segment-left-out "#S"\n' \
    > "$BATS_TMPDIR/pl/withcpu"
  airline layout register "$BATS_TMPDIR/pl"
  airline layout use withcpu            # cpu adapter active, coloured by the dark palette
  airline palette use light             # swap palette → must re-colour cpu
  run sopt @cpu_low_fg_color
  assert_output "$(sopt @airline-secondary)"   # tracks light's secondary now
}

@test "adapter use applies multiple plugins in one call (multi-target)" {
  airline init
  airline adapter use cpu battery       # one call, both applied
  run sopt @cpu_low_fg_color
  assert_output "$(sopt @airline-secondary)"
  run sopt @batt_color_full_charge
  assert_success                        # battery adapter ran too (option is set)
  refute_output ""
}

# --- session isolation ------------------------------------------------------

@test "palette, layout, adapter, and guard state are isolated by session" {
  airline init
  one="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{session_id}')"
  $TMUX -L "$_bats_socket" new-session -d -s other
  other="$($TMUX -L "$_bats_socket" display-message -p -t other '#{session_id}')"
  airline_session "$other" init

  airline_session "$one" palette use light
  run sopt @airline-inner-bg -t "$one"
  assert_output "colour231"
  run sopt @airline-inner-bg -t "$other"
  assert_output "colour234"

  airline_session "$one" layout use minimal
  airline_session "$other" layout use default
  run sopt @airline-segment-right-out -t "$one"
  assert_output ""
  run sopt @airline-segment-right-out -t "$other"
  assert_output "%Y-%m-%d %H:%M"

  airline_session "$one" adapter use cpu
  run sopt @cpu_low_fg_color -t "$one"
  assert_output "colour245"
  run sopt @cpu_low_fg_color -t "$other"
  assert_output "colour246"

  $TMUX -L "$_bats_socket" set -t "$one" @airline--applying 1
  airline_session "$other" layout use minimal
  run sopt @airline--layout -t "$other"
  assert_output "minimal"
}

@test "global user configuration is inherited without becoming mutable runtime state" {
  for element in outer-bg middle-bg inner-bg secondary primary emphasized active \
    special ok alert stress zoom copy monitor; do
    $TMUX -L "$_bats_socket" set -g "@airline-$element" colour99
  done
  $TMUX -L "$_bats_socket" set -g @airline-inner-bg colour99
  $TMUX -L "$_bats_socket" set -g @airline-segment-left-out GLOBAL
  airline init
  one="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{session_id}')"
  $TMUX -L "$_bats_socket" new-session -d -s other
  other="$($TMUX -L "$_bats_socket" display-message -p -t other '#{session_id}')"
  airline_session "$other" init

  run airline_session "$one" palette show inner-bg
  assert_output "colour99"
  run airline_session "$other" palette show inner-bg
  assert_output "colour99"

  airline_session "$one" palette use light
  run get_option @airline-inner-bg
  assert_output "colour99"             # runtime use did not rewrite the default
  run airline_session "$other" palette show inner-bg
  assert_output "colour99"
}

@test "AIRLINE_SESSION cannot override tmux's native pane context" {
  airline init
  one="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{session_id}')"
  pane="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{pane_id}')"
  $TMUX -L "$_bats_socket" new-session -d -s other
  other="$($TMUX -L "$_bats_socket" display-message -p -t other '#{session_id}')"
  airline_session "$other" init

  AIRLINE_SESSION="$other" TMUX_PANE="$pane" AIRLINE_DIR="$PROJECT_ROOT" \
    AIRLINE_TMUX="$TMUX -L $_bats_socket" "$PROJECT_ROOT/airline" palette use light

  run sopt @airline-inner-bg -t "$one"
  assert_output "colour231"
  run sopt @airline-inner-bg -t "$other"
  assert_output "colour234"
}

# --- status (dynamic noun) --------------------------------------------------

@test "status set lights the badge; clear removes it" {
  airline init
  airline status set build active
  run wopt @airline--badge-status
  assert_output "active"
  airline status clear build
  run wopt @airline--badge-status
  assert_output ""
}

@test "status set reduces multiple contributors by precedence" {
  airline init
  airline status set build active
  airline status set review attention
  run wopt @airline--badge-status
  assert_output "attention"          # attention outranks active
}

@test "status set rejects an invalid level" {
  airline init
  run airline status set x bogus
  assert_failure
}

@test "status show lists contributors; status show X prints one level" {
  airline init
  airline status set build active
  run airline status show
  assert_output --partial "build"
  assert_output --partial "active"
  run airline status show build
  assert_output "active"
}

@test "status and health accept a pane target and store on its containing window" {
  airline init
  pane="$($TMUX -L "$_bats_socket" display-message -p -t bats '#{pane_id}')"
  window="$($TMUX -L "$_bats_socket" display-message -p -t "$pane" '#{window_id}')"

  airline status set agent active -t "$pane"
  airline health set agent warn -t "$pane"

  run wopt @airline--badge-status -t "$window"
  assert_output "active"
  run wopt @airline--badge-health -t "$window"
  assert_output "warn"
}

@test "signal commands reject -t without a window target" {
  run airline status set build active -t
  assert_failure
  assert_output --partial "status set: -t requires <window>"

  run airline status clear build -t
  assert_failure
  assert_output --partial "status clear: -t requires <window>"

  run airline status show -t
  assert_failure
  assert_output --partial "status show: -t requires <window>"
}

# --- health (dynamic noun) --------------------------------------------------

@test "health set/clear drives the health badge" {
  airline init
  airline health set cpu warn
  run wopt @airline--badge-health
  assert_output "warn"
  airline health clear cpu
  run wopt @airline--badge-health
  assert_output ""
}

@test "health set ok records recovery by clearing the contributor" {
  airline init
  airline health set cpu fail
  airline health set cpu ok
  run airline health show cpu
  assert_output ""
  run wopt @airline--badge-health
  assert_output ""
}

@test "health set rejects an invalid level" {
  airline init
  run airline health set disk warpspeed
  assert_failure
}

# --- problem (session-scoped widget failures) -------------------------------

@test "problem contributors reduce to one session badge and recover independently" {
  airline init
  session="$($TMUX -L "$_bats_socket" display-message -p '#{session_id}')"
  airline problem set "$session" cpu warn "required program 'sensors' was not found"
  airline problem set "$session" battery fail "battery query timed out"
  run sopt @airline--badge-problem -t "$session"
  assert_output "fail"
  run $TMUX -L "$_bats_socket" display-message -p -t "$session" '#{E:status-right}'
  assert_output --partial "▲"       # the session scalar drives the extreme-right glyph

  $TMUX -L "$_bats_socket" new-session -d -s other
  other="$($TMUX -L "$_bats_socket" display-message -p -t other '#{session_id}')"
  run sopt @airline--badge-problem -t "$other"
  assert_output ""                  # no server-global leakage into another session
  run $TMUX -L "$_bats_socket" display-message -p -t "$other" '#{E:status-right}'
  refute_output --partial "▲"

  run airline problem show "$session"
  assert_output --partial "cpu"
  assert_output --partial "sensors"
  assert_output --partial "battery"
  assert_output --partial "battery query timed out"

  airline problem clear "$session" battery
  run sopt @airline--badge-problem -t "$session"
  assert_output "warn"
  airline problem clear "$session" cpu
  run sopt @airline--badge-problem -t "$session"
  assert_output ""
}

@test "problem show SESSION KEY returns its level and message as a raw tuple" {
  airline init
  session="$($TMUX -L "$_bats_socket" display-message -p '#{session_id}')"
  airline problem set "$session" cpu warn "sensors missing"
  run airline problem show "$session" cpu
  assert_output "$(printf 'warn\tsensors missing')"
}

@test "problem set ok records recovery without requiring a message" {
  airline init
  session="$($TMUX -L "$_bats_socket" display-message -p '#{session_id}')"
  airline problem set "$session" cpu fail "query failed"
  airline problem set "$session" cpu ok
  run airline problem show "$session" cpu
  assert_output ""
  run sopt @airline--badge-problem -t "$session"
  assert_output ""
}

@test "problem set validates level, message, and session target" {
  airline init
  session="$($TMUX -L "$_bats_socket" display-message -p '#{session_id}')"
  run airline problem set
  assert_failure
  assert_output --partial "problem set: need <session>"
  run airline problem set "$session" cpu bogus "bad level"
  assert_failure
  run airline problem set "$session" cpu warn
  assert_failure
  run airline problem clear "$session"
  assert_failure
  assert_output --partial "problem clear: need <key>"
}

@test "bare problem show lists problems across sessions" {
  airline init
  session="$($TMUX -L "$_bats_socket" display-message -p '#{session_id}')"
  $TMUX -L "$_bats_socket" new-session -d -s other
  other="$($TMUX -L "$_bats_socket" display-message -p -t other '#{session_id}')"
  airline problem set "$session" cpu warn "sensors missing"
  airline problem set "$other" battery fail "battery unavailable"

  run airline problem show
  assert_success
  assert_output --partial "$session:"
  assert_output --partial "cpu"
  assert_output --partial "$other:"
  assert_output --partial "battery"
}

@test "lock diagnostics are empty normally and clear rejects a missing lock" {
  airline init
  session="$($TMUX -L "$_bats_socket" display-message -p '#{session_id}')"

  run airline lock show
  assert_success
  assert_output ""

  run airline lock clear session "$session" problem
  assert_failure
  assert_output --partial "no such outstanding transaction"
}

# --- transient (consume-on-view) --------------------------------------------

@test "a --transient signal arms the focus hook and clears on _unfocus" {
  airline init
  win="$($TMUX -L "$_bats_socket" display-message -p '#{window_id}')"
  airline status set build active                 # persistent
  airline status set review attention --transient # transient
  run get_option focus-events
  assert_output "on"
  airline _unfocus "$win"
  run wopt @airline--badge-status
  assert_output "active"             # transient 'review' gone, persistent 'build' remains
}

# --- state (active/suspended) -----------------------------------------------

@test "state suspend traps the prefix; resume restores; show reads the state" {
  airline init
  run airline state show
  assert_output "active"            # default
  airline state suspend
  run sopt prefix
  assert_output "None"              # prefix trapped
  run airline state show
  assert_output "suspended"
  airline state resume
  run sopt prefix
  refute_output "None"              # released → back to default
  run airline state show
  assert_output "active"
}

@test "state toggle flips between active and suspended" {
  airline init
  airline state toggle
  run airline state show
  assert_output "suspended"
  airline state toggle
  run airline state show
  assert_output "active"
}

@test "palette show name reads the active palette via the API (not a private option)" {
  airline init
  airline palette use light
  run airline palette show name
  assert_output "light"
}

@test "layout show: bare summarizes, name/path give raw fields" {
  airline init
  airline layout use default
  run airline layout show name
  assert_output "default"                 # raw, script-safe
  run airline layout show path
  assert_output --partial "/layouts/default"
  run airline layout show
  assert_output --partial "name"          # bare = labeled summary
  assert_output --partial "path"
}

# --- help -------------------------------------------------------------------

@test "help is self-documenting: extracted verbs, iterate + recurse into nouns" {
  run airline help
  assert_success
  assert_output --partial "init"                    # a top-level command (from the dispatcher)
  assert_output --partial "palette:"                # recursed into a noun
  assert_output --partial "[name|<element>]"         # a verb's extracted #| help
  refute_output --partial "#|"                      # the marker itself is stripped
}

@test "<noun> help prints just that noun" {
  run airline palette help
  assert_success
  assert_output --partial "palette:"
  assert_output --partial "register"
  refute_output --partial "segment:"                # scoped to the one noun
}
