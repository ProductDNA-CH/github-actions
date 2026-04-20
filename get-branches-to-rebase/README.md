# Get Branches to Rebase GitHub Action

This GitHub Action lists branches that should be rebased depending on the current base branch (`main` or `develop`). It helps automate workflows that require keeping certain branches up to date with the latest changes from your main development branches.

## 🚦 Branch Selection Logic

- **If the base branch is `main`:**
  - Lists all remote branches matching:
    - `hotfix/*`
    - `release/*`
    - `develop`
- **If the base branch is `develop`:**
  - Lists all remote branches matching:
    - `feat/*`
    - `fix/*`
    - `docs/*`
    - `style/*`
    - `refactor/*`
    - `perf/*`
    - `test/*`
    - `build/*`
    - `ci/*`
    - `chore/*`
    - `revert/*`

## 🔍 Filtering Logic

The action includes intelligent filtering to exclude branches that are descendants of `refactor/material3`:

1. **Checks if `refactor/material3` exists** in the remote repository
2. **Filters out descendant branches**: If a branch is a descendant of `refactor/material3`, it will be excluded from the rebase list
3. **Logs excluded branches**: The action will display which branches are excluded with a message like: `"Excluding <branch> (descendant of refactor/material3)"`

This prevents unnecessary rebases on branches that are already based on the `refactor/material3` work.

## 📦 Usage

Add the following step to your workflow:

```yaml
- name: Get branches to rebase  
  id: get-branches  
  uses: ProductDNA-CH/github-actions/get-branches-to-rebase@main
```

You can then access the output as a JSON array:

```yaml
- name: Print branches to rebase  
  run: echo "${{ steps.get-branches.outputs.branches }}"
```

## 📝 Outputs

| Name      | Description                                 |
|-----------|---------------------------------------------|
| `branches`| JSON array list of branches to rebase       |

### Example Output

If the action finds the following branches:
- `feat/feature-1`
- `fix/bug-2`
- `docs/update-readme`

The output will be:
```json
["feat/feature-1", "fix/bug-2", "docs/update-readme"]
```

## ⚙️ How it works

1. **Detects the current base branch** using `github.ref_name`
2. **Lists remote branches** using `git branch -rl` to find branches matching the relevant patterns
3. **Formats the list** as a JSON array
4. **Checks for `refactor/material3`** branch existence
5. **Filters descendant branches**: Uses `git merge-base --is-ancestor` to determine if branches are descendants of `refactor/material3` and excludes them
6. **Outputs the filtered JSON array** of branch names to be used in subsequent workflow steps

### Internal Steps

The action performs the following steps internally:

1. **List branches to rebase** - Identifies candidate branches based on the base branch
2. **Format as JSON array** - Converts the list into a proper JSON array format
3. **Check if refactor/material3 exists** - Verifies if the special branch exists in the repository
4. **Filter out branches descendant of refactor/material3** - Removes branches that are already based on Material 3 refactoring work
