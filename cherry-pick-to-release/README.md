# Cherry-pick to release

A GitHub composite action that, when a pull request is merged, carries its commits onto the
**release branch of its sprint**: a PR labelled `sprint 24` (by
[`clickup-sprint-label`](../clickup-sprint-label/README.md)) lands on `release/sprint-24`.

| Release branch     | What happens                                                                               |
| ------------------ | ------------------------------------------------------------------------------------------ |
| does not exist yet | created at the PR's merge commit, i.e. `develop` as of that merge, which already holds the PR |
| exists             | the PR's commits are cherry-picked onto it (`-x`), oldest first, and pushed                  |
| conflicts          | the cherry-pick is aborted, the branch is left untouched, `status` is `conflict`             |

The action does the git work and **reports**; it never fails the job on its own. The caller
decides what a `conflict` or a `no-label` means (a Slack message, a red job).

## Usage

```yaml
name: Cherry-pick to release
on:
  pull_request:
    types: [closed]
permissions:
  contents: read
# One release push at a time per base branch, never cancelled mid-pick.
concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.base.ref }}
  cancel-in-progress: false
jobs:
  pick:
    if: github.event.pull_request.merged == true && github.event.pull_request.base.ref == 'develop'
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/create-github-app-token@v3
        id: app-token
        with:
          client-id: ${{ vars.GH_APP_REBASE_CLIENT_ID }}
          private-key: ${{ secrets.GH_APP_REBASE_PRIVATE_KEY }}
      - uses: ProductDNA-CH/github-actions/cherry-pick-to-release@main
        id: pick
        with:
          github-token: ${{ steps.app-token.outputs.token }}
      - if: steps.pick.outputs.status != 'ok'
        run: ... # post ${{ steps.pick.outputs.report }} somewhere, then fail on 'conflict'
```

**Use a GitHub App token for `github-token`.** A push made with `GITHUB_TOKEN` triggers no
workflow, so the release branch's own pull request would not rebuild. The App needs
`contents: write` on the repository and, if the release branches are protected, a place on the
ruleset's bypass list.

## Inputs

| Input            | Required | Default                                   | Description                                           |
| ---------------- | -------- | ----------------------------------------- | ----------------------------------------------------- |
| `github-token`   | **yes**  | —                                         | Pushes to the release branches (`contents: write`)     |
| `labels`         | no       | the event's PR labels                     | Comma-separated labels of the PR                       |
| `pr-number`      | no       | the event's                               | Pull request number                                   |
| `merge-sha`      | no       | the event's                               | The PR's merge commit                                 |
| `commit-count`   | no       | the event's                               | Number of commits in the PR                           |
| `label-prefix`   | no       | `sprint `                                 | Labels that name a release start with this            |
| `branch-prefix`  | no       | `release/sprint-`                         | The label's remainder is appended to this             |
| `git-user-name`  | no       | `github-actions[bot]`                     | Committer of the cherry-picked commits                |
| `git-user-email` | no       | `41898282+github-actions[bot]@users.noreply.github.com` | Committer email                            |
| `dry-run`        | no       | `false`                                   | `true` reports what would be pushed, pushes nothing   |

## Outputs

| Output     | Value                                                                                                   |
| ---------- | ------------------------------------------------------------------------------------------------------- |
| `status`   | `ok` (every branch is up to date), `conflict` (at least one branch could not take the commit, or a push failed), `no-label` (no release label on the PR) |
| `branches` | The release branches resolved from the labels, comma-separated                                           |
| `report`   | One line per branch: `created at …`, `picked N commits: …`, `already on the branch`, `CONFLICT on … in <files>` |

## Which commits are picked

The repositories using this action allow **squash** and **rebase** merges only.

- A squash merge is one commit, the PR's merge commit.
- A rebase merge is the last `commit-count` commits ending at the merge commit. It is
  recognised by their patch ids all matching the PR's own commits, read from
  `refs/pull/<n>/head`, which GitHub keeps after the branch is deleted. Anything else is a
  squash.

A commit whose **patch id** is already on the release branch is skipped (`git cherry`), so a
hotfix picked by hand, or a re-run, is never applied twice. A pick that applies cleanly but
changes nothing is skipped the same way.

## Behavior & guarantees

- **Never fails the job.** The step exits `0`; the outcome is in `status` and `report`, also
  appended to the job summary.
- **Never touches `develop`**, and never force-pushes. A push rejected because someone pushed
  to the release branch meanwhile is retried once on the new tip.
- **A conflict leaves the branch exactly as it was.** The cherry-pick is aborted; the report
  names the commit and the conflicting files so that the pick can be done by hand:

  ```bash
  git fetch origin && git checkout release/sprint-24 && git cherry-pick -x <sha>
  ```

- **Two sprint labels** means two release branches; a conflict on one does not stop the other.
- A label for a sprint whose release branch was already merged and deleted **recreates** that
  branch from `develop` as of the merge. Fix the label and delete the branch if that was a
  mistake.

## Local testing

The logic lives in a pure, env-driven `pick.sh` (no GitHub API calls: git fetch and push
only), unit-tested with [bats](https://github.com/bats-core/bats-core) against throwaway
repositories that are merged into the way GitHub does (squash, rebase, `refs/pull/N/head`):

```bash
bats cherry-pick-to-release/tests/pick.bats
```

A real run against a repository, pushing nothing:

```bash
git clone git@github.com:ProductDNA-CH/frontend.git && cd frontend
PR_NUMBER=4204 MERGE_SHA=$(gh pr view 4204 --json mergeCommit --jq .mergeCommit.oid) \
COMMIT_COUNT=1 LABELS='sprint 24' DRY_RUN=1 bash ../github-actions/cherry-pick-to-release/pick.sh
```
