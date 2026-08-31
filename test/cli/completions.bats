#!/usr/bin/env bats

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load

PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

@test "committed completions are generated from current rendered help" {
  output_dir="$BATS_TEST_TMPDIR/generated"
  run bash "$PROJECT_ROOT/scripts/generate-completions" "$output_dir"
  assert_success
  run cmp "$PROJECT_ROOT/completions/airline.bash" "$output_dir/airline.bash"
  assert_success
  run cmp "$PROJECT_ROOT/completions/_airline" "$output_dir/_airline"
  assert_success
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
  assert_equal "${COMPREPLY[*]}" "show use list register"

  COMP_WORDS=(airline health set runner build ""); COMP_CWORD=5; _airline_completion
  assert_equal "${COMPREPLY[*]}" "ok warn fail"
}

@test "bash completion resolves typed and contextual values through the airline CLI" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/usr/bin/env bash\ncase "$1 $2" in\n  "palette list") printf "dark\\nlight\\n" ;;\n  "adapter list") printf "battery\\ncpu\\n" ;;\n  "problem show") printf "example      build  active  warn\\nexample      deploy  active  fail\\n" ;;\nesac\n' \
    > "$BATS_TEST_TMPDIR/bin/airline"
  printf '#!/usr/bin/env bash\ncase "$1" in\n  list-panes) printf "%%2\\n%%3\\n" ;;\n  list-sessions) printf "\\$1\\n\\$2\\n" ;;\nesac\n' \
    > "$BATS_TEST_TMPDIR/bin/tmux"
  chmod +x "$BATS_TEST_TMPDIR/bin/airline"
  chmod +x "$BATS_TEST_TMPDIR/bin/tmux"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  # shellcheck source=/dev/null
  source "$PROJECT_ROOT/completions/airline.bash"

  COMP_WORDS=(airline palette use l); COMP_CWORD=3; _airline_completion
  assert_equal "${COMPREPLY[*]}" light

  COMP_WORDS=(airline adapter use battery c); COMP_CWORD=4; _airline_completion
  assert_equal "${COMPREPLY[*]}" cpu

  COMP_WORDS=(airline problem clear example d); COMP_CWORD=4; _airline_completion
  assert_equal "${COMPREPLY[*]}" deploy

  COMP_WORDS=(airline problem set --pane %3 ""); COMP_CWORD=5; _airline_completion
  assert_equal "${COMPREPLY[*]}" example

  COMP_WORDS=(airline problem set --pane %3 example build w); COMP_CWORD=7; _airline_completion
  assert_equal "${COMPREPLY[*]}" warn

  COMP_WORDS=(airline problem close --session '$'); COMP_CWORD=4; _airline_completion
  assert_equal "${COMPREPLY[*]}" '$1 $2'

  COMP_WORDS=(airline transaction clear global server p); COMP_CWORD=5; _airline_completion
  assert_equal "${COMPREPLY[*]}" problem
}

@test "generated zsh completion parses when zsh is installed" {
  command -v zsh >/dev/null || skip "zsh is not installed"
  run zsh -n "$PROJECT_ROOT/completions/_airline"
  assert_success
}
