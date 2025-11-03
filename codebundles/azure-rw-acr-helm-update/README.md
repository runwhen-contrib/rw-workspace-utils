# RunWhen Local Helm Update Check (ACR)
This is intended for use by customers running a private ACR registry which RunWhen Local must use for it's images. It is intended to be paired with azure-rw-acr-sync. These two CodeBundles function as follows: 

- azure-rw-acr-sync (Not this CodeBundle) - Synchronizes upstream RunWhen images into Azure Container Registry on a regular basis when updates are available. 
- azure-rw-acr-helm-update (**This CodeBundle**) - Compares the running Helm release to the available images in ACR and applys a helm upgrade (cli based) if new images are available. 

## Image Tagging Strategy

This codebundle handles two categories of images with different tagging strategies:

### CodeCollection Images
CodeCollection images use a REF-based tagging strategy with digest verification:
- Tags follow the pattern: `${REF}-${HASH}` (e.g., `main-abc1234`)
- The script looks for tags matching the current REF (default: `main`)
- Compares image digests (SHA256) to ensure consistency
- Excludes architecture-prefixed tags (e.g., `amd64-*`, `arm64-*`)
- Falls back to `${REF}-latest` siblings with matching digests

### RunWhen Local Images
RunWhen Local images use simpler version-based tagging:
- Uses standard semantic versioning
- Selects the latest tag via version sort

## CodeBundle Configuration

Required Variables:
- **REGISTRY_NAME** - The ACR registry name (e.g., `myacr.azurecr.io`)
- **REGISTRY_REPOSITORY_PATH** - The root path/directory in the ACR registry to search for images (e.g., `runwhen`)
- **NAMESPACE** - The Kubernetes namespace (e.g., `runwhen-local`)
- **CONTEXT** - The Kubernetes context
- **HELM_RELEASE** - The name of the helm release to inspect and update (e.g., `runwhen-local`)

Optional Variables:
- **HELM_APPLY_UPGRADE** - Set to `true` to automatically apply the upgrade (default: `false`)
- **REF** - The git reference (branch) for codecollection image tagging (default: `main`)
- **AZURE_RESOURCE_SUBSCRIPTION_ID** - The Azure Subscription ID (auto-detected if not set)

This CodeBundle requires the following custom variables to be added to the workspaceInfo.yaml: 

```
custom: 
    private_registry: azure_acr
    azure_acr_registry: [ACR registry Name]
    azure_service_principal_secret_name: azure-sp (not required if spSecretName is set)
```

## SLI
The SLI runs the helm_update.sh script on a regular basis (defaulted to every 10m), listing the running images the helm release, looking for newer images in ACR, and generating the `helm upgrade` command needed to apply the update. If `HELM_APPLY_UPGRADE="true"`, the helm upgrade is automatically applied.

Pushes the metric of the total number of images that need to be updated. 


## Taskset
Performs the same function as the SLI, but adds the details to the report and can be run on demand. 