# Python Library Test Action

GitHub Action to run tests for Python libraries using `uv` and `pytest`.

## Usage

```yaml
name: Test

on:
  push:
  pull_request:

permissions:
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version:
          - 3.12
          - 3.13
    steps:
      - uses: ProductDNA-CH/github-actions/python-lib-test@main
        with:
          python_version: ${{ matrix.python-version }}
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `python_version` | Python version to test | Yes | - |
| `uv_version` | UV version to use | No | latest |

## What it does

1. Checks out the repository
2. Installs `uv` and Python
3. Runs `uv sync --locked --all-extras --dev`
4. Runs `uv run pytest`

## Requirements

Your repository must have:
- `pyproject.toml` with dependencies
- `uv.lock` file
- Tests in a `tests/` directory
