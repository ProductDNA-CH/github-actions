# Docker Pull, Tag, and Push Action

This GitHub Action pulls an existing Docker image from a registry, tags it with a new tag, and pushes it back to the registry.

## 📥 Inputs

| Name         | Required | Description                                 |
|--------------|----------|---------------------------------------------|
| `registry`   | Yes      | Docker registry (e.g., `myacr.azurecr.io`)  |
| `image_name` | Yes      | Image name (e.g., `myimage`)                |
| `source_tag` | Yes      | Existing image tag (e.g., commit SHA)       |
| `target_tag` | Yes      | Tag to create and push (e.g., `prod`)       |

## 🚀 Usage Example

```yaml
jobs:
  docker-tag-push:
    runs-on: ubuntu-latest
    steps:
      - name: Azure login
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZ_ACR_CLIENT_ID }}
          tenant-id: ${{ secrets.AZ_ACR_TENANT_ID }}
          subscription-id: ${{ secrets.AZ_ACR_SUBSCRIPTION_ID }}

      - name: Login to Azure Container Registry
        run: az acr login --name ${{ vars.AZ_ACR_NAME }}

      - name: Pull, tag, and push Docker image
        uses: ProductDNA-CH/github-actions/docker-pull-tag-push@master
        with:
          registry: ${{ secrets.REGISTRY_URL }}
          image_name: myimage
          source_tag: ${{ github.sha }}
          target_tag: prod
```

## 📝 How it works

1. **Pulls** the image from the specified registry and source tag.
2. **Tags** the image with the new target tag.
3. **Pushes** the newly tagged image back to the registry.

## 🛡️ Requirements

- You must authenticate to your Docker registry before using this action (see example above).

---

For questions or feedback, open an issue in this repository.