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

## 📦 Usage

Add the following step to your workflow:

```yaml
- name: Get branches to rebase  
  id: get-branches  
  uses: ProductDNA-CH/github-actions/get-branches-to-rebase@master
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

- Detects the current base branch using `github.ref_name`.
- Uses `git branch -rl` to list remote branches matching the relevant patterns.
- Outputs a JSON array of branch names to be used in subsequent workflow steps.
