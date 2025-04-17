# Terraform init action
This action aims to initialize the Terraform package.

# Usage
```
jobs:
  tf-plan:
    runs-on: ubuntu-latest
    steps:
      - name: Terraform init
        id: init
        uses: ProductDNA-CH/github-actions/terraform-init@master
        with:
          storage-account-name: ${{ secrets.STORAGE_ACCOUNT_NAME }}
          container-name: ${{ secrets.CONTAINER_NAME }}
          key: ${{ secrets.KEY }}
          working-directory:
```
