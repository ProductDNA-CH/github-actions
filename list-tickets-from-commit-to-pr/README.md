# List Tickets from Commits to PR

This GitHub Action automatically extracts Click Up task IDs from commit messages in a pull request and updates the PR description with a list of these tasks.

## Features

- Automatically extracts Click Up task IDs (format: `LETTERS-NUMBERS`, e.g., `TASK-123`, `FEAT-456`)
- Handles pull requests with any number of commits using proper GitHub API pagination
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
      - uses: your-org/github-actions/list-tickets-from-commit-to-pr@master
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

## How it works

1. **Fetches PR details**: Retrieves the current PR description
2. **Gets commits**: Fetches all commits in the PR using GitHub API pagination with Link headers to handle PRs with more than 30 commits
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

## Technical Details

### Pagination Support
This action properly handles GitHub API pagination using Link headers as recommended by [GitHub's documentation](https://docs.github.com/en/rest/using-the-rest-api/using-pagination-in-the-rest-api). This ensures that all commits are fetched, even for large PRs with more than 30 commits (the default API limit).

The action:
- Uses the `/repos/{owner}/{repo}/pulls/{pr}/commits` endpoint with `per_page=100`
- Follows the `rel="next"` links in the response headers to fetch all pages
- Extracts the response body using `awk` for reliable parsing of HTTP responses
