# Terraform Init Action

This GitHub Action initializes Terraform with an Azure Blob Storage backend.

## Inputs

| Name                  | Description                                        | Required | Default     |
|-----------------------|----------------------------------------------------|----------|-------------|
| `storage-account-name`| The name of the Azure Storage Account              | Yes      | N/A         |
| `container-name`      | The name of the Azure Blob Storage container       | No       | `tfstates`  |
| `key`                 | The name of the state file                         | Yes      | N/A         |
| `client-id`           | The client ID of the Azure Service Principal       | Yes      | N/A         |
| `subscription-id`     | The subscription ID of the Azure Service Principal | Yes      | N/A         |
| `tenant-id`           | The tenant ID of the Azure Service Principal       | Yes      | N/A         |
| `working-directory`   | The working directory                              | Yes      | N/A         |

## Usage

```yaml
jobs:
# ...
  tf-plan:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Terraform init
        id: init
        uses: ProductDNA-CH/github-actions/terraform-init@master
        with:
          storage-account-name: ${{ vars.AZ_TF_STORAGE_ACCOUNT_NAME }}
          container-name: ${{ vars.AZ_TF_CONTAINER_NAME }}
          key: ${{ matrix.terraform_key }}
          working-directory: ${{ steps.set-variables.outputs.terraform_path }}
          client-id: ${{ secrets.AZ_ARM_CLIENT_ID }}
          subscription-id: ${{ secrets.AZ_ARM_SUBSCRIPTION_ID }}
          tenant-id: ${{ secrets.AZ_ARM_TENANT_ID }}
# ...
```
