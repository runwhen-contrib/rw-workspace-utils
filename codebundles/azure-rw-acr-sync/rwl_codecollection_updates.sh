#!/bin/bash

set -euo pipefail

# ===================================
# Configuration Variables
# ===================================
OUTPUT_JSON="${OUTPUT_DIR:-$(pwd)}/azure-rw-acr-sync/cc_images_to_update.json"
mkdir -p "$(dirname "$OUTPUT_JSON")"

# Registry-specific variables
REGISTRY_TYPE=${REGISTRY_TYPE:-"acr"} # Default to ACR
REGISTRY_NAME=${REGISTRY_NAME:-""} # Registry name (without .azurecr.io)
REGISTRY_REPOSITORY_PATH=${REGISTRY_REPOSITORY_PATH:-""} # Root path in registry
SYNC_IMAGES=${SYNC_IMAGES:-false} # Whether to sync images
REGISTRY_CATALOG_URL="${REGISTRY_CATALOG_URL:-https://registry.runwhen.com}"

# CodeCollection version resolution
REF="${REF:-main}"

# Docker Hub credentials
docker_username="${DOCKER_USERNAME:-}"
docker_token="${DOCKER_TOKEN:-}"

# Clean Output File
rm -f "$OUTPUT_JSON"

# Set Private Registry
private_registry="${REGISTRY_NAME}"

# ===================================
# Azure Setup
# ===================================
# Check if AZURE_RESOURCE_SUBSCRIPTION_ID is set, otherwise get the current subscription ID
if [ -z "${AZURE_RESOURCE_SUBSCRIPTION_ID:-}" ]; then
    subscription=$(az account show --query "id" -o tsv)
    echo "AZURE_RESOURCE_SUBSCRIPTION_ID is not set. Using current subscription ID: $subscription"
else
    subscription="$AZURE_RESOURCE_SUBSCRIPTION_ID"
    echo "Using specified subscription ID: $subscription"
fi

# Set the subscription to the determined ID
echo "Switching to subscription ID: $subscription"
az account set --subscription "$subscription" || { echo "Failed to set subscription."; exit 1; }

# Ensure Docker credentials are set to avoid throttling (for source registries like Docker Hub)
if [[ -z "$docker_username" || -z "$docker_token" ]]; then
    echo "Warning: Docker credentials (DOCKER_USERNAME and DOCKER_TOKEN) should be set to avoid throttling."
fi

# Attempt ACR login (optional - not required since we use service principal auth)
# Using || true to make it non-blocking if Docker is not available
az acr login -n "$private_registry" 2>/dev/null || echo "Note: Direct ACR login not available (Docker not installed), using service principal authentication"

# ===================================
# Tool Checks
# ===================================
for tool in curl jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "❌ Missing tool: $tool"
        exit 1
    fi
done

# ===================================
# Helper Functions
# ===================================

fetch_catalog_entries() {
    curl -sSf "${REGISTRY_CATALOG_URL}/api/v1/catalog/codecollections"
}

resolve_collection_image() {
    local slug=$1
    curl -sSf "${REGISTRY_CATALOG_URL}/api/v1/catalog/codecollections/${slug}/resolve?ref=${REF}"
}

# Check if a tag exists in ACR
tag_exists_in_acr() {
    local destination_image=$1
    local destination_tag=$2
    
    echo "Checking if tag $destination_tag exists in $private_registry/$destination_image..." >&2

    # First, check if the repository exists
    az acr repository show -n "$private_registry" --repository "$destination_image" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Repository $destination_image does not exist in $private_registry. Flagging as needing update." >&2
        return 1  # Needs update
    fi

    # Then check if the tag exists
    az acr manifest list-metadata "$private_registry/$destination_image" \
        --query "[?tags[?@=='$destination_tag']]" 2>/dev/null | jq -e '. | length > 0' > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo "Tag $destination_tag exists in $private_registry/$destination_image." >&2
        return 0  # Tag exists
    else
        echo "Tag $destination_tag does not exist in $private_registry/$destination_image." >&2
        return 1  # Needs update
    fi
}

