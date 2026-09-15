#!/usr/bin/env bats

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load

PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

@test "committed completions are generated from the current grammar" {
  output_dir="$BATS_TEST_TMPDIR/generated"
  run bash "$PROJECT_ROOT/scripts/generate-completions" "$output_dir"
  assert_success
  run cmp "$PROJECT_ROOT/completions/airline.bash" "$output_dir/airline.bash"
  assert_success
  run cmp "$PROJECT_ROOT/completions/_airline" "$output_dir/_airline"
  assert_success
}

@test "compiled grammar emits one well-formed record per command path" {
  local grammar
  grammar="$(env AIRLINE_DIR="$PROJECT_ROOT" "$PROJECT_ROOT/airline.sh" help _grammar)"

  # Every record is path<TAB>usage<TAB>description with all three fields present.
  run awk -F'\t' 'NF != 3 || $1 == "" || $2 == "" || $3 == "" { bad++ } END { print bad + 0 }' \
    <<< "$grammar"
  assert_output 0

  run grep -Fx 'version	@none	Show the Airline release/API version' <<< "$grammar"
  assert_success
  run grep -Fx 'palette use	<palette>	Load a complete palette and publish the session palette' <<< "$grammar"
  assert_success
  run grep -Fx 'session	@none	session commands' <<< "$grammar"
  assert_success
}

@test "compiled grammar is independent of human help formatting" {
  # The completion compiler reads the `#| …` annotations, never rendered prose.
  # Perturbing wrap width, group headings, and indentation must not move it.
  work="$BATS_TEST_TMPDIR/reformatted"
  cp -R "$PROJECT_ROOT" "$work"
  sed -i 's/> 80 ))/> 48 ))/; s/%s commands:\\n/== %s ==\\n/' "$work/lib/help.sh"

  run env AIRLINE_DIR="$work" "$work/airline.sh" help
  assert_success
  refute_line --partial 'Session commands:'   # formatting really did change

  baseline="$(env AIRLINE_DIR="$PROJECT_ROOT" "$PROJECT_ROOT/airline.sh" help _grammar)"
  run env AIRLINE_DIR="$work" "$work/airline.sh" help _grammar
  assert_success
  assert_equal "$output" "$baseline"
}

@test "bash completion follows commands, canonical help, and typed enums" {
  # shellcheck source=/dev/null
  source "$PROJECT_ROOT/completions/airline.bash"

  COMP_WORDS=(airline pal); COMP_CWORD=1; _airline_completion
  assert_equal "${COMPREPLY[*]}" palette

  COMP_WORDS=(airline sta); COMP_CWORD=1; _airline_completion
  assert_equal "${COMPREPLY[*]}" status

  COMP_WORDS=(airline session ""); COMP_CWORD=2; _airline_completion
  assert_equal "${COMPREPLY[*]}" "init apply show suspend resume toggle"

  COMP_WORDS=(airline help palette ""); COMP_CWORD=3; _airline_completion
  assert_equal "${COMPREPLY[*]}" "describe show use load list register"

  COMP_WORDS=(airline health set runner build ""); COMP_CWORD=5; _airline_completion
  assert_equal "${COMPREPLY[*]}" "ok warn fail"

  COMP_WORDS=(airline status ""); COMP_CWORD=2; _airline_completion
  assert_equal "${COMPREPLY[*]}" "set clear show"

  COMP_WORDS=(airline runner run --); COMP_CWORD=3; _airline_completion
  assert_equal "${COMPREPLY[*]}" "--pane --window --interval --probe --classify --filter --merge-stderr --"
}

@test "bash completion resolves typed and contextual values through the airline CLI" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/usr/bin/env bash\ncase "$1 $2" in\n  "palette list") printf "dark\\nlight\\n" ;;\n  "widget list") printf "battery\\ncpu\\n" ;;\n  "problem show") printf "example      build  active  warn\\nexample      deploy  active  fail\\n" ;;\nesac\n' \
    > "$BATS_TEST_TMPDIR/bin/airline"
  printf '#!/usr/bin/env bash\n[[ "$1" == --fixture ]] && shift\ncase "$1" in\n  list-panes) printf "%%%%2\\n%%%%3\\n" ;;\n  list-sessions) printf "\\$1\\n\\$2\\n" ;;\nesac\n' \
    > "$BATS_TEST_TMPDIR/bin/tmux"
  chmod +x "$BATS_TEST_TMPDIR/bin/airline"
  chmod +x "$BATS_TEST_TMPDIR/bin/tmux"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  # shellcheck source=/dev/null
  source "$PROJECT_ROOT/completions/airline.bash"

  COMP_WORDS=(airline palette use l); COMP_CWORD=3; _airline_completion
  assert_equal "${COMPREPLY[*]}" light

  COMP_WORDS=(airline widget describe c); COMP_CWORD=3; _airline_completion
  assert_equal "${COMPREPLY[*]}" cpu

  COMP_WORDS=(airline problem clear example d); COMP_CWORD=4; _airline_completion
  assert_equal "${COMPREPLY[*]}" deploy

  COMP_WORDS=(airline problem set -t %3 ""); COMP_CWORD=5; _airline_completion
  assert_equal "${COMPREPLY[*]}" example

  COMP_WORDS=(airline problem set -t '%'); COMP_CWORD=4; _airline_completion
  assert_equal "${COMPREPLY[*]}" '%2 %3'
  COMP_WORDS=(airline problem close -t '%'); COMP_CWORD=4; _airline_completion
  assert_equal "${COMPREPLY[*]}" '%2 %3'

  COMP_WORDS=(airline problem set -t %3 example build w); COMP_CWORD=7; _airline_completion
  assert_equal "${COMPREPLY[*]}" warn

  COMP_WORDS=(airline problem close --session '$'); COMP_CWORD=4; _airline_completion
  assert_equal "${COMPREPLY[*]}" '$1 $2'

  COMP_WORDS=(airline status set -t '%'); COMP_CWORD=4; _airline_completion
  assert_equal "${COMPREPLY[*]}" '%2 %3'

  AIRLINE_TMUX="$BATS_TEST_TMPDIR/bin/tmux --fixture"
  COMP_WORDS=(airline status set -t '%'); COMP_CWORD=4; _airline_completion
  assert_equal "${COMPREPLY[*]}" '%2 %3'
  unset AIRLINE_TMUX

  COMP_WORDS=(airline transaction clear global server p); COMP_CWORD=5; _airline_completion
  assert_equal "${COMPREPLY[*]}" problem
}

