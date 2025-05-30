# Validate Branch Name on PR

This GitHub Action validates the name of a branch in a pull request based on the target branch. It enforces naming conventions to help maintain a consistent workflow.

## 🚦 Branch Naming Rules

- **When targeting `develop`:**
  - The source branch must start with one of the following prefixes:
    - `feat/`
    - `fix/`
    - `docs/`
    - `style/`
    - `refactor/`
    - `perf/`
    - `test/`
    - `build/`
    - `ci/`
    - `chore/`
    - `revert/`
- **When targeting `main`:**
  - The source branch must start with one of the following prefixes:
    - `release/`
    - `hotfix/`
- **Other target branches:**  
  - No restrictions are enforced.

If the branch name does not follow the rules, the action will fail and print an error message.

## 📦 Usage

Add the following step to your workflow:

```yaml
- name: Validate branch name
  uses: ProductDNA-CH/github-actions/validate-branch-name-on-pr@master
```

## 💡 Example Workflow

```yaml
name: Validate PR branches name

on:
  pull_request:
    types: [opened, edited, reopened]

jobs:
  validate-branches-name:
    name: Validate branches name on PR
    runs-on: ubuntu-latest
    steps:
      - name: Validate branches name
        uses: ProductDNA-CH/github-actions/validate-branch-name-on-pr@master
```

## 📝 How it works

- Extracts the base (target) and head (source) branch names from the pull request.
- Checks the prefix of the source branch according to the rules above.
- Fails the workflow if the branch name does not match the expected pattern.
