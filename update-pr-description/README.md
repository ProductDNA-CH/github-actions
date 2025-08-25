# Update PR Description with Click Up Tasks

This GitHub Action automatically extracts Click Up task IDs from commit messages in a pull request and updates the PR description with a list of these tasks.

## Features

- Automatically extracts Click Up task IDs (format: `LETTERS-NUMBERS`, e.g., `TASK-123`, `FEAT-456`)
- Updates PR description with a formatted list of unique task IDs
- Preserves existing PR description content
- Places Click Up tasks between invisible HTML comment markers for clean organization

## Usage

Add this action to your workflow:

```yaml
name: Update PR with Click Up Tasks

on:
  pull_request:
    types: [opened, synchronize]

jobs:
  update-pr:
    runs-on: ubuntu-latest
    steps:
      - uses: your-org/github-actions/update-pr-description@main
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

## How it works

1. **Fetches PR details**: Retrieves the current PR description
2. **Gets commits**: Fetches all commits in the PR
3. **Extracts task IDs**: Finds all Click Up task IDs matching the pattern `[A-Z]+-[0-9]+`
4. **Updates description**: Adds or updates a Click Up tasks section in the PR description

## Example

If your PR contains commits with messages like:
- `TASK-123: Fix authentication bug`
- `feat: Add new feature FEAT-456`
- `Update documentation for ABC-789`

The action will add this section to your PR description:

```markdown
<!--- beginning of the Click Up tasks list -->
### Click Up Tasks
- ABC-789
- FEAT-456
- TASK-123
<!--- end of the Click Up tasks list -->
```

## Inputs

| Input | Description | Required |
|-------|-------------|----------|
| `github-token` | GitHub token used to update the PR description | Yes |

## Requirements

- The action requires `pull_request` events to access PR information
- The GitHub token must have write permissions to the repository