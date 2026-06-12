#!/usr/bin/env bash
# clickup-status-sync core logic. Pure: reads env vars, no GitHub API calls.
# Always exits 0 — never blocks a workflow.
set -uo pipefail

# --- Inputs (with defaults) ---
CLICKUP_TOKEN="${CLICKUP_TOKEN:-}"
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

note() { echo "::notice::$*"; }
warn() { echo "::warning::$*"; }

# Functions filled in T2/T3/T4.
main() { :; }

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
  exit 0
fi