@test "generated zsh completion parses when zsh is installed" {
  command -v zsh >/dev/null || skip "zsh is not installed"
  run zsh -n "$PROJECT_ROOT/completions/_airline"
  assert_success
}

@test "catalog help and bash completions distinguish describe from state show" {
  source "$PROJECT_ROOT/completions/airline.bash"
  local noun
  for noun in palette widget layout classifier filter probe runner; do
    run env AIRLINE_DIR="$PROJECT_ROOT" "$PROJECT_ROOT/airline.sh" help "$noun"
    assert_success
    assert_output --partial 'describe'
    if [[ "$noun" != palette && "$noun" != layout ]]; then
      refute_output --regexp '(^|[[:space:]])show([[:space:]]|$)'
    fi

    COMP_WORDS=(airline "$noun" de); COMP_CWORD=2; _airline_completion
    assert_equal "${COMPREPLY[*]}" describe
    COMP_WORDS=(airline "$noun" sh); COMP_CWORD=2; _airline_completion || true
    if [[ "$noun" == palette || "$noun" == layout ]]; then
      assert_equal "${COMPREPLY[*]}" show
    else
      assert_equal "${COMPREPLY[*]}" ''
    fi
  done
}

@test "bash describe completion resolves all seven catalog kinds" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/airline" <<'CLI'
#!/usr/bin/env bash
[[ "$2" == list ]] && printf '%s-sample\n' "$1"
CLI
  chmod +x "$BATS_TEST_TMPDIR/bin/airline"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  source "$PROJECT_ROOT/completions/airline.bash"
  local noun
  for noun in palette widget layout classifier filter probe runner; do
    COMP_WORDS=(airline "$noun" describe "$noun-"); COMP_CWORD=3; _airline_completion
    assert_equal "${COMPREPLY[*]}" "$noun-sample"
  done
}

@test "zsh describe completion resolves all seven catalog kinds" {
  command -v zsh >/dev/null || skip "zsh is not installed"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/airline" <<'CLI'
#!/usr/bin/env bash
[[ "$2" == list ]] && printf '%s-sample\n' "$1"
CLI
  chmod +x "$BATS_TEST_TMPDIR/bin/airline"
  local noun
  for noun in palette widget layout classifier filter probe runner; do
    run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" zsh -f -c '
      compdef() { :; }
      compadd() { print -rl -- "$@"; }
      source "$1"
      words=(airline "$2" describe "")
      CURRENT=4
      _airline_zsh
    ' zsh "$PROJECT_ROOT/completions/_airline" "$noun"
    assert_success
    assert_output "$noun-sample"
  done
}

@test "bash runner completion offers reserved options after each element's arguments" {
  source "$PROJECT_ROOT/completions/airline.bash"
  local kind
  for kind in --classify --filter --probe; do
    COMP_WORDS=(airline runner run "$kind" custom 'one two' --m)
    COMP_CWORD=6; _airline_completion
    assert_equal "${COMPREPLY[*]}" --merge-stderr
  done
  COMP_WORDS=(airline runner watch --probe custom endpoint --i)
  COMP_CWORD=6; _airline_completion
  assert_equal "${COMPREPLY[*]}" --interval
}

@test "zsh runner completion offers reserved options after probe arguments" {
  command -v zsh >/dev/null || skip "zsh is not installed"
  run zsh -f -c '
    compdef() { :; }
    compadd() { print -rl -- "$@"; }
    source "$1"
    words=(airline runner run --probe custom endpoint --m)
    CURRENT=7 PREFIX=--m
    _airline_zsh
  ' zsh "$PROJECT_ROOT/completions/_airline"
  assert_success
  assert_line --merge-stderr
  assert_line --filter
}
