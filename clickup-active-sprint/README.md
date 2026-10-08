# ClickUp Active Sprint

A GitHub composite action that answers one question: **which sprint is active today?** The
answer comes out as the `sprint N` label that [`clickup-sprint-label`](../clickup-sprint-label/README.md)
puts on pull requests, so the two can be compared directly. Its first consumer is
[`cherry-pick-to-release`](../cherry-pick-to-release/README.md), which only creates a release
branch for the active sprint.

## Usage

```yaml
- uses: ProductDNA-CH/github-actions/clickup-active-sprint@main
  id: active
  with:
    clickup-token: ${{ secrets.CLICKUP_API_TOKEN }}
- run: echo "${{ steps.active.outputs.label }}" # sprint 24
```

## Inputs

| Input              | Required | Default         | Description                                   |
| ------------------ | -------- | --------------- | --------------------------------------------- |
| `clickup-token`    | **yes**  | —               | ClickUp API token (`pk_...`) of the bot user   |
| `sprint-folder-id` | no       | `90159037608`   | Folder whose lists are the sprints (`Core plateform`) |
| `sprint-timezone`  | no       | `Europe/Zurich` | Timezone of the sprint calendar               |

## Outputs

| Output   | Value                            |
| -------- | -------------------------------- |
| `label`  | `sprint 24`                      |
| `number` | `24`                             |

## How the sprint is resolved

Among the lists of `sprint-folder-id`, the sprint list (named `Sprint <number>…`) whose dates
cover today: the list's own `start_date` / `due_date` when ClickUp has them, otherwise the
`(M/D - M/D)` range in its name, with the year inferred from today. "Today" is the calendar
date in `sprint-timezone`. When two sprints overlap, the highest-numbered one wins. The rules
are the same code as `clickup-sprint-label`'s fallback, imported from its module.

## Behavior & guarantees

**The step fails** when ClickUp cannot be read or when no sprint covers today (the gap
between two sprints). An unknown active sprint is not a value a consumer should act on
silently; a red job is the honest answer. Consumers that can live without the answer put
`continue-on-error: true` on the step and treat an empty `label` accordingly.

## Local testing

```bash
node --test clickup-active-sprint/tests/active-sprint.test.mjs
CLICKUP_TOKEN=pk_... node clickup-active-sprint/active-sprint.mjs
```
