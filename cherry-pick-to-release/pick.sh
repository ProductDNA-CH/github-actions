#!/usr/bin/env bash
# cherry-pick-to-release core logic. Runs inside a full clone whose `origin` is
# the repository; reads env vars; its only network calls are git fetch/push.
#
# For every `<LABEL_PREFIX>N` label of the merged pull request, the release
# branch `<BRANCH_PREFIX>N` receives the PR's commits:
#   - branch missing  -> created at the merge commit (develop as of the merge),
#                        which already contains the PR: nothing to pick. With
#                        ACTIVE_LABEL set, only the active sprint's branch is
#                        created; any other sprint's PR is left on develop;
#   - branch present  -> the commits are cherry-picked (-x) onto it, oldest
#                        first, skipping any whose patch id is already there,
#                        and pushed;
#   - conflict        -> the cherry-pick is aborted, the branch is left as it
#                        was, and the branch is reported as CONFLICT.
#
# Which commits: a squash merge is the one merge commit. A rebase merge is the
# last COMMIT_COUNT commits ending at the merge commit; it is recognised by
# their patch ids all matching the PR's own commits (refs/pull/N/head), which
# GitHub keeps after the branch is deleted. Merge commits are not supported
# (the repos using this action forbid them).
#
# Outputs (GITHUB_OUTPUT): status = ok | conflict | no-label,
# branches = comma-separated, report = one line per branch.
# Exits 0 whatever the outcome; `status` carries it. Never touches develop.
set -uo pipefail

PR_NUMBER="${PR_NUMBER:-}"
MERGE_SHA="${MERGE_SHA:-}"
COMMIT_COUNT="${COMMIT_COUNT:-1}"
LABELS="${LABELS:-}"
LABEL_PREFIX="${LABEL_PREFIX:-sprint }"
BRANCH_PREFIX="${BRANCH_PREFIX:-release/sprint-}"
ACTIVE_LABEL="${ACTIVE_LABEL:-}"
DRY_RUN="${DRY_RUN:-}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

REPORT=""
COMMITS=""

note() { echo "$*"; }
warn() { echo "::warning::$*"; }
report() {
  echo "$*"
  REPORT+="$*"$'\n'
}

