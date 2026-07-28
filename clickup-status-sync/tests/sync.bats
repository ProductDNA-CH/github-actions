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

# --- Task 3: resolve_status / resolve_ref ---

rs() { # helper: run resolve_status with given env
  run env "$@" bash -c 'source "'"$SCRIPT"'" 2>/dev/null; resolve_status'
}

@test "create branch -> in development" {
  rs EVENT_NAME=create REF_TYPE=branch
  [ "$output" = "in development" ]
}
@test "create tag -> no-op (empty)" {
  rs EVENT_NAME=create REF_TYPE=tag
  [ -z "$output" ]
}
@test "PR opened to develop -> in review" {
  rs EVENT_NAME=pull_request PR_ACTION=opened PR_BASE_REF=develop DEV_BRANCH=develop PROD_BRANCH=main
  [ "$output" = "in review" ]
}
@test "PR ready_for_review to main -> demo done" {
  rs EVENT_NAME=pull_request PR_ACTION=ready_for_review PR_BASE_REF=main DEV_BRANCH=develop PROD_BRANCH=main
  [ "$output" = "demo done" ]
}
@test "PR merged to develop -> dev done" {
  rs EVENT_NAME=pull_request PR_ACTION=closed PR_MERGED=true PR_BASE_REF=develop DEV_BRANCH=develop PROD_BRANCH=main
  [ "$output" = "dev done" ]
}
@test "PR merged to main -> shipped" {
  rs EVENT_NAME=pull_request PR_ACTION=closed PR_MERGED=true PR_BASE_REF=main DEV_BRANCH=develop PROD_BRANCH=main
  [ "$output" = "shipped" ]
}
@test "PR closed unmerged -> no-op" {
  rs EVENT_NAME=pull_request PR_ACTION=closed PR_MERGED=false PR_BASE_REF=develop
  [ -z "$output" ]
}
@test "PR opened to unrelated base -> no-op" {
  rs EVENT_NAME=pull_request PR_ACTION=opened PR_BASE_REF=release/x DEV_BRANCH=develop PROD_BRANCH=main
  [ -z "$output" ]
}

@test "resolve_ref returns created ref for create" {
  run env EVENT_NAME=create CREATED_REF=feat/CORE-9 bash -c 'source "'"$SCRIPT"'" 2>/dev/null; resolve_ref'
  [ "$output" = "feat/CORE-9" ]
}
@test "resolve_ref returns head ref for PR" {
  run env EVENT_NAME=pull_request PR_HEAD_REF=fix/CORE-8 bash -c 'source "'"$SCRIPT"'" 2>/dev/null; resolve_ref'
  [ "$output" = "fix/CORE-8" ]
}

# --- Task 4: end-to-end (dry-run) ---

@test "e2e: PR opened to develop dry-runs the right calls" {
  run env DRY_RUN=1 EVENT_NAME=pull_request PR_ACTION=opened \
      PR_BASE_REF=develop PR_HEAD_REF=feat/CORE-100-x \
      DEV_BRANCH=develop PROD_BRANCH=main ID_PREFIX=CORE \
      "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WOULD update CORE-100 -> in review"* ]]
}

@test "e2e: no task id -> warning, exit 0" {
  run env DRY_RUN=1 EVENT_NAME=pull_request PR_ACTION=opened \
      PR_BASE_REF=develop PR_HEAD_REF=develop "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::"* ]]
  [[ "$output" == *"no "* ]]
}

@test "e2e: no-op event exits 0 quietly" {
  run env DRY_RUN=1 EVENT_NAME=pull_request PR_ACTION=closed \
      PR_MERGED=false PR_HEAD_REF=feat/CORE-1 "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"WOULD update"* ]]
}

# --- read PR body task-list section ---

@test "clickup_section extracts the task list from an HTML-marker block" {
  body=$'<!--- beginning of the Click Up tasks list -->\n### Click Up Tasks\n- CORE-1\n- CORE-2\n<!--- end of the Click Up tasks list -->\n## Describe your changes\nreverts CORE-999'
  run env ID_PREFIX=CORE PR_BODY="$body" \
    bash -c 'source "'"$SCRIPT"'" 2>/dev/null; extract_ids "$(clickup_section "$PR_BODY")"'
  printf '%s\n' "$output" | grep -qx "CORE-1"
  printf '%s\n' "$output" | grep -qx "CORE-2"
  [[ "$output" != *"CORE-999"* ]]
}

@test "clickup_section fallback reads the heading section and stops at the next heading" {
  body=$'### Click Up Tasks\n- CORE-6231\n- CORE-6258\n\n## Describe your changes\nreverts CORE-9999'
  run env ID_PREFIX=CORE PR_BODY="$body" \
    bash -c 'source "'"$SCRIPT"'" 2>/dev/null; extract_ids "$(clickup_section "$PR_BODY")"'
  printf '%s\n' "$output" | grep -qx "CORE-6231"
  printf '%s\n' "$output" | grep -qx "CORE-6258"
  [[ "$output" != *"CORE-9999"* ]]
}

@test "resolve_ids unions branch and body ids, deduped" {
  body=$'### Click Up Tasks\n- CORE-2\n- CORE-3'
  run env EVENT_NAME=pull_request PR_HEAD_REF=feat/CORE-1-x ID_PREFIX=CORE PR_BODY="$body" \
    bash -c 'source "'"$SCRIPT"'" 2>/dev/null; resolve_ids'
  printf '%s\n' "$output" | grep -qx "CORE-1"
  printf '%s\n' "$output" | grep -qx "CORE-2"
  printf '%s\n' "$output" | grep -qx "CORE-3"
  [ "$(printf '%s\n' "$output" | grep -c 'CORE-')" -eq 3 ]
}

@test "resolve_ids reads no body for a create event" {
  run env EVENT_NAME=create CREATED_REF=feat/CORE-5-x ID_PREFIX=CORE PR_BODY=$'### Click Up Tasks\n- CORE-77' \
    bash -c 'source "'"$SCRIPT"'" 2>/dev/null; resolve_ids'
  printf '%s\n' "$output" | grep -qx "CORE-5"
  [[ "$output" != *"CORE-77"* ]]
}
