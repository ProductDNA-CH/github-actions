# ClickUp Sprint Label

A GitHub composite action that labels a pull request with the **ClickUp sprint** of the
ticket named in its title, so the open PR list can be read, filtered and searched by sprint
(`label:"sprint 24"`).

| PR title                                        | CORE-7895 sits in the list… | Label                   |
| ----------------------------------------------- | --------------------------- | ----------------------- |
| `fix(respect-saas): [CORE-7895] search …`       | `Sprint 24(9/28 - 10/18)`   | `sprint 24`             |
| `fix(respect-saas): [CORE-7895] search …`       | `Backlog`                   | the sprint active today |
| `chore: add verify-frontend verification skill` | _(no ticket in the title)_  | the sprint active today |

## Usage

In each consumer repo, add `.github/workflows/clickup-sprint-label.yml`:

```yaml
name: ClickUp sprint label
on:
  pull_request:
    types: [opened, reopened, edited]
permissions:
  pull-requests: write
  issues: write # labels are an issues-API resource; also creates one if absent
concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number }}
  cancel-in-progress: true
jobs:
  label:
    # `edited` also fires for body and base-branch edits; only a title change can change the answer.
    if: github.event.action != 'edited' || github.event.changes.title != null
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: ProductDNA-CH/github-actions/clickup-sprint-label@main
        with:
          clickup-token: ${{ secrets.CLICKUP_API_TOKEN }}
```

No `checkout` is needed. Keep the default `github-token`: events raised by `GITHUB_TOKEN`
never trigger another workflow, so labelling here cannot queue anything that listens on
`labeled` (a build, release-drafter, a preview environment). An App token would.

## Inputs

| Input              | Required | Default         | Description                                                      |
| ------------------ | -------- | --------------- | ---------------------------------------------------------------- |
| `clickup-token`    | **yes**  | —               | ClickUp API token (`pk_...`) of the bot user; empty -> no-op     |
| `github-token`     | no       | `github.token`  | Reads and writes the PR's labels (`pull-requests`/`issues` write) |
| `clickup-team-id`  | no       | `90151502952`   | ClickUp workspace/team id (for `custom_task_ids`)                |
| `sprint-folder-id` | no       | `90159037608`   | Folder whose lists are the sprints (`Core plateform`)            |
| `id-prefix`        | no       | `CORE`          | Custom task id prefix                                            |
| `sprint-timezone`  | no       | `Europe/Zurich` | Timezone of the sprint calendar                                  |
| `dry-run`          | no       | `false`         | `true` resolves and reports, writes nothing                      |

## How the sprint is resolved

1. **Ticket ids** are every `<id-prefix>-<digits>` in the PR title, deduplicated. The branch
   name is not read.
2. Each ticket is fetched from ClickUp by custom id. Its sprint is every list it sits in whose
   name starts with `Sprint <number>`: the task's **home list**, or one of its **secondary
   locations** (ClickUp lets a task live in several lists). The label is the lowercase
   `sprint <number>`, with the dates dropped, which is also how the release branches spell it
   (`release/sprint-24`).
3. A title naming tickets from two sprints gets **both** labels.
4. When no ticket resolves to a sprint (no id in the title, a ticket in `Backlog`, an id
   ClickUp does not know) the PR gets the **sprint active today**: among the lists of
   `sprint-folder-id`, the sprint whose dates cover today. The dates come from the list's own
   `start_date` / `due_date` (ClickUp does supply them for our sprint lists), otherwise from
   the `(M/D - M/D)` range in its name, with the year inferred from today (a sprint that wraps
   the new year is active on both sides of it). "Today" is the calendar date in
   `sprint-timezone`, not on the UTC runner. When two sprints overlap the highest-numbered one
   wins; when none covers today (the gap between two sprints) no label is added.

## Keeping the label honest

Only `sprint N` labels are ever touched. After resolution, the PR's sprint labels are made to
match exactly: the wanted ones are added, the others removed, every non-sprint label is left
alone. So a ticket moved to the next sprint gets its new label on the next title edit (or
re-run), and a PR retitled to another ticket does not keep the old sprint.

A label that does not exist yet is created with a fixed colour and description, rather than
through the issues endpoint, which would give it GitHub's default grey.

## Behavior & guarantees

| Situation                                        | Behaviour                                                                                                     |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------- |
| ClickUp unreachable or answering an error        | `::warning::`. **Nothing is removed**: a failed lookup is no evidence the existing label is wrong. Exit `0`. |
| Ticket id unknown to ClickUp (typo in the title) | `::warning::`, the id is skipped, the active sprint applies.                                                  |
| PR from a fork                                   | No secrets, so no ClickUp token: the action does nothing.                                                     |
| GitHub label write fails                         | The step fails, so someone sees it.                                                                            |
| Labels already right                             | No GitHub write at all.                                                                                        |

The step's output is also appended to the job summary.

## Prerequisites

The same bot ClickUp user and `CLICKUP_API_TOKEN` org secret as
[`clickup-status-sync`](../clickup-status-sync/README.md#prerequisites-one-time-by-an-orgworkspace-admin).
The token only needs **read** access to the tasks and the sprint folder.

## Local testing

The logic lives in a dependency-free, env-driven Node module, `sprint-label.mjs`, with the
API clients behind an injectable `fetch`. The tests cover id extraction, sprint name mapping,
home list vs secondary locations, the active sprint by dates and by name (year wrap, overlap,
gap, archived lists), label diffing, and the end-to-end run against a fake API.

```bash
node --test clickup-sprint-label/tests/sprint-label.test.mjs
```

A real run against the APIs, writing nothing:

```bash
CLICKUP_TOKEN=pk_... GITHUB_TOKEN=$(gh auth token) GITHUB_REPOSITORY=ProductDNA-CH/frontend \
PR_NUMBER=4208 PR_TITLE='fix(ui): [CORE-7895] x' DRY_RUN=1 node clickup-sprint-label/sprint-label.mjs
```
