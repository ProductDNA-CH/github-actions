#!/usr/bin/env bats
# Run: bats clickup-status-sync/tests/sync.bats
SCRIPT="${BATS_TEST_DIRNAME}/../sync.sh"

# --- Task 2: extract_ids ---

@test "extracts a single CORE id from a branch" {
  run env ID_PREFIX=CORE bash -c 'source "'"$SCRIPT"'" 2>/dev/null; extract_ids "feat/CORE-3470-fix-thing"'
  [ "$status" -eq 0 ]
  [ "$output" = "CORE-3470" ]
}

@test "extracts and dedupes multiple ids" {
  run env ID_PREFIX=CORE bash -c 'source "'"$SCRIPT"'" 2>/dev/null; extract_ids "CORE-1_CORE-2_CORE-1"'
  printf '%s\n' "$output" | grep -qx "CORE-1"
  printf '%s\n' "$output" | grep -qx "CORE-2"
  [ "$(printf '%s\n' "$output" | grep -c CORE-1)" -eq 1 ]
}

@test "returns nothing when no id present" {
  run env ID_PREFIX=CORE bash -c 'source "'"$SCRIPT"'" 2>/dev/null; extract_ids "develop"'
  [ -z "$output" ]
}
