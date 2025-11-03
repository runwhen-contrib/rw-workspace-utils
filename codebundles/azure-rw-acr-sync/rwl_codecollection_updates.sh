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
IMAGE_ARCHITECTURE=${IMAGE_ARCHITECTURE:-"amd64"} # Default architecture

# CodeCollection tagging configuration
REF="${REF:-main}"
LATEST_TAG="${REF}-latest"
REF_HASH_REGEX="^${REF}-[0-9a-f]{7,}$"
desired_architecture="$IMAGE_ARCHITECTURE"
declare -a tag_exclusion_list=("main-latest" "tester")

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
# CodeCollection Image Definitions
# ===================================
codecollection_images=$(cat <<EOF
{
    "us-west1-docker.pkg.dev/runwhen-nonprod-beta/public-images/runwhen-contrib-rw-cli-codecollection": {
        "destination": "$REGISTRY_REPOSITORY_PATH/runwhen-contrib-rw-cli-codecollection"
    },
    "us-west1-docker.pkg.dev/runwhen-nonprod-beta/public-images/runwhen-contrib-rw-public-codecollection": {
        "destination": "$REGISTRY_REPOSITORY_PATH/runwhen-contrib-rw-public-codecollection"
    },
    "us-west1-docker.pkg.dev/runwhen-nonprod-beta/public-images/runwhen-contrib-rw-generic-codecollection": {
        "destination": "$REGISTRY_REPOSITORY_PATH/runwhen-contrib-rw-generic-codecollection"
    },
    "us-west1-docker.pkg.dev/runwhen-nonprod-beta/public-images/runwhen-contrib-rw-workspace-utils": {
        "destination": "$REGISTRY_REPOSITORY_PATH/runwhen-contrib-rw-workspace-utils"
    },
    "us-west1-docker.pkg.dev/runwhen-nonprod-beta/public-images/runwhen-contrib-azure-c7n-codecollection": {
        "destination": "$REGISTRY_REPOSITORY_PATH/runwhen-contrib-azure-c7n-codecollection"
    }
}
EOF
)

# ===================================
# Tool Checks
# ===================================
for tool in curl jq yq awk; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "❌ Missing tool: $tool"
        exit 1
    fi
done

# ===================================
# Helper Functions
# ===================================

# Check if tag is in exclusion list
is_excluded_tag() {
    local tag=$1
    for excluded in "${tag_exclusion_list[@]}"; do
        [[ "$tag" == "$excluded" ]] && return 0
    done
    return 1
}

# Check if tag has architecture prefix (amd64- or arm64-)
is_arch_prefixed_tag() {
    [[ "$1" =~ ^(amd64|arm64)- ]]
}

