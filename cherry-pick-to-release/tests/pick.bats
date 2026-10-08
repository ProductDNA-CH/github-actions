#!/usr/bin/env bats
# Run: bats cherry-pick-to-release/tests/pick.bats
#
# Every test builds a throwaway bare "origin" with a develop branch, merges
# pull requests into it the way GitHub does (squash or rebase, plus the
# refs/pull/N/head ref GitHub keeps), then runs pick.sh from a fresh clone and
# looks at what reached origin.
SCRIPT="${BATS_TEST_DIRNAME}/../pick.sh"

setup() {
  export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
  export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
  export GIT_CONFIG_GLOBAL=/dev/null
  TMP="$(mktemp -d)"
  ORIGIN="$TMP/origin.git"
  SEED="$TMP/seed"
  WORK="$TMP/work"
  OUT="$TMP/github_output"
  git init -q --bare -b develop "$ORIGIN"
  git init -q -b develop "$SEED"
  cd "$SEED"
  printf 'line 1\nline 2\nline 3\n' > a.txt
  git add . && git commit -qm "chore: init"
  git remote add origin "$ORIGIN"
  git push -q origin develop
}

teardown() {
  cd / && rm -rf "$TMP"
}

# Merge a pull request into develop the way GitHub does.
#   make_pr <number> <squash|rebase> <commit count> <file to append to>
# Sets MERGE_SHA and COMMIT_COUNT like the pull_request event would.
make_pr() {
  local n=$1 method=$2 count=$3 file=$4 i
  cd "$SEED"
  git checkout -q develop && git checkout -q -b "pr-$n"
  for i in $(seq 1 "$count"); do
    echo "pr$n commit $i" >> "$file"
    git add . && git commit -qm "feat: pr $n commit $i"
  done
  git push -q origin "refs/heads/pr-$n:refs/pull/$n/head"
  git checkout -q develop
  if [ "$method" = squash ]; then
    git merge -q --squash "pr-$n" && git commit -qm "feat: pr $n squashed (#$n)"
  else
    git merge -q --ff-only "pr-$n"
  fi
  git push -q origin develop
  MERGE_SHA=$(git rev-parse develop)
  COMMIT_COUNT=$count
}

# Create release/<name> on origin at develop's current tip.
make_release() {
  git -C "$SEED" push -q origin "develop:refs/heads/release/$1"
}

# A commit straight onto an existing release branch (a hand cherry-pick, a hotfix).
commit_on_release() { # <name> <file> <content> <message>
  cd "$SEED"
  git fetch -q origin
  git checkout -q -B "tmp-release" "origin/release/$1"
  printf '%s\n' "$3" > "$2"
  git add . && git commit -qm "$4"
  git push -q origin "HEAD:refs/heads/release/$1"
  git checkout -q develop
}

# Run pick.sh from a fresh clone of origin. $1 = LABELS, rest = extra env.
run_pick() {
  local labels=$1; shift
  # Leave the previous clone before deleting it: on Linux a process whose cwd
  # was removed cannot run `git clone` ("Unable to read current working directory").
  cd "$TMP"
  rm -rf "$WORK"
  git clone -q "$ORIGIN" "$WORK" 2>/dev/null
  cd "$WORK"
  : > "$OUT"
  run env GITHUB_OUTPUT="$OUT" PR_NUMBER="${PR_NUMBER:-7}" MERGE_SHA="${MERGE_SHA:-}" \
    COMMIT_COUNT="${COMMIT_COUNT:-1}" LABELS="$labels" "$@" bash "$SCRIPT"
}

out_status() { sed -n 's/^status=//p' "$OUT"; }
origin_tip() { git -C "$SEED" ls-remote -q "$ORIGIN" "refs/heads/$1" | cut -f1; }
origin_subjects() { git -C "$WORK" fetch -q origin && git -C "$WORK" log --format=%s "origin/$1"; }

