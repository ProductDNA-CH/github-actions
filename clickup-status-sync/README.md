# ClickUp Status Sync

A GitHub composite action that moves a ClickUp task to the right status when a branch
is created, a pull request is opened/merged or a release is published — driven entirely from GitHub, with **no
native ClickUp automations**.

## Why this exists

ClickUp's native "GitHub Automations" must be created **one per repository × per transition**
in the UI, and each one is bound to **a single user's personal GitHub OAuth grant**. When that
user's token is revoked or they leave, the automation silently fails and ClickUp disables it
(error `AUTO_951 - GitHub token is invalid ...`). That model produced ~19 hand-duplicated rules
coupled to one person's account.

This action replaces all of them with **one versioned definition** consumed by a ~12-line workflow
in each repo, authenticated by **one bot ClickUp token** stored as a GitHub org secret — decoupled
from any individual.

## Status mapping

| GitHub event | Detail | `base` branch | → ClickUp status |
|---|---|---|---|
| `create` (branch) | branch created referencing a task | — | **in development** |
| `pull_request` | `opened` / `ready_for_review` / `reopened` | `develop` | **in review** |
| `pull_request` | `opened` / `ready_for_review` / `reopened` / `synchronize` | `main` | **demo done** |
| `pull_request` | `closed` + merged | `develop` | **dev done** |
| `pull_request` | `closed` + merged | `main` | **demo done** |
| `release` | `published` / `released`, not a prerelease | — | **shipped** |
| `pull_request` | `synchronize` | `develop` | no-op |
| `pull_request` | `closed`, not merged | — | no-op |
| `create` (tag) | — | — | no-op |
| `release` | prerelease, or any other action | — | no-op |

**Shipped means published.** Merging a release PR to `main` only stages its code on
demo; production deploys when a GitHub release is published, which can be days later.
So a merge to `main` keeps the task at *demo done*, and the release event moves it to
*shipped*. Before v2, a merge to `main` set *shipped* directly, and Sprint 24 ended with
tickets marked shipped whose release was still a draft.

Task IDs are extracted from the branch name (head branch for PRs) and, for pull requests,
from the auto-generated `### Click Up Tasks` section of the PR body (produced by the sibling
action `list-tickets-from-commit-to-pr`), with the regex `<id-prefix>-[0-9]+` (default prefix
`CORE`). All matches across both sources are deduplicated and updated. Only that
machine-generated section is read, never the free-text prose of the description, so a task id
mentioned in `## Describe your changes` is not moved. ClickUp matches the `status` field
**case-insensitively**.

For a published release, the ids come from one of two places, chosen with
`release-ids-from`:

- `commits` (default): every commit between the **previous published release with the
  same tag prefix** and this one. The prefix is the tag without its trailing version
  (`v0.2.141` → `v`, `rss-v0.1.79` → `rss-v`), so a monorepo publishing one release per
  app compares each app with its own previous release. The first release of a prefix has
  nothing to compare with: it warns and updates nothing.
- `body`: the release notes. Use it where the notes already list only what the release
  ships, like the frontend monorepo, whose notes hold the commits that touched that one
  app. Every commit since the previous tag would also include the other apps' work.

For a pull request to `main`, the ids are also read from **every commit of the PR**, through
the paginated compare endpoint. The task-list section cannot be relied on there: the sibling
action writes it in a workflow that runs at the same time as this one, so on `opened` it is
still empty. And the PR commits endpoint stops at 250 commits, which a release can exceed.

## Usage

In each consumer repo, add `.github/workflows/clickup-status-sync.yml`:

```yaml
name: ClickUp status sync
on:
  create:
  pull_request:
    types: [opened, ready_for_review, reopened, synchronize, closed]
  release:
    types: [released]
permissions:
  contents: read
jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: ProductDNA-CH/github-actions/clickup-status-sync@clickup-status-sync/v2
        with:
          clickup-token: ${{ secrets.CLICKUP_API_TOKEN }}
          # release-ids-from: body   # when the release notes are scoped per app
```

`released` fires once, when a release is published (or a prerelease is promoted), and not
for a prerelease. A release published by a workflow with the default `GITHUB_TOKEN`
triggers no other workflow, so publish it by hand or with an app token.

No `checkout` is needed. The only GitHub permission it uses is `contents: read`, to list the
commits of a PR to `main`, the releases, and a release's commits; without it those ids are
skipped with a warning.

## Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `clickup-token` | **yes** | — | ClickUp API token (`pk_...`) of the bot user |
| `github-token` | no | `github.token` | Token that lists a `main` PR's commits (`contents: read`) |
| `clickup-team-id` | no | `90151502952` | ClickUp workspace/team id (for `custom_task_ids`) |
| `dev-branch` | no | `develop` | Branch that maps to *in review* / *dev done* |
| `prod-branch` | no | `main` | Branch that maps to *demo done* / *shipped* |
| `id-prefix` | no | `CORE` | Custom task id prefix |
| `status-in-dev` | no | `in development` | Status set when a branch is created |
| `status-in-review` | no | `in review` | Status set when a PR opens to `dev-branch` |
| `status-dev-done` | no | `dev done` | Status set when a PR merges to `dev-branch` |
| `status-demo-done` | no | `demo done` | Status set when a PR opens to, or merges into, `prod-branch` |
| `status-shipped` | no | `shipped` | Status set when a release is published |
| `release-ids-from` | no | `commits` | `commits` since the previous release of the same prefix, or the release `body` |

## Prerequisites (one-time, by an org/workspace admin)

1. **Bot ClickUp user.** ClickUp has no native service account — create a dedicated **Member**
   (e.g. `bot-devops@productdna.com`) with edit rights on the target space, so the sync is not
   coupled to any person.
2. **API token.** Logged in as the bot: avatar → `Settings` → `Apps` → `API Token` → `Generate`
   (a `pk_...` token).
3. **Verify the token and read the exact status names** of your list:

   ```bash
   curl -s -H "Authorization: pk_XXXX" \
     "https://api.clickup.com/api/v2/list/<LIST_ID>" | jq '.statuses[].status'
   ```

4. **Org secret** scoped to the consumer repos:

   ```bash
   gh secret set CLICKUP_API_TOKEN --org ProductDNA-CH \
     --visibility selected \
     --repos frontend,backend-rss,backend-rsc,core-oauth
   ```

## Behavior & guarantees

- **Never blocks a workflow.** The action always exits `0`. On a missing task ID or a ClickUp API
  error it emits a `::warning::`; on success a `::notice::`.
- **Idempotent.** Re-applying the same status is a no-op on ClickUp's side.
- **Never moves a task back.** Before an update it reads the task's current status; if that status
  is further along `in development → in review → dev done → demo done → shipped`, the task is kept
  where it is and a `::notice::` says so. A follow-up PR merged to `develop` therefore no longer
  sends a shipped task back to *dev done*. Statuses outside that list (`not started`, `scoping`…)
  never block. To reopen a task on purpose, move it back by hand in ClickUp.

## Local testing

The logic lives in a pure, env-driven `sync.sh` (no GitHub API calls), unit-tested with
[bats-core](https://github.com/bats-core/bats-core):

```bash
brew install bats-core
bats clickup-status-sync/tests/sync.bats
```

Set `DRY_RUN=1` to print the intended updates without calling ClickUp:

```bash
DRY_RUN=1 EVENT_NAME=pull_request PR_ACTION=opened \
  PR_BASE_REF=develop PR_HEAD_REF=feat/CORE-100-x \
  ./clickup-status-sync/sync.sh
# ::notice::WOULD update CORE-100 -> in review
```
