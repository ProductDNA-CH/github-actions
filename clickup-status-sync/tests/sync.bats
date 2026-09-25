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

# --- e2e: PR body drives the status update ---

@test "e2e: release PR to main with body list -> demo done per ticket" {
  body=$'### Click Up Tasks\n- CORE-6231\n- CORE-6258\n- CORE-6261\n\n## Describe your changes'
  run env DRY_RUN=1 EVENT_NAME=pull_request PR_ACTION=opened \
      PR_BASE_REF=main PR_HEAD_REF=release/sprint-20 \
      DEV_BRANCH=develop PROD_BRANCH=main ID_PREFIX=CORE PR_BODY="$body" \
      "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WOULD update CORE-6231 -> demo done"* ]]
  [[ "$output" == *"WOULD update CORE-6258 -> demo done"* ]]
  [[ "$output" == *"WOULD update CORE-6261 -> demo done"* ]]
}

@test "e2e: PR opened to develop with id in branch, no body section -> in review (unchanged)" {
  run env DRY_RUN=1 EVENT_NAME=pull_request PR_ACTION=opened \
      PR_BASE_REF=develop PR_HEAD_REF=feat/CORE-100-x \
      DEV_BRANCH=develop PROD_BRANCH=main ID_PREFIX=CORE \
      PR_BODY=$'## Describe your changes\nnothing here' \
      "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WOULD update CORE-100 -> in review"* ]]
}

@test "e2e: a CORE id present only in free-text prose is not updated" {
  run env DRY_RUN=1 EVENT_NAME=pull_request PR_ACTION=opened \
      PR_BASE_REF=main PR_HEAD_REF=release/sprint-21 \
      DEV_BRANCH=develop PROD_BRANCH=main ID_PREFIX=CORE \
      PR_BODY=$'## Describe your changes\nthis reverts CORE-9999' \
      "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"WOULD update CORE-9999"* ]]
}

# --- release PRs: ids from the commits, updated release branches ---

@test "PR synchronize to main -> demo done" {
  rs EVENT_NAME=pull_request PR_ACTION=synchronize PR_BASE_REF=main DEV_BRANCH=develop PROD_BRANCH=main
  [ "$output" = "demo done" ]
}
@test "PR synchronize to develop -> no-op" {
  rs EVENT_NAME=pull_request PR_ACTION=synchronize PR_BASE_REF=develop DEV_BRANCH=develop PROD_BRANCH=main
  [ -z "$output" ]
}

@test "resolve_ids reads the commits of a PR to main, even with an empty body" {
  run env EVENT_NAME=pull_request PR_BASE_REF=main PROD_BRANCH=main PR_HEAD_REF=release/sprint-23 ID_PREFIX=CORE PR_BODY="" \
    bash -c 'source "'"$SCRIPT"'" 2>/dev/null
             commit_messages() { printf "%s\n" "feat: [CORE-7374] project data tab" "fix: CORE-7568 qty" "chore: no id"; }
             resolve_ids'
  printf '%s\n' "$output" | grep -qx "CORE-7374"
  printf '%s\n' "$output" | grep -qx "CORE-7568"
  [ "$(printf '%s\n' "$output" | grep -c 'CORE-')" -eq 2 ]
}

@test "resolve_ids does not read commits for a PR to develop" {
  run env EVENT_NAME=pull_request PR_BASE_REF=develop PROD_BRANCH=main PR_HEAD_REF=feat/CORE-1-x ID_PREFIX=CORE \
    bash -c 'source "'"$SCRIPT"'" 2>/dev/null
             commit_messages() { echo "CORE-999"; }
             resolve_ids'
  [ "$output" = "CORE-1" ]
}

@test "commit_messages warns and prints nothing without a token" {
  run env GITHUB_TOKEN= REPO=o/r PR_BASE_SHA=a PR_HEAD_SHA=b \
    bash -c 'source "'"$SCRIPT"'" 2>/dev/null; commit_messages'
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::"* ]]
  [[ "$output" != *"CORE-"* ]]
}

@test "commit_messages pages through the compare endpoint past 250 commits" {
  run env GITHUB_TOKEN=t REPO=o/r PR_BASE_SHA=a PR_HEAD_SHA=b \
    bash -c 'source "'"$SCRIPT"'" 2>/dev/null
             curl() { # 3 full pages then a partial one: 377 commits
               local url="${@: -1}" page; page="${url##*page=}"
               local n=100; [ "$page" = 4 ] && n=77
               jq -n --argjson n "$n" --arg p "$page" "{commits: [range(\$n) | {commit: {message: \"CORE-\(\$p)\(.)\"}}]}"
             }
             commit_messages | wc -l'
  [ "$(echo "$output" | tr -d ' ')" = "377" ]
}

# --- never move a task back along the pipeline ---

@test "is_regression: shipped -> dev done is a regression" {
  run bash -c 'source "'"$SCRIPT"'" 2>/dev/null; is_regression "shipped" "dev done"'
  [ "$status" -eq 0 ]
}
@test "is_regression: dev done -> shipped is not" {
  run bash -c 'source "'"$SCRIPT"'" 2>/dev/null; is_regression "dev done" "shipped"'
  [ "$status" -ne 0 ]
}
@test "is_regression: compares status names case-insensitively" {
  run bash -c 'source "'"$SCRIPT"'" 2>/dev/null; is_regression "Demo Done" "in review"'
  [ "$status" -eq 0 ]
}
@test "is_regression: a status outside the pipeline never blocks" {
  run bash -c 'source "'"$SCRIPT"'" 2>/dev/null; is_regression "not started" "in development"'
  [ "$status" -ne 0 ]
}

@test "update_task keeps a shipped task out of dev done" {
  run env DRY_RUN=1 bash -c 'source "'"$SCRIPT"'" 2>/dev/null
                             fetch_status() { echo "shipped"; }
                             update_task CORE-7568 "dev done"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"kept CORE-7568 at 'shipped'"* ]]
  [[ "$output" != *"WOULD update"* ]]
}

@test "update_task moves a dev done task forward to shipped" {
  run env DRY_RUN=1 bash -c 'source "'"$SCRIPT"'" 2>/dev/null
                             fetch_status() { echo "dev done"; }
                             update_task CORE-7374 "shipped"'
  [[ "$output" == *"WOULD update CORE-7374 -> shipped"* ]]
}

@test "update_task still updates when the current status cannot be read" {
  run env DRY_RUN=1 bash -c 'source "'"$SCRIPT"'" 2>/dev/null
                             fetch_status() { :; }
                             update_task CORE-1 "in review"'
  [[ "$output" == *"WOULD update CORE-1 -> in review"* ]]
}
