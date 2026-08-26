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
