# RunWhen Platform Azure ACR Image Sync

This codebundle synchronizes upstream RunWhen images (CodeCollection and RunWhen Local components) into a private Azure Container Registry. It is intended to be paired with azure-rw-acr-helm-update.

## Purpose

- **azure-rw-acr-sync** (**This CodeBundle**) - Synchronizes upstream RunWhen images into Azure Container Registry when updates are available
- azure-rw-acr-helm-update (Not this CodeBundle) - Compares running Helm releases to available images in ACR and applies helm upgrades

## Image Categories

This codebundle handles two categories of images with different tagging strategies:

### CodeCollection Images
CodeCollection images are resolved from the [RunWhen Skills Registry catalog](https://registry.runwhen.com/api/docs) (`GET /api/v1/catalog/codecollections`):

- Source registries and tags come from the catalog (for example `ghcr.io/runwhen-contrib/rw-cli-codecollection`)
- For each public catalog entry, the script calls `GET /api/v1/catalog/codecollections/{slug}/resolve?ref={REF}` to determine the image tag
- Images are imported into ACR under `${REGISTRY_REPOSITORY_PATH}/{slug}` using the catalog tag (for example `main-b967857-6e4bc81`)

**Public catalog collections include:**

- `rw-cli-codecollection`
- `rw-public-codecollection`
- `rw-generic-codecollection`
- `rw-workspace-utils`
- `azure-c7n-codecollection`
- `aws-c7n-codecollection`

Catalog data is maintained in [codecollection-registry/cc-registry-v2](https://github.com/runwhen-contrib/codecollection-registry/tree/main/cc-registry-v2).

### RunWhen Local Images
RunWhen Local images use simpler tagging:

- Standard versioning or date-based tags
- Latest tag selection via version sort
- Supports optional date-based tagging with `USE_DATE_TAG=true`

**Images:**

- `runwhen-local`
- `opentelemetry-collector`
- `runner`

## Configuration

### Required Variables

- **REGISTRY_NAME** - The ACR registry name (e.g., `myacr.azurecr.io` or `myacr`)
- **REGISTRY_REPOSITORY_PATH** - Root path in ACR for image storage (e.g., `runwhen`)
- **AZURE_RESOURCE_SUBSCRIPTION_ID** - Azure Subscription ID (auto-detected if not set)

### Optional Variables

- **SYNC_IMAGES** - Set to `true` to sync images; `false` generates report only (default: `false` for SLI, `true` for Taskset)
- **REF** - Git reference (branch) passed to the catalog resolve endpoint (default: `main`)
- **REGISTRY_CATALOG_URL** - Base URL for the RunWhen Skills Registry API (default: `https://registry.runwhen.com`)
- **USE_DATE_TAG** - Set to `true` to generate unique date-based tags for `latest` images (default: `false`)
- **USE_DOCKER_AUTH** - Set to `true` to import Docker Hub credentials to bypass rate limits (default: `false`)

### Required Secrets

- **azure_credentials** - Contains AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_CLIENT_SECRET, AZURE_SUBSCRIPTION_ID

### Optional Secrets (if USE_DOCKER_AUTH=true)

- **DOCKER_USERNAME** - Docker Hub username
- **DOCKER_TOKEN** - Docker Hub token/password

## How It Works

### CodeCollection Sync Process

1. Lists public entries from `GET /api/v1/catalog/codecollections`
2. Resolves each slug with `GET /api/v1/catalog/codecollections/{slug}/resolve?ref={REF}`
3. Checks whether the resolved tag already exists in ACR at `${REGISTRY_REPOSITORY_PATH}/{slug}`
4. Imports missing tags from the catalog `image_registry` into ACR

### RunWhen Local Sync Process

1. Renders the latest RunWhen Local Helm chart
2. Extracts image references from rendered manifests
3. Compares creation dates between upstream and ACR images
4. Imports newer images to ACR
5. Optionally replaces `latest` tags with date-based tags

## Usage

### SLI (Service Level Indicator)

The SLI checks for available updates and pushes a metric with the total count of images needing sync:

- Runs on a schedule (e.g., every hour)
- Reports number of outdated images
- Does NOT sync by default (set `SYNC_IMAGES=true` to enable)

### Taskset (On-Demand Sync)

The Taskset performs the actual sync operation:

- Runs on-demand or on schedule
- Syncs images to ACR (default `SYNC_IMAGES=true`)
- Adds detailed output to report

## Examples

### Check for Updates (Dry Run)
```bash
SYNC_IMAGES=false
REF=main
```

### Sync Images from Main Branch
```bash
SYNC_IMAGES=true
REF=main
REGISTRY_NAME=myacr.azurecr.io
REGISTRY_REPOSITORY_PATH=runwhen
```

### Sync Images from Dev Branch
```bash
SYNC_IMAGES=true
REF=dev
REGISTRY_NAME=myacr.azurecr.io
REGISTRY_REPOSITORY_PATH=runwhen
```

### Use Date-Based Tags
```bash
SYNC_IMAGES=true
USE_DATE_TAG=true
```

## Workspace Configuration

Add to your workspaceInfo.yaml:

```yaml
custom: 
    private_registry: azure_acr
    azure_acr_registry: [ACR registry Name]
    azure_service_principal_secret_name: azure-sp
```

## Output

### SLI Output
- Metric: Total number of images requiring update
- JSON files:
  - `cc_images_to_update.json` - CodeCollection images needing sync
  - `images_to_update.json` - RunWhen Local images needing sync

### Taskset Output
- Detailed sync results in report
- Lists of imported images
- Any errors or warnings

## Troubleshooting

### Common Issues

**"Unable to resolve image for slug=..., ref=..."**
- Verify REF matches a branch tracked in the catalog
- Check catalog refs with `GET /api/v1/catalog/codecollections/{slug}/refs`

**"Failed to fetch catalog"**
- Check network connectivity to `registry.runwhen.com`
- Override `REGISTRY_CATALOG_URL` if using a private registry mirror

**Rate limiting from Docker Hub**
- Set `USE_DOCKER_AUTH=true`
- Configure DOCKER_USERNAME and DOCKER_TOKEN secrets

**Import failures**
- Verify azure_credentials have ACR push permissions
- Check Azure subscription is active
- Ensure sufficient ACR storage quota

## Requirements

- Azure CLI (`az`) with ACR access
- Network access to:
  - `registry.runwhen.com` (catalog API)
  - `ghcr.io` (CodeCollection images)
  - `ghcr.io` / `docker.io` (RunWhen Local images)
- Azure credentials with ACR import permissions

## Related CodeBundles

- **azure-rw-acr-helm-update** - Detects and applies updates to RunWhen Local Helm releases using synced images
