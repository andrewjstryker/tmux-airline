#!/usr/bin/env bats

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load
load ../support/helper

setup() {
  load_collections
  source "$PROJECT_ROOT/lib/catalog.sh"
  mkdir -p "$BATS_TEST_TMPDIR/builtin" "$BATS_TEST_TMPDIR/user"
  printf 'builtin\n' > "$BATS_TEST_TMPDIR/builtin/shared"
  printf 'builtin\n' > "$BATS_TEST_TMPDIR/builtin/z-builtin"
  printf 'user\n' > "$BATS_TEST_TMPDIR/user/shared"
  printf 'user\n' > "$BATS_TEST_TMPDIR/user/a-user"
}

@test "builtin paths append while user registration prepends" {
  catalog_register_builtin s1 palette "$BATS_TEST_TMPDIR/builtin"
  catalog_register s1 palette "$BATS_TEST_TMPDIR/user"

  run catalog_paths s1 palette
  assert_output "$BATS_TEST_TMPDIR/user $BATS_TEST_TMPDIR/builtin"
}

@test "resolution honors path priority and accepts only bare names" {
  catalog_register_builtin s1 palette "$BATS_TEST_TMPDIR/builtin"
  catalog_register s1 palette "$BATS_TEST_TMPDIR/user"

  run catalog_resolve s1 palette shared
  assert_output "$BATS_TEST_TMPDIR/user/shared"
  run catalog_resolve s1 palette nested/shared
  assert_output ""
}

@test "list deduplicates shadowed names in priority order" {
  catalog_register_builtin s1 palette "$BATS_TEST_TMPDIR/builtin"
  catalog_register s1 palette "$BATS_TEST_TMPDIR/user"

  run catalog_list s1 palette
  assert_output $'a-user\nshared\nz-builtin'
}

@test "builtin registration ignores a missing optional directory" {
  catalog_register_builtin s1 probe "$BATS_TEST_TMPDIR/missing"
  run catalog_paths s1 probe
  assert_output ""
}

@test "user registration validates exactly one existing directory" {
  run catalog_register s1 palette
  assert_failure 2
  assert_output "airline: palette register: need exactly one <dir>"

  run catalog_register s1 palette "$BATS_TEST_TMPDIR/missing"
  assert_failure 2
  assert_output --partial "no such directory"

  run catalog_register s1 palette "$BATS_TEST_TMPDIR/user" extra
  assert_failure 2
  assert_output "airline: palette register: need exactly one <dir>"
}

@test "metadata is read from marked header comments without executing the file" {
  cat > "$BATS_TEST_TMPDIR/element" <<'ELEMENT'
#!/usr/bin/env bash
#| summary: Check one or more HTTP endpoints
#| usage: <endpoint> [<endpoint>...]
#| interval: 5

printf 'EXECUTED\n'
touch "$BATS_TEST_TMPDIR/side-effect"
ELEMENT

  run catalog_metadata "$BATS_TEST_TMPDIR/element"
  assert_success
  assert_line --index 0 "summary	Check one or more HTTP endpoints"
  assert_line --index 1 "usage	<endpoint> [<endpoint>...]"
  assert_line --index 2 "interval	5"
  refute_output --partial EXECUTED
  [ ! -e "$BATS_TEST_TMPDIR/side-effect" ]

  run catalog_metadata "$BATS_TEST_TMPDIR/element" summary
  assert_output "Check one or more HTTP endpoints"
}

@test "metadata distinguishes an empty field from an absent one" {
  printf '#| summary: has one\n#| usage:\n' > "$BATS_TEST_TMPDIR/element"

  run catalog_metadata "$BATS_TEST_TMPDIR/element" usage
  assert_success
  assert_output ""

  run catalog_metadata "$BATS_TEST_TMPDIR/element" interval
  assert_failure
}

@test "metadata scanning stops at the first line of code" {
  cat > "$BATS_TEST_TMPDIR/element" <<'ELEMENT'
#| summary: declared in the header
opt_set_session "$AIRLINE_SESSION" @cpu_low_fg_color red
#| summary: smuggled in below the code
ELEMENT

  run catalog_metadata "$BATS_TEST_TMPDIR/element"
  assert_success
  assert_output "summary	declared in the header"
}

@test "metadata rejects malformed markers and repeated keys" {
  printf '#| summary no colon\n' > "$BATS_TEST_TMPDIR/bad-marker"
  run catalog_metadata "$BATS_TEST_TMPDIR/bad-marker"
  assert_failure
  assert_output --partial "malformed marker"

  printf '#| summary: one\n#| summary: two\n' > "$BATS_TEST_TMPDIR/duplicate"
  run catalog_metadata "$BATS_TEST_TMPDIR/duplicate"
  assert_failure
  assert_output --partial "duplicate 'summary'"

  run catalog_metadata "$BATS_TEST_TMPDIR/absent-file"
  assert_failure
  assert_output --partial "no such file"
}