# Print the release branch of every `<LABEL_PREFIX>…` label, one per line,
# in label order. Spaces in the remainder become dashes.
release_branches() {
  local IFS=',' label rest
  for label in $LABELS; do
    label="${label#"${label%%[![:space:]]*}"}"
    label="${label%"${label##*[![:space:]]}"}"
    [[ "$label" == "$LABEL_PREFIX"* ]] || continue
    rest="${label#"$LABEL_PREFIX"}"
    [[ -n "$rest" ]] || continue
    printf '%s%s\n' "$BRANCH_PREFIX" "${rest// /-}"
  done
}

# Print the release branch of ACTIVE_LABEL, or nothing when it is unset.
active_branch() {
  [[ -n "$ACTIVE_LABEL" ]] || return 0
  local rest="${ACTIVE_LABEL#"$LABEL_PREFIX"}"
  printf '%s%s\n' "$BRANCH_PREFIX" "${rest// /-}"
}

patch_id() {
  git diff-tree -p --root "$1" | git patch-id --stable | cut -d' ' -f1
}

# Print the commits to cherry-pick, oldest first.
pr_commits() {
  if (( COMMIT_COUNT <= 1 )); then
    printf '%s\n' "$MERGE_SHA"
    return
  fi
  if ! git fetch -q origin "refs/pull/${PR_NUMBER}/head:refs/pick/pr-head" 2>/dev/null; then
    warn "cannot fetch refs/pull/${PR_NUMBER}/head: assuming a squash merge"
    printf '%s\n' "$MERGE_SHA"
    return
  fi
  local pr_ids candidate
  pr_ids=$(git rev-list -n "$COMMIT_COUNT" refs/pick/pr-head | while read -r sha; do patch_id "$sha"; done)
  for candidate in $(git rev-list --reverse -n "$COMMIT_COUNT" "$MERGE_SHA"); do
    if ! grep -qx "$(patch_id "$candidate")" <<<"$pr_ids"; then
      printf '%s\n' "$MERGE_SHA" # a squash: the PR's own commits never reached develop
      return
    fi
  done
  git rev-list --reverse -n "$COMMIT_COUNT" "$MERGE_SHA"
}

short() { printf '%s' "${1:0:9}"; }

plural() { # <count> <noun>
  if (( $1 == 1 )); then printf '%s %s' "$1" "$2"; else printf '%s %ss' "$1" "$2"; fi
}

# Bring release branch $1 up to date with the PR's commits. Returns 1 on a
# conflict or a failed push, 0 otherwise. $2 = 1 on the retry after a rejected push.
pick_onto() {
  local branch=$1 retry=${2:-0} sha picked=() skipped=() conflict_files

  git cherry-pick --abort >/dev/null 2>&1 || true
  git reset -q --hard

  if ! git rev-parse -q --verify "refs/remotes/origin/$branch" >/dev/null; then
    # Only the active sprint gets a release branch cut. A PR of a later
    # sprint stays on develop until its sprint starts; a PR of an earlier,
    # already released sprint stays on develop too, rather than reviving its
    # branch.
    if [[ -n "$ACTIVE_LABEL" && "$branch" != "$(active_branch)" ]]; then
      report "$branch: not the active sprint ($ACTIVE_LABEL) and no branch yet: left on develop"
      return 0
    fi
    if [[ -n "$DRY_RUN" ]]; then
      report "$branch: WOULD be created at $(short "$MERGE_SHA")"
      return 0
    fi
    if ! git push -q origin "$MERGE_SHA:refs/heads/$branch" 2>&1; then
      report "$branch: PUSH FAILED while creating the branch"
      return 1
    fi
    report "$branch: created at $(short "$MERGE_SHA"), develop as of the merge of #$PR_NUMBER"
    return 0
  fi

  git checkout -q -B "pick/$branch" "refs/remotes/origin/$branch"
  for sha in $COMMITS; do
    # `-` from git cherry: a commit with this patch id is already on the branch.
    if [[ "$(git cherry HEAD "$sha" "$sha~1" 2>/dev/null)" == -* ]]; then
      skipped+=("$sha")
      continue
    fi
    if git cherry-pick -x "$sha" >/dev/null 2>&1; then
      picked+=("$sha")
      continue
    fi
    conflict_files=$(git diff --name-only --diff-filter=U)
    if [[ -z "$conflict_files" ]]; then
      # Applied cleanly but changed nothing: the content is already there.
      git cherry-pick --skip >/dev/null 2>&1 || git cherry-pick --abort >/dev/null 2>&1 || true
      git reset -q --hard
      skipped+=("$sha")
      continue
    fi
    git cherry-pick --abort >/dev/null 2>&1 || true
    git reset -q --hard
    report "$branch: CONFLICT on $(short "$sha") in $(tr '\n' ' ' <<<"$conflict_files" | sed 's/ $//')"
    return 1
  done

  if (( ${#picked[@]} == 0 )); then
    report "$branch: already on the branch"
    return 0
  fi
  if [[ -n "$DRY_RUN" ]]; then
    report "$branch: WOULD push $(plural ${#picked[@]} commit): $(for s in "${picked[@]}"; do short "$s"; printf ' '; done)"
    return 0
  fi
  if ! git push -q origin "HEAD:refs/heads/$branch" 2>&1; then
    if (( retry == 0 )); then
      # Someone pushed to the branch meanwhile: take their tip and pick again.
      note "$branch: push rejected, fetching and retrying once"
      git fetch -q origin "+refs/heads/$branch:refs/remotes/origin/$branch"
      pick_onto "$branch" 1
      return $?
    fi
    report "$branch: PUSH FAILED after a retry"
    return 1
  fi
  report "$branch: picked $(plural ${#picked[@]} commit): $(for s in "${picked[@]}"; do short "$s"; printf ' '; done | sed 's/ $//')"
  return 0
}

write_outputs() { # <status> <branches, one per line>
  local branches
  branches=$(printf '%s' "$2" | paste -sd, -)
  {
    echo "status=$1"
    echo "branches=$branches"
    echo "report<<__PICK_REPORT__"
    printf '%s' "$REPORT"
    echo "__PICK_REPORT__"
  } >> "$GITHUB_OUTPUT"
}

main() {
  local branches status=ok branch
  branches=$(release_branches)
  if [[ -z "$branches" ]]; then
    report "#$PR_NUMBER carries no '${LABEL_PREFIX}N' label: nothing to cherry-pick"
    write_outputs no-label ""
    return 0
  fi
  if [[ -z "$MERGE_SHA" ]]; then
    report "#$PR_NUMBER has no merge commit: nothing to cherry-pick"
    write_outputs conflict "$branches"
    return 0
  fi
  COMMITS=$(pr_commits)
  note "#$PR_NUMBER: $(plural "$(wc -l <<<"$COMMITS")" commit) to pick ($(tr '\n' ' ' <<<"$COMMITS" | sed 's/ $//'))"
  while IFS= read -r branch; do
    [[ -n "$branch" ]] || continue
    pick_onto "$branch" || status=conflict
  done <<<"$branches"
  write_outputs "$status" "$branches"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
  exit 0
fi
