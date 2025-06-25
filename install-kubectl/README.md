# install-kubectl GitHub Action

This action installs the [kubectl](https://kubernetes.io/docs/tasks/tools/) CLI tool in your GitHub Actions workflow.

## Inputs

| Name    | Description         | Default  |
| ------- | ------------------ | -------- |
| version | Kubectl version to install (`latest` for the most recent stable release) | `latest` |

## Usage

```yaml
- name: Install kubectl
  uses: ProductDNA-CH/github-actions/install-kubectl@master
  with:
    version: 'latest' # or specify a version, e.g., '1.29.0'
```

## Example

```yaml
jobs:
  setup-kubectl:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install kubectl
        uses: ProductDNA-CH/github-actions/install-kubectl@master
        with:
          version: 'latest'
      - name: Verify kubectl version
        run: kubectl version --client
```
