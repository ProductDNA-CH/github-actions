# Install ArgoCD CLI action
This action aims to install the ArgoCD CLI package.

github.com/ProductDNA-CH/github-actions/blob/master/install-argocd-cli/action.yaml

# Usage
```
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: ArgoCD CLI install
        uses: ProductDNA-CH/github-actions/install-argocd-cli@master
      - name: ArgoCD Applications deploy
        run: |
          argocd app set myapp --helm-set image.tag=${{ github.event.inputs.tag }}
        shell: bash
        env:
          ARGOCD_SERVER: ${{ vars.ARGOCD_SERVER }}
          ARGOCD_AUTH_TOKEN: ${{ secrets.ARGOCD_AUTH_TOKEN }}
          ARGOCD_OPTS: ${{ vars.ARGOCD_OPTS }}
```