# --- release_branches (unit) ------------------------------------------------

@test "maps sprint labels to release branches and ignores the others" {
  run env LABELS="respect-saas, sprint 24,approved by claude" bash -c 'source "'"$SCRIPT"'"; release_branches'
  [ "$status" -eq 0 ]
  [ "$output" = "release/sprint-24" ]
}

@test "one branch per sprint label, in label order" {
  run env LABELS="sprint 25,sprint 24" bash -c 'source "'"$SCRIPT"'"; release_branches'
  [ "$output" = $'release/sprint-25\nrelease/sprint-24' ]
}

@test "label and branch prefixes are configurable" {
  run env LABELS="iteration 3" LABEL_PREFIX="iteration " BRANCH_PREFIX="rel/it-" \
    bash -c 'source "'"$SCRIPT"'"; release_branches'
  [ "$output" = "rel/it-3" ]
}

@test "no sprint label -> nothing" {
  run env LABELS="respect-saas,dpp" bash -c 'source "'"$SCRIPT"'"; release_branches'
  [ -z "$output" ]
}

# --- end to end ---------------------------------------------------------------

@test "no sprint label: status no-label, nothing pushed" {
  make_pr 7 squash 1 a.txt
  run_pick "respect-saas"
  [ "$status" -eq 0 ]
  [ "$(out_status)" = "no-label" ]
  [ -z "$(origin_tip release/sprint-24)" ]
}

@test "missing release branch: created at the merge commit, nothing to pick" {
  make_pr 7 squash 1 a.txt
  run_pick "sprint 24"
  [ "$status" -eq 0 ]
  [ "$(out_status)" = "ok" ]
  [ "$(origin_tip release/sprint-24)" = "$MERGE_SHA" ]
  [[ "$output" == *"release/sprint-24: created"* ]]
}

@test "squash merge of a 2-commit PR: the one squash commit is picked, with -x" {
  make_release sprint-24
  make_pr 7 squash 2 b.txt
  run_pick "sprint 24"
  [ "$status" -eq 0 ]
  [ "$(out_status)" = "ok" ]
  [ "$(origin_subjects release/sprint-24 | head -1)" = "feat: pr 7 squashed (#7)" ]
  [ "$(origin_subjects release/sprint-24 | wc -l)" -eq 2 ]
  git -C "$WORK" log -1 --format=%b origin/release/sprint-24 | grep -q "cherry picked from commit $MERGE_SHA"
  [[ "$output" == *"release/sprint-24: picked 1 commit"* ]]
}

@test "rebase merge of a 2-commit PR: both commits are picked, oldest first" {
  make_release sprint-24
  make_pr 7 rebase 2 b.txt
  run_pick "sprint 24"
  [ "$status" -eq 0 ]
  [ "$(out_status)" = "ok" ]
  [ "$(origin_subjects release/sprint-24 | head -2 | tr '\n' '|')" = "feat: pr 7 commit 2|feat: pr 7 commit 1|" ]
  [[ "$output" == *"release/sprint-24: picked 2 commits"* ]]
}

@test "commit already on the release branch (by patch id): skipped, branch untouched" {
  make_release sprint-24
  make_pr 7 squash 1 b.txt
  run_pick "sprint 24"
  [ "$(out_status)" = "ok" ]
  tip=$(origin_tip release/sprint-24)
  run_pick "sprint 24"
  [ "$status" -eq 0 ]
  [ "$(out_status)" = "ok" ]
  [ "$(origin_tip release/sprint-24)" = "$tip" ]
  [[ "$output" == *"release/sprint-24: already on the branch"* ]]
}