# Get repository base URL for API calls
get_repo_base() {
    local img=$1
    if [[ $img == *.pkg.dev/* ]]; then
        echo "https://${img%%/*}/v2/${img#*pkg.dev/}"
    elif [[ $img == us-docker.pkg.dev/* ]]; then
        echo "https://us-docker.pkg.dev/v2/${img#*pkg.dev/}"
    elif [[ $img == us-west1-docker.pkg.dev/* ]]; then
        echo "https://us-west1-docker.pkg.dev/v2/${img#*pkg.dev/}"
    elif [[ $img == ghcr.io/* ]]; then
        echo "https://ghcr.io/v2/${img#ghcr.io/}"
    elif [[ $img == docker.io/* ]]; then
        echo "https://registry-1.docker.io/v2/${img#docker.io/}"
    elif [[ $img == *.azurecr.io/* ]]; then
        echo "https://${img%%/*}/v2/${img#*.azurecr.io/}"
    else
        echo ""
    fi
}

# Get architecture-specific child digest or fallback to header digest
get_arch_child_digest() {
    local repo_base=$1
    local tag=$2
    local arch=${3:-amd64}
    local json child

    json=$(curl -s -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.v2+json" \
        "${repo_base}/manifests/${tag}" 2>/dev/null || echo "")

    if [[ -z "$json" ]]; then
        echo ""
        return 1
    fi

    # Try to extract arch-specific child digest from manifest list
    child=$(echo "$json" | jq -r --arg arch "$arch" '.manifests[]? | select(.platform.architecture==$arch) | .digest' 2>/dev/null | head -n1)
    if [[ -n "$child" && "$child" != "null" ]]; then
        echo "$child"
        return 0
    fi

    # Fallback: get digest from header
    curl -sI -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
        "${repo_base}/manifests/${tag}" 2>/dev/null \
        | awk -F': ' '/Docker-Content-Digest/ {print $2}' | tr -d $'\r'
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

# Find best tag for codecollection images using REF-based strategy with digest matching
find_codecollection_tag() {
    local repo=$1
    local repo_base=$2
    
    echo "🔍 Checking CodeCollection image with REF-based tagging strategy..." >&2
    echo "Repository: $repo" >&2
    
    # Fetch all tags
    local tag_list
    tag_list=$(curl -sL "${repo_base}/tags/list" 2>/dev/null | jq -r '.tags[]?' || echo "")
    
    if [[ -z "$tag_list" ]]; then
        echo "⚠️  No tags found for $repo" >&2
        echo ""
        return 1
    fi
    
    # Check if LATEST_TAG exists
    if ! grep -qx "${LATEST_TAG}" <<<"$tag_list"; then
        echo "⚠️  No ${LATEST_TAG} found in repository" >&2
        echo ""
        return 1
    fi
    
    # Get digest for LATEST_TAG
    local latest_digest
    latest_digest=$(get_arch_child_digest "$repo_base" "$LATEST_TAG" "$desired_architecture")
    
    if [[ -z "$latest_digest" ]]; then
        echo "⚠️  Unable to resolve ${desired_architecture} child digest for ${LATEST_TAG}" >&2
        echo ""
        return 1
    fi
    
    echo "DEBUG: ${LATEST_TAG} (${desired_architecture}) digest = ${latest_digest}" >&2
    
    local selected_tag=""
    
    # Strategy 1: Prefer ref-hash sibling with same digest (exclude arch-prefixed tags)
    while read -r t; do
        [[ -z "$t" ]] && continue
        [[ "$t" == "$LATEST_TAG" ]] && continue
        is_excluded_tag "$t" && continue
        is_arch_prefixed_tag "$t" && { echo "DEBUG: skip arch-prefixed $t" >&2; continue; }
        [[ ! "$t" =~ $REF_HASH_REGEX ]] && continue
        
        local t_digest
        t_digest=$(get_arch_child_digest "$repo_base" "$t" "$desired_architecture")
        [[ -z "$t_digest" ]] && continue
        
        echo "DEBUG: compare $t → $t_digest" >&2
        if [[ "$t_digest" == "$latest_digest" ]]; then
            selected_tag="$t"
            break
        fi
    done <<<"$tag_list"
    
    # Strategy 2: Fallback to any non-arch, non-excluded sibling with same digest
    if [[ -z "$selected_tag" ]]; then
        while read -r t; do
            [[ -z "$t" ]] && continue
            [[ "$t" == "$LATEST_TAG" ]] && continue
            is_excluded_tag "$t" && continue
            is_arch_prefixed_tag "$t" && continue
            
            local t_digest
            t_digest=$(get_arch_child_digest "$repo_base" "$t" "$desired_architecture")
            [[ -z "$t_digest" ]] && continue
            
            if [[ "$t_digest" == "$latest_digest" ]]; then
                selected_tag="$t"
                break
            fi
        done <<<"$tag_list"
    fi
    
    if [[ -z "$selected_tag" ]]; then
        echo "⚠️  ${LATEST_TAG} exists but no sibling on same ${desired_architecture} digest — skipping" >&2
        echo ""
        return 1
    fi
    
    echo "✅ Using ${selected_tag} (same ${desired_architecture} child digest as ${LATEST_TAG})" >&2
    echo "$selected_tag"
}

# ===================================
# Main Script Logic
# ===================================
main() {
    echo "========================================"
    echo "CodeCollection Image Sync"
    echo "========================================"
    echo "REF=${REF} (using ${LATEST_TAG} for tagging strategy)"
    echo "Architecture: ${desired_architecture}"
    echo "Private Registry: ${private_registry}"
    echo "Repository Path: ${REGISTRY_REPOSITORY_PATH}"
    echo "Sync Images: ${SYNC_IMAGES}"
    echo ""
    
    local updates_json="["
    local has_updates=false
    
    for repository_image in $(echo "$codecollection_images" | jq -r 'keys[]'); do
        echo "========================================="
        echo "Processing: $repository_image"
        
        dest=$(echo "$codecollection_images" | jq -r --arg repo "$repository_image" '.[$repo].destination')
        repo_base=$(get_repo_base "$repository_image")
        
        if [[ -z "$repo_base" ]]; then
            echo "❌ Unsupported registry for $repository_image"
            continue
        fi
        
        # Find appropriate tag using REF-based strategy
        selected_tag=$(find_codecollection_tag "$repository_image" "$repo_base")
        
        if [[ -z "$selected_tag" ]]; then
            echo "⚠️  No suitable tag found for $repository_image"
            echo ""
            continue
        fi
        
        # Check if the repository or tag exists in ACR
        if ! tag_exists_in_acr "$dest" "$selected_tag"; then
            echo "🔄 Flagging $dest:$selected_tag as needing an update."
            
            # Add to JSON output
            if [[ "$has_updates" == "true" ]]; then
                updates_json+=","
            fi
            updates_json+="{\"source\": \"$repository_image:$selected_tag\", \"destination\": \"$private_registry/$dest:$selected_tag\"}"
            has_updates=true
            
            if [[ "$SYNC_IMAGES" == "true" ]]; then
                echo "🚀 Syncing image..."
                if copy_image "$repository_image" "$selected_tag" "$dest" "$selected_tag"; then
                    echo "✅ Image $private_registry/$dest:$selected_tag synced successfully"
                else
                    echo "❌ Failed to sync image $private_registry/$dest:$selected_tag"
                fi
            fi
        else
            echo "✅ Tag $dest:$selected_tag already exists in ACR - skipping."
        fi
        echo ""
    done
    
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
