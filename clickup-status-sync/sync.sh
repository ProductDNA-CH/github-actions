#!/usr/bin/env bash
# clickup-status-sync core logic. Reads env vars; its only GitHub API call lists
# the commits of a PR to the prod branch. Always exits 0 — never blocks a workflow.
set -uo pipefail

# --- Inputs (with defaults) ---
CLICKUP_TOKEN="${CLICKUP_TOKEN:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
GITHUB_API_URL="${GITHUB_API_URL:-https://api.github.com}"
REPO="${REPO:-}"
DEV_BRANCH="${DEV_BRANCH:-develop}"
PROD_BRANCH="${PROD_BRANCH:-main}"
ID_PREFIX="${ID_PREFIX:-CORE}"
CLICKUP_TEAM_ID="${CLICKUP_TEAM_ID:-90151502952}"
STATUS_IN_DEV="${STATUS_IN_DEV:-in development}"
STATUS_IN_REVIEW="${STATUS_IN_REVIEW:-in review}"
STATUS_DEV_DONE="${STATUS_DEV_DONE:-dev done}"
STATUS_DEMO_DONE="${STATUS_DEMO_DONE:-demo done}"
STATUS_SHIPPED="${STATUS_SHIPPED:-shipped}"
DRY_RUN="${DRY_RUN:-0}"

# --- GitHub event context (mapped by action.yaml) ---
EVENT_NAME="${EVENT_NAME:-}"
REF_TYPE="${REF_TYPE:-}"
CREATED_REF="${CREATED_REF:-}"
PR_ACTION="${PR_ACTION:-}"
PR_MERGED="${PR_MERGED:-}"
PR_HEAD_REF="${PR_HEAD_REF:-}"
PR_BASE_REF="${PR_BASE_REF:-}"
PR_BASE_SHA="${PR_BASE_SHA:-}"
PR_HEAD_SHA="${PR_HEAD_SHA:-}"
PR_BODY="${PR_BODY:-}"

# The forward order of the pipeline; the sync never moves a task back along it.
STATUS_ORDER=("$STATUS_IN_DEV" "$STATUS_IN_REVIEW" "$STATUS_DEV_DONE" "$STATUS_DEMO_DONE" "$STATUS_SHIPPED")

note() { echo "::notice::$*"; }
warn() { echo "::warning::$*"; }

# Print unique task IDs (one per line) found in $1.
extract_ids() {
  local text="$1"
  grep -oE "${ID_PREFIX}-[0-9]+" <<<"$text" | awk '!seen[$0]++'
}

# Print the branch ref carrying the task id, depending on the event.
resolve_ref() {
  case "$EVENT_NAME" in
    create)       printf '%s' "$CREATED_REF" ;;
    pull_request) printf '%s' "$PR_HEAD_REF" ;;
  esac
}

