# Validate PR Name GitHub Action

This composite GitHub Action validates pull request titles using the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) specification, with a configurable list of allowed scopes.

## ✅ Supported commit types

The following types are supported and hardcoded into the action:

- `feat`
- `fix`
- `docs`
- `style`
- `refactor`
- `perf`
- `test`
- `build`
- `ci`
- `chore`
- `revert`
- `release`
- `hotfix`

## 📥 Inputs

| Name           | Required | Description                                              |
|----------------|----------|----------------------------------------------------------|
| `scopes`       | No       | Comma-separated list of allowed scopes. Optional.       |
| `github-token` | Yes      | GitHub token with `issues: write` permission.            |

NB: The token should have permissions to post comments on the pull request with the `issues: write` permission.

## 🔧 Example usage

```yaml
name: PR Name Validator

on:
  pull_request:
    types:
      - opened
      - reopened
      - edited
      - synchronize

permissions:
  pull-requests: write

jobs:
  check-pr-name:
    runs-on: ubuntu-latest
    steps:
      - name: Validate PR name
        uses: ProductDNA-CH/github-actions/validate-pr-name@master
        with:
          scopes: respect-code,respect-code-e2e,respect-saas,respect-saas-e2e,testbed,testbed-e2e,ui,api,core
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

## 📌 Title format

The PR title must follow the format:

```yaml
<type>(<scope>): <description>
```

Where:

- `<type>` is one of the supported types
- `<scope>` is one of the allowed scopes provided in `scopes` (or optional if `scopes` is empty)
- `!` is optional for breaking changes

### ✅ Valid example
```yaml
feat(ui): add dark mode support
```

### ✅ Valid example without scopes (if `scopes` input is empty)
```yaml
fix: correct minor bug
```

### ❌ Invalid example
```yaml
feature(ui): added new button style
```

## 💬 Comments on failure

If the title does not match the expected format, the action will post a comment on the pull request with the expected pattern and exit with an error.

---

For questions or feedback, feel free to open an issue in this repository.