@test "metadata reads the shipped side-effecting element kinds" {
  # Adapters and palettes cannot be sourced for inspection: doing so applies them.
  run catalog_metadata "$PROJECT_ROOT/layouts/adapters/cpu" summary
  assert_success
  refute_output ""

  run catalog_metadata "$PROJECT_ROOT/layouts/palettes/dark" summary
  assert_success
  refute_output ""
}

@test "all shipped catalog kinds satisfy the same header metadata contract" {
  local directory file
  for directory in layouts/palettes layouts/adapters layouts/definitions \
    runners/classifiers runners/filters runners/probes runners/definitions; do
    for file in "$PROJECT_ROOT/$directory/"*; do
      run catalog_metadata_valid "$file"
      assert_success "$file"
    done
  done
}

@test "description validates common metadata consistently across catalog kinds" {
  local kind content
  for content in '# ordinary comment' '#| summary:' '#| summary:   ' \
    $'#| summary: first\n#| summary: second' '#| bad marker'; do
    printf '%s\n' "$content" > "$BATS_TEST_TMPDIR/user/invalid"
    for kind in palette adapter layout classifier filter probe runner; do
      catalog_register s1 "$kind" "$BATS_TEST_TMPDIR/user"
      run catalog_describe_resolve s1 "$kind" invalid
      assert_failure
      assert_output --partial "$kind describe: 'invalid' has invalid metadata"
    done
  done
}

@test "description uses the winning catalog file and renders declared usage" {
  printf '%s\n' '#| summary: builtin summary' > "$BATS_TEST_TMPDIR/builtin/shared"
  printf '%s\n' '#| summary: user summary' '#| usage: <argument>' \
    'exit 99' > "$BATS_TEST_TMPDIR/user/shared"
  catalog_register_builtin s1 classifier "$BATS_TEST_TMPDIR/builtin"
  catalog_register s1 classifier "$BATS_TEST_TMPDIR/user"
  local file
  file="$(catalog_describe_resolve s1 classifier shared)"
  run catalog_describe_render shared "$file"
  assert_success
  assert_output --partial 'user summary'
  assert_output --partial '<argument>'
  assert_output --partial "$BATS_TEST_TMPDIR/user/shared"
  refute_output --partial 'builtin summary'

  printf '%s\n' '#| summary: no arguments' '#| usage:' > "$file"
  run catalog_describe_render shared "$file"
  assert_success
  assert_output --partial 'arguments    none'
}

@test "option documentation reads dashed arms and alternations without executing code" {
  cat > "$BATS_TEST_TMPDIR/options" <<'ELEMENT'
#| summary: Documented options
#| usage: [--timeout <seconds>]
exit 99
outside() {
  case "$1" in
    --hidden) : ;; #| — outside the documented region
  esac
}
private_parse_helper()
{
  # options:begin
  case "$1" in
    --timeout|-t) : ;; #| <seconds> — request budget
    ( --expect | -e ) : ;; #| <pattern> — expected result
    --quiet) : ;; #| — silence normal output
    *) : ;;
  esac
  # options:end
}
ELEMENT
  run catalog_options "$BATS_TEST_TMPDIR/options"
  assert_success
  assert_output $'--timeout|-t\t<seconds> — request budget\n--expect | -e\t<pattern> — expected result\n--quiet\t— silence normal output'
  run catalog_describe_render options "$BATS_TEST_TMPDIR/options"
  assert_success
  assert_output --partial 'options:'
  assert_output --partial '--timeout|-t <seconds> — request budget'
  refute_output --partial '--hidden'
}

@test "option documentation is optional but malformed section boundaries fail" {
  local content
  printf '%s\n' '#| summary: No options' > "$BATS_TEST_TMPDIR/options"
  run catalog_options "$BATS_TEST_TMPDIR/options"
  assert_success
  assert_output ''
  for content in '# options:begin' '# options:end' \
    $'# options:begin\n# options:begin\n# options:end' \
    $'# options:begin\n# options:end\n# options:begin\n# options:end'; do
    printf '%s\n' '#| summary: Invalid documentation' "$content" > "$BATS_TEST_TMPDIR/options"
    run catalog_describe_render options "$BATS_TEST_TMPDIR/options"
    assert_failure
    assert_output --partial 'airline: options:'
    refute_output --partial 'summary      Invalid documentation'
  done
}