@test "conflict: aborted, branch untouched, status conflict, file named, work tree clean" {
  make_release sprint-24
  commit_on_release sprint-24 a.txt "release side" "hotfix: release edit"
  tip=$(origin_tip release/sprint-24)
  make_pr 7 squash 1 a.txt
  run_pick "sprint 24"
  [ "$status" -eq 0 ]
  [ "$(out_status)" = "conflict" ]
  [ "$(origin_tip release/sprint-24)" = "$tip" ]
  [[ "$output" == *"release/sprint-24: CONFLICT"* ]]
  [[ "$output" == *"a.txt"* ]]
  [ ! -d "$WORK/.git/sequencer" ]
  [ -z "$(git -C "$WORK" status --porcelain)" ]
}

@test "two sprint labels: both branches get the commit" {
  make_release sprint-24
  make_release sprint-25
  make_pr 7 squash 1 b.txt
  run_pick "sprint 24,sprint 25"
  [ "$(out_status)" = "ok" ]
  [ "$(origin_subjects release/sprint-24 | head -1)" = "feat: pr 7 squashed (#7)" ]
  [ "$(origin_subjects release/sprint-25 | head -1)" = "feat: pr 7 squashed (#7)" ]
}

@test "a conflict on one branch does not stop the other" {
  make_release sprint-24
  make_release sprint-25
  commit_on_release sprint-24 a.txt "release side" "hotfix: release edit"
  make_pr 7 squash 1 a.txt
  run_pick "sprint 24,sprint 25"
  [ "$(out_status)" = "conflict" ]
  [ "$(origin_subjects release/sprint-25 | head -1)" = "feat: pr 7 squashed (#7)" ]
  [[ "$output" == *"release/sprint-24: CONFLICT"* ]]
  [[ "$output" == *"release/sprint-25: picked 1 commit"* ]]
}

@test "dry run: resolves and reports, pushes nothing" {
  make_release sprint-24
  tip=$(origin_tip release/sprint-24)
  make_pr 7 squash 1 b.txt
  run_pick "sprint 24" DRY_RUN=1
  [ "$status" -eq 0 ]
  [ "$(out_status)" = "ok" ]
  [ "$(origin_tip release/sprint-24)" = "$tip" ]
  [[ "$output" == *"WOULD"* ]]
}

@test "active_branch maps the active label through the prefixes" {
  run env ACTIVE_LABEL="sprint 24" bash -c 'source "'"$SCRIPT"'"; active_branch'
  [ "$output" = "release/sprint-24" ]
  run env ACTIVE_LABEL="" bash -c 'source "'"$SCRIPT"'"; active_branch'
  [ -z "$output" ]
}

@test "active label: a missing branch for another sprint is not created, the PR stays on develop" {
  make_pr 7 squash 1 a.txt
  run_pick "sprint 25" ACTIVE_LABEL="sprint 24"
  [ "$status" -eq 0 ]
  [ "$(out_status)" = "ok" ]
  [ -z "$(origin_tip release/sprint-25)" ]
  [[ "$output" == *"release/sprint-25: not the active sprint (sprint 24)"* ]]
}

@test "active label: a missing branch for the active sprint is created" {
  make_pr 7 squash 1 a.txt
  run_pick "sprint 24" ACTIVE_LABEL="sprint 24"
  [ "$(out_status)" = "ok" ]
  [ "$(origin_tip release/sprint-24)" = "$MERGE_SHA" ]
}

@test "active label: an existing branch of another sprint still gets the pick" {
  make_release sprint-24
  make_pr 7 squash 1 b.txt
  run_pick "sprint 24" ACTIVE_LABEL="sprint 25"
  [ "$(out_status)" = "ok" ]
  [ "$(origin_subjects release/sprint-24 | head -1)" = "feat: pr 7 squashed (#7)" ]
}

@test "report is written to GITHUB_OUTPUT as a multi-line value" {
  make_pr 7 squash 1 a.txt
  run_pick "sprint 24"
  grep -q '^report<<' "$OUT"
  grep -q 'release/sprint-24: created' "$OUT"
  grep -q '^branches=release/sprint-24$' "$OUT"
}