# Copy image to ACR
copy_image() {
    local repository_image=$1
    local src_tag=$2
    local destination=$3
    local dest_tag=$4

    # Check if the destination tag already exists
    echo "Checking $destination for tag $dest_tag" >&2
    if tag_exists_in_acr "$destination" "$dest_tag"; then
        echo "✅ Destination tag $dest_tag already exists in $private_registry/$destination. Skipping import." >&2
        return 0
    fi

    echo "📦 Importing image $repository_image:$src_tag to $private_registry/$destination:$dest_tag..." >&2

    # Initialize the command with the basic az acr import structure
    local cmd="az acr import -n ${private_registry} --source ${repository_image}:${src_tag} --image ${destination}:${dest_tag} --force"

    # Conditionally add Docker authentication if the repository is from Docker Hub and credentials are set
    if [[ $repository_image == docker.io/* ]]; then
        if [[ -n "$docker_username" && -n "$docker_token" ]]; then
            echo "Docker Hub image detected. Using Docker credentials for import..." >&2
            cmd+=" --username ${docker_username} --password ${docker_token}"
        else
            echo "Warning: Docker Hub image detected but credentials are not set. Throttling might occur." >&2
        fi
    fi

    # Execute the dynamically constructed command
    eval $cmd

    # Check if the import succeeded
    if [ $? -ne 0 ]; then
        echo "❌ Error: Failed to import image ${repository_image}:${src_tag} to ${private_registry}/${destination}:${dest_tag}" >&2
        return 1
    fi

    echo "✅ Image ${private_registry}/${destination}:${dest_tag} imported successfully" >&2
    return 0
}

# ===================================
# Main Script Logic
# ===================================
main() {
    echo "========================================"
    echo "CodeCollection Image Sync"
    echo "========================================"
    echo "Catalog: ${REGISTRY_CATALOG_URL}/api/v1/catalog/codecollections"
    echo "REF=${REF}"
    echo "Private Registry: ${private_registry}"
    echo "Repository Path: ${REGISTRY_REPOSITORY_PATH}"
    echo "Sync Images: ${SYNC_IMAGES}"
    echo ""

    local catalog_json
    catalog_json=$(fetch_catalog_entries) || {
        echo "❌ Failed to fetch catalog from ${REGISTRY_CATALOG_URL}"
        exit 1
    }

    local updates_json="["
    local has_updates=false

    while IFS= read -r slug; do
        [[ -z "$slug" ]] && continue

        echo "========================================="
        echo "Processing catalog entry: $slug"

        local resolved
        resolved=$(resolve_collection_image "$slug" 2>/dev/null || echo "")
        if [[ -z "$resolved" ]]; then
            echo "⚠️  Unable to resolve image for slug=${slug}, ref=${REF}"
            echo ""
            continue
        fi

        local source_registry source_tag
        source_registry=$(echo "$resolved" | jq -r '.image_registry // empty')
        source_tag=$(echo "$resolved" | jq -r '.image_tag // empty')

        if [[ -z "$source_registry" || -z "$source_tag" ]]; then
            echo "⚠️  Catalog resolve response missing image_registry/image_tag for ${slug}"
            echo ""
            continue
        fi

        local dest="${REGISTRY_REPOSITORY_PATH}/${slug}"
        echo "Source: ${source_registry}:${source_tag}"
        echo "Destination: ${private_registry}/${dest}:${source_tag}"

        if ! tag_exists_in_acr "$dest" "$source_tag"; then
            echo "🔄 Flagging $dest:$source_tag as needing an update."

            if [[ "$has_updates" == "true" ]]; then
                updates_json+=","
            fi
            updates_json+="{\"slug\": \"$slug\", \"source\": \"$source_registry:$source_tag\", \"destination\": \"$private_registry/$dest:$source_tag\"}"
            has_updates=true

            if [[ "$SYNC_IMAGES" == "true" ]]; then
                echo "🚀 Syncing image..."
                if copy_image "$source_registry" "$source_tag" "$dest" "$source_tag"; then
                    echo "✅ Image $private_registry/$dest:$source_tag synced successfully"
                else
                    echo "❌ Failed to sync image $private_registry/$dest:$source_tag"
                fi
            fi
        else
            echo "✅ Tag $dest:$source_tag already exists in ACR - skipping."
        fi
        echo ""
    done < <(echo "$catalog_json" | jq -r '.[] | select(.visibility == "public") | .slug')

    # Finalize JSON output
    updates_json+="]"
    echo "$updates_json" | jq '.' > "$OUTPUT_JSON" 2>/dev/null || echo "$updates_json" > "$OUTPUT_JSON"

    echo "========================================"
    echo "Summary"
    echo "========================================"
    local update_count
    update_count=$(echo "$updates_json" | jq 'length' 2>/dev/null || echo "0")
    echo "Total images needing update: $update_count"
    echo "Image update list written to: $OUTPUT_JSON"
    echo ""

    if [[ "$has_updates" == "false" ]]; then
        echo "✅ All CodeCollection images are up-to-date!"
    elif [[ "$SYNC_IMAGES" == "true" ]]; then
        echo "✅ Image sync completed!"
    else
        echo "ℹ️  To sync images, set SYNC_IMAGES=true"
    fi
}

# Execute the main script
main