# Print only the auto-generated ClickUp task-list slice of a PR body.
# Prefer the HTML-marker block; else the "### Click Up Tasks" heading section,
# bounded by the next Markdown heading, so free-text prose is never scanned.
clickup_section() {
  local body="$1" block
  block=$(awk '
    /beginning of the Click Up tasks list/ {g=1; next}
    /end of the Click Up tasks list/       {g=0}
    g' <<<"$body")
  [[ -n "$block" ]] && { printf '%s' "$block"; return; }
  awk '
    /^#+[[:space:]]*Click ?Up Tasks/ {g=1; next}
    g && /^#/ {g=0}
    g' <<<"$body"
}

# Print the message of every commit between the PR's base and head.
# Uses the compare endpoint, paginated: the PR commits endpoint stops at 250
# commits, and so does compare when it is not paginated.
commit_messages() {
  if [[ -z "$GITHUB_TOKEN" || -z "$REPO" || -z "$PR_BASE_SHA" || -z "$PR_HEAD_SHA" ]]; then
    warn "cannot list the PR's commits: github token, repository or base/head sha missing"
    return 0
  fi
  local page=1 resp count
  while (( page <= 100 )); do
    resp=$(curl -sS -f \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      "${GITHUB_API_URL}/repos/${REPO}/compare/${PR_BASE_SHA}...${PR_HEAD_SHA}?per_page=100&page=${page}") \
      || { warn "GitHub compare failed on page ${page}"; return 0; }
    jq -r '.commits[].commit.message' <<<"$resp"
    count=$(jq '.commits | length' <<<"$resp" 2>/dev/null)
    count="${count:-0}"
    (( count < 100 )) && return 0
    page=$((page + 1))
  done
}

# Union of task IDs from the head-branch ref, (for PRs) the task-list section and
# (for PRs to the prod branch) the commits themselves: the task-list section is
# written by a sibling workflow that races this one when the PR opens.
resolve_ids() {
  local ref_ids body_ids="" commit_ids=""
  ref_ids="$(extract_ids "$(resolve_ref)")"
  if [[ "$EVENT_NAME" == "pull_request" ]]; then
    body_ids="$(extract_ids "$(clickup_section "$PR_BODY")")"
    [[ "$PR_BASE_REF" == "$PROD_BRANCH" ]] && commit_ids="$(extract_ids "$(commit_messages)")"
  fi
  printf '%s\n%s\n%s\n' "$ref_ids" "$body_ids" "$commit_ids" | awk 'NF && !seen[$0]++'
}

# Print the position of status $1 in STATUS_ORDER (case-insensitive), or -1.
status_rank() {
  local wanted i
  wanted="$(tr '[:upper:]' '[:lower:]' <<<"$1")"
  for i in "${!STATUS_ORDER[@]}"; do
    [[ "$(tr '[:upper:]' '[:lower:]' <<<"${STATUS_ORDER[$i]}")" == "$wanted" ]] && { echo "$i"; return; }
  done
  echo -1
}

# True when moving from status $1 to status $2 goes back along the pipeline.
is_regression() {
  local current target
  current="$(status_rank "$1")"
  target="$(status_rank "$2")"
  (( current >= 0 && target >= 0 && current > target ))
}

# Print a task's current ClickUp status, or nothing if it cannot be read.
fetch_status() {
  local id="$1"
  [[ "$DRY_RUN" == "1" ]] && return 0
  curl -sS -f -H "Authorization: ${CLICKUP_TOKEN}" \
    "https://api.clickup.com/api/v2/task/${id}?custom_task_ids=true&team_id=${CLICKUP_TEAM_ID}" \
    | jq -r '.status.status // empty' 2>/dev/null || true
}

# Print the target ClickUp status for this event, or nothing for a no-op.
resolve_status() {
  case "$EVENT_NAME" in
    create)
      [[ "$REF_TYPE" == "branch" ]] && printf '%s' "$STATUS_IN_DEV"
      ;;
    pull_request)
      case "$PR_ACTION" in
        opened|reopened|ready_for_review)
          if   [[ "$PR_BASE_REF" == "$DEV_BRANCH"  ]]; then printf '%s' "$STATUS_IN_REVIEW"
          elif [[ "$PR_BASE_REF" == "$PROD_BRANCH" ]]; then printf '%s' "$STATUS_DEMO_DONE"
          fi
          ;;
        synchronize)
          [[ "$PR_BASE_REF" == "$PROD_BRANCH" ]] && printf '%s' "$STATUS_DEMO_DONE"
          ;;
        closed)
          [[ "$PR_MERGED" == "true" ]] || return 0
          if   [[ "$PR_BASE_REF" == "$DEV_BRANCH"  ]]; then printf '%s' "$STATUS_DEV_DONE"
          elif [[ "$PR_BASE_REF" == "$PROD_BRANCH" ]]; then printf '%s' "$STATUS_SHIPPED"
          fi
          ;;
      esac
      ;;
  esac
}

# Update a single ClickUp task's status, unless that would move it back along
# the pipeline. Honours DRY_RUN. Never aborts the run.
update_task() {
  local id="$1" status="$2" current
  current="$(fetch_status "$id")"
  if [[ -n "$current" ]] && is_regression "$current" "$status"; then
    note "kept ${id} at '${current}': '${status}' would move it back"
    return 0
  fi
  if [[ "$DRY_RUN" == "1" ]]; then
    note "WOULD update ${id} -> ${status}"
    return 0
  fi
  local code body
  body=$(curl -sS -w '\n%{http_code}' -X PUT \
    -H "Authorization: ${CLICKUP_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://api.clickup.com/api/v2/task/${id}?custom_task_ids=true&team_id=${CLICKUP_TEAM_ID}" \
    -d "{\"status\":\"${status}\"}") || { warn "curl failed for ${id}"; return 0; }
  code=$(tail -n1 <<<"$body")
  if [[ "$code" == "200" ]]; then
    note "updated ${id} -> ${status}"
  else
    warn "ClickUp API ${code} for ${id}: $(sed '$d' <<<"$body" | tr -d '\n' | cut -c1-200)"
  fi
}

main() {
  local status ids found=0
  status="$(resolve_status)"
  if [[ -z "$status" ]]; then
    note "no status transition for event=${EVENT_NAME} action=${PR_ACTION:-} base=${PR_BASE_REF:-}; nothing to do"
    return 0
  fi
  ids="$(resolve_ids)"
  if [[ -z "$ids" ]]; then
    warn "target status '${status}' but no ${ID_PREFIX}-NNN id found in branch '$(resolve_ref)' or PR body"
    return 0
  fi
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    update_task "$id" "$status"
    found=1
  done <<<"$ids"
  [[ "$found" == 1 ]] || warn "no task updated"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
  exit 0
fi
