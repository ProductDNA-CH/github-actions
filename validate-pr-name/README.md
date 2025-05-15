# Validate PR Name GitHub Action

This composite GitHub Action validates a pull request’s name against a configurable regex pattern following Conventional Commit guidelines.

---

## Inputs

| Name          | Description                                  | Required | Default                                                                                                                       |
|---------------|----------------------------------------------|----------|-------------------------------------------------------------------------------------------------------------------------------|
| `github-token` | GitHub token used to post comments on the PR | **Yes**  | N/A                                                                                                                           |
| `name-regex`   | Regex pattern to validate the PR name        | No       | `^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\((respect-code|respect-code-e2e|respect-saas|respect-saas-e2e|testbed|testbed-e2e|ui|api|core)\))?!?: .+$` |

---

## Usage

Example workflow using this action:

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
  issues: write

jobs:
  check-pr-name:
    runs-on: ubuntu-latest
    steps:
      - name: Validate PR name
        uses: ProductDNA-CH/github-actions/validate-pr-name@master
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

---

## Notes

- The `github-token` input **must** be provided for the action to function properly.
  - The token should have permissions to post comments on the pull request with the `issues: write` permission.
- Customize the regex via `name-regex` input if you want a different validation pattern.
