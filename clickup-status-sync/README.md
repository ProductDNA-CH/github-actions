# ClickUp Status Sync

A GitHub composite action that moves a ClickUp task to the right status when a branch
is created or a pull request is opened/merged — driven entirely from GitHub, with **no
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
| `pull_request` | `opened` / `ready_for_review` / `reopened` | `main` | **demo done** |
| `pull_request` | `closed` + merged | `develop` | **dev done** |
| `pull_request` | `closed` + merged | `main` | **shipped** |
| `pull_request` | `closed`, not merged | — | no-op |
| `create` (tag) | — | — | no-op |

The task ID is extracted from the branch name (head branch for PRs) with the regex
`<id-prefix>-[0-9]+` (default prefix `CORE`); all matches are deduplicated and updated.
ClickUp matches the `status` field **case-insensitively**.

## Usage

In each consumer repo, add `.github/workflows/clickup-status-sync.yml`:

```yaml
name: ClickUp status sync
on:
  create:
  pull_request:
    types: [opened, ready_for_review, reopened, closed]
permissions: {}
jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: ProductDNA-CH/github-actions/clickup-status-sync@clickup-status-sync/v1
        with:
          clickup-token: ${{ secrets.CLICKUP_API_TOKEN }}
```

No `checkout` is needed — the action only reads the event payload, so it needs **no GitHub
permissions** (`permissions: {}`).

## Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `clickup-token` | **yes** | — | ClickUp API token (`pk_...`) of the bot user |
| `clickup-team-id` | no | `90151502952` | ClickUp workspace/team id (for `custom_task_ids`) |
| `dev-branch` | no | `develop` | Branch that maps to *in review* / *dev done* |
| `prod-branch` | no | `main` | Branch that maps to *demo done* / *shipped* |
| `id-prefix` | no | `CORE` | Custom task id prefix |
| `status-in-dev` | no | `in development` | Status set when a branch is created |
| `status-in-review` | no | `in review` | Status set when a PR opens to `dev-branch` |
| `status-dev-done` | no | `dev done` | Status set when a PR merges to `dev-branch` |
| `status-demo-done` | no | `demo done` | Status set when a PR opens to `prod-branch` |
| `status-shipped` | no | `shipped` | Status set when a PR merges to `prod-branch` |

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
- **No anti-regression guard.** Opening a new `develop` PR on an already-shipped task moves it back
  to *in review* — this matches the original native behavior. (Could be added later if desired.)

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
