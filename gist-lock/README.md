# Gist Lock Action

This GitHub Action allows you to create, lock, unlock, or delete a Gist lock file. It is useful for managing temporary locks in workflows, such as protecting critical sections of code from running concurrently.

## Inputs

- `token` (required): **GitHub token** with `gist` scope.
- `mode` (required): The **operation mode**. Can be one of the following values:
  - `create`: Creates a new Gist with the provided content.
  - `lock`: Locks an existing Gist (requires `gist-id`).
  - `unlock`: Unlocks an existing Gist (requires `gist-id`).
  - `delete`: Deletes an existing Gist (requires `gist-id`).
- `gist-id` (optional): The **ID of the Gist** to operate on (only required for `lock`, `unlock`, and `delete` modes).
- `filename` (optional): The **filename** of the lock file. Default is `lock.txt`.
- `content` (optional): The **initial content** of the lock file (only used when creating a Gist). Default is `lock:free`.
- `description` (optional): The **description** of the Gist (only used when creating a Gist). Default is `Temporary lock Gist`.
- `public` (optional): Whether the Gist should be **public** (only used when creating a Gist). Default is `false`.

## Outputs

- `gist-id`: The **ID** of the created Gist (only for the `create` mode).

## Example Usage

### Workflow Example

```yaml
jobs:
  setup-lock:
    runs-on: ubuntu-latest
    outputs:
      gist-id: ${{ steps.create.outputs.gist-id }}
    steps:
      - name: Create Gist lock
        id: create
        uses: ProductDNA-CH/github-actions/gist-lock@master
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          mode: create

  protected-section:
    needs: setup-lock
    runs-on: ubuntu-latest
    steps:
      - name: Acquire lock
        uses: ProductDNA-CH/github-actions/gist-lock@master
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          gist-id: ${{ needs.setup-lock.outputs.gist-id }}
          mode: lock

      - name: Critical work
        run: echo "🚧 Critical work in progress..."

      - name: Release lock
        uses: ProductDNA-CH/github-actions/gist-lock@master
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          gist-id: ${{ needs.setup-lock.outputs.gist-id }}
          mode: unlock

  cleanup:
    needs: [setup-lock, protected-section]
    runs-on: ubuntu-latest
    if: always()
    steps:
      - name: Delete Gist
        uses: ProductDNA-CH/github-actions/gist-lock@master
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          gist-id: ${{ needs.setup-lock.outputs.gist-id }}
          mode: delete
```

## Modes

- **Create Mode**: 
  - This mode creates a new Gist with the specified filename and content. It will return the Gist ID, which you can use in subsequent steps.

- **Lock Mode**: 
  - This mode locks the provided Gist by updating the file's content to indicate that the lock is acquired. If the lock is not free, it will retry every 5 seconds until the lock is acquired.

- **Unlock Mode**: 
  - This mode unlocks the provided Gist by changing the content of the lock file back to `lock:free`.

- **Delete Mode**: 
  - This mode deletes the provided Gist from GitHub.

## Development

If you're developing this action locally, here are the steps to run and test it:

1. Clone the repository to your local machine.
2. Navigate to the `.github/actions/gist-lock-action` directory.
3. Create the action locally:
   - Run `npm install` to install dependencies.
   - Run `npm run test` to test the action locally (if you have tests configured).
4. Modify the action as needed and commit the changes.
5. Push the changes to your repository.

For local testing, you can use the `act` tool to simulate GitHub Actions workflows locally.

## Contributing

If you find any bugs or would like to improve this action, feel free to open an issue or a pull request. Contributions are welcome!

## License

This action is open-source and available under the [MIT License](LICENSE).
