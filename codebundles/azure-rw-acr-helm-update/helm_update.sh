#!/bin/bash

set -euo pipefail

# ===================================
# Configuration Variables
# ===================================
REGISTRY_NAME="${REGISTRY_NAME:-myacr.azurecr.io}"  # Full Azure Container Registry URL
NAMESPACE="${NAMESPACE:-runwhen-local}"  # Kubernetes namespace
HELM_RELEASE="${HELM_RELEASE:-runwhen-local}"  # Helm release name
CONTEXT="${CONTEXT:-cluster1}"  # Kubernetes context to use
MAPPING_FILE="image_mappings.yaml"  # Generic mapping file
HELM_APPLY_UPGRADE="${HELM_APPLY_UPGRADE:-false}"  # Set to "true" to apply upgrades
REGISTRY_REPOSITORY_PATH="${REGISTRY_REPOSITORY_PATH:-runwhen}"  # Default repository root path
HELM_REPO_URL="${HELM_REPO_URL:-https://runwhen-contrib.github.io/helm-charts}"
HELM_REPO_NAME="${HELM_REPO_NAME:-runwhen-contrib}"
HELM_CHART_NAME="${HELM_CHART_NAME:-runwhen-local}"

# CodeCollection tagging configuration
REF="${REF:-main}"
LATEST_TAG="${REF}-latest"
REF_HASH_REGEX="^${REF}-[0-9a-f]{7,}$"
desired_architecture="amd64"
declare -a tag_exclusion_list=("main-latest")

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
az acr login -n "$REGISTRY_NAME"

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

# Get image digest from ACR
get_image_digest() {
    local registry_name=$1
    local repo=$2
    local tag=$3
    local digest
    
    digest=$(az acr repository show --name "${registry_name%%.*}" \
        --image "${repo}:${tag}" \
        --query "digest" -o tsv 2>/dev/null || echo "")
    
    echo "$digest"
}

# Parse image string into components
parse_image() {
    local image=$1
    local registry repo tag
    
    # Extract registry, repo, and tag
    registry=$(echo "$image" | cut -d '/' -f 1)
    repo=$(echo "$image" | cut -d '/' -f 2- | cut -d ':' -f 1)
    tag=$(echo "$image" | rev | cut -d ':' -f 1 | rev)
    
    # Normalize scientific notation to a plain integer if necessary
    if [[ "$tag" =~ [0-9]+[eE][+-]?[0-9]+ ]]; then
        tag=$(printf "%.0f" "$tag")
    fi
    
    echo "$registry" "$repo" "$tag"
}

# Resolve ${REGISTRY_REPOSITORY_PATH} placeholder
resolve_REGISTRY_REPOSITORY_PATH() {
    local input=$1
    echo "$input" | sed "s|\$REGISTRY_REPOSITORY_PATH|$REGISTRY_REPOSITORY_PATH|g" | xargs
}

# Get category for an image from mapping file
get_image_category() {
    local repo=$1
    local resolved_mapping_file="resolved_mappings"
    
    # Temporarily resolve placeholders
    sed "s|\$REGISTRY_REPOSITORY_PATH|$REGISTRY_REPOSITORY_PATH|g" "$MAPPING_FILE" > "$resolved_mapping_file"
    
    local category
    category=$(yq eval ".images[] | select(.image == \"$repo\") | .category" "$resolved_mapping_file" 2>/dev/null | head -n1)
    
    rm -f "$resolved_mapping_file"
    
    if [[ -z "$category" || "$category" == "null" ]]; then
        echo "runwhen_local"  # Default to simpler strategy
    else
        echo "$category"
    fi
}

# Find best tag for codecollection images using REF-based strategy with digest matching
find_codecollection_tag() {
    local registry_name=$1
    local repo=$2
    local current_tag=$3
    
    echo "🔍 Checking CodeCollection image with REF-based tagging strategy..." >&2
    
    # Fetch all tags
    local tag_list
    tag_list=$(az acr repository show-tags --name "${registry_name%%.*}" \
        --repository "$repo" --orderby time_desc --query "[]" -o tsv 2>/dev/null)
    
    if [[ -z "$tag_list" ]]; then
        echo "No tags found" >&2
        echo ""
        return 1
    fi
    
    # Check if LATEST_TAG exists
    if ! grep -qx "${LATEST_TAG}" <<<"$tag_list"; then
        echo "⚠️  No ${LATEST_TAG} found, using current tag" >&2
        echo "$current_tag"
        return 0
    fi
    
    # Get digest for LATEST_TAG
    local latest_digest
    latest_digest=$(get_image_digest "$registry_name" "$repo" "$LATEST_TAG")
    
    if [[ -z "$latest_digest" ]]; then
        echo "⚠️  Unable to get digest for ${LATEST_TAG}, using current tag" >&2
        echo "$current_tag"
        return 0
    fi
    
    echo "DEBUG: ${LATEST_TAG} digest = ${latest_digest}" >&2
    
    local selected_tag=""
    
    # Strategy 1: Prefer ref-hash sibling with same digest (exclude arch-prefixed tags)
    while read -r t; do
        [[ -z "$t" ]] && continue
        [[ "$t" == "$LATEST_TAG" ]] && continue
        is_excluded_tag "$t" && continue
        is_arch_prefixed_tag "$t" && { echo "DEBUG: skip arch-prefixed $t" >&2; continue; }
        [[ ! "$t" =~ $REF_HASH_REGEX ]] && continue
        
        local t_digest
        t_digest=$(get_image_digest "$registry_name" "$repo" "$t")
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
            t_digest=$(get_image_digest "$registry_name" "$repo" "$t")
            [[ -z "$t_digest" ]] && continue
            
            if [[ "$t_digest" == "$latest_digest" ]]; then
                selected_tag="$t"
                break
            fi
        done <<<"$tag_list"
    fi
    
    if [[ -z "$selected_tag" ]]; then
        echo "⚠️  ${LATEST_TAG} exists but no sibling with matching digest — using current tag" >&2
        echo "$current_tag"
        return 0
    fi
    
    echo "✅ Found matching tag: ${selected_tag} (same digest as ${LATEST_TAG})" >&2
    echo "$selected_tag"
}

# Find best tag for runwhen_local images using simple version sorting
find_runwhen_local_tag() {
    local registry_name=$1
    local repo=$2
    local current_tag=$3
    
    echo "🔍 Checking RunWhen Local image with simple version strategy..." >&2
    
    # Fetch latest tag using version sort
    local tag_list
    tag_list=$(az acr repository show-tags --name "${registry_name%%.*}" \
        --repository "$repo" --query "[]" -o tsv 2>/dev/null)
    
    if [[ -z "$tag_list" ]]; then
        echo "No tags found" >&2
        echo ""
        return 1
    fi
    
    local latest_tag
    latest_tag=$(echo "$tag_list" | sort -V | tail -n 1)
    
    echo "Latest tag found: $latest_tag (current: $current_tag)" >&2
    echo "$latest_tag"
}

# Construct --set flags for helm upgrade command
construct_set_flags() {
    local mapping_file=$1
    local updated_images=$2
    local set_flags=""
    local resolved_mapping_file="resolved_mappings"
    
    # Resolve placeholders in mapping file
    sed "s|\$REGISTRY_REPOSITORY_PATH|$REGISTRY_REPOSITORY_PATH|g" "$mapping_file" > "$resolved_mapping_file"
    
    while IFS= read -r line; do
        repo=$(echo "$line" | awk '{print $1}')
        tag=$(echo "$line" | awk '{print $2}')
        
        if [[ -z "$repo" || -z "$tag" ]]; then
            continue
        fi
        
        normalized_repo=$(resolve_REGISTRY_REPOSITORY_PATH "$repo")
        set_path=$(yq eval ".images[] | select(.image == \"$normalized_repo\") | .set_path" "$resolved_mapping_file" 2>/dev/null | sed 's/^"//;s/"$//' | head -n1)
        
        if [[ -n "$set_path" && "$set_path" != "null" ]]; then
            set_flags+="--set $set_path=$tag "
        fi
    done <<< "$updated_images"
    
    # Cleanup
    rm -f "$resolved_mapping_file"
    
    echo "$set_flags"
}

# ===================================
# Main Script Logic
# ===================================
main() {
    echo "========================================"
    echo "RunWhen Local Helm Update Check"
    echo "========================================"
    echo "REF=${REF} (using ${LATEST_TAG} for CodeCollection images)"
    echo ""
    
    echo "Extracting images for Helm release '$HELM_RELEASE' in namespace '$NAMESPACE' on context '$CONTEXT'..."
    
    # Extract images from Helm release manifest
    local helm_images
    helm_images=$(helm get manifest "$HELM_RELEASE" -n "$NAMESPACE" --kube-context "$CONTEXT" | \
        grep -oP '(?<=image: ).*' | sed 's/"//g' | sort -u)
    
    if [[ -z "$helm_images" ]]; then
        echo "❌ No images found for Helm release '$HELM_RELEASE'."
        exit 1
    fi
    
    echo "Found images in Helm release '$HELM_RELEASE':"
    echo "$helm_images"
    echo ""
    
    local updated_images=""
    local update_count=0
    
    while IFS= read -r image; do
        echo "========================================="
        echo "Checking image: $image"
        
        read -r registry repo current_tag <<< "$(parse_image "$image")"
        echo "  Registry: $registry"
        echo "  Repository: $repo"
        echo "  Current Tag: $current_tag"
        
        # Determine image category
        local full_repo="$REGISTRY_REPOSITORY_PATH/$repo"
        local category
        category=$(get_image_category "$full_repo")
        echo "  Category: $category"
        
        # Find appropriate tag based on category
        local new_tag=""
        if [[ "$category" == "codecollection" ]]; then
            new_tag=$(find_codecollection_tag "$REGISTRY_NAME" "$repo" "$current_tag")
        else
            new_tag=$(find_runwhen_local_tag "$REGISTRY_NAME" "$repo" "$current_tag")
        fi
        
        # Check if update is needed
        if [[ -n "$new_tag" && "$new_tag" != "$current_tag" ]]; then
            echo "  ✅ UPDATE AVAILABLE: $current_tag → $new_tag"
            updated_images+="$repo $new_tag"$'\n'
            ((update_count++))
        else
            echo "  ℹ️  No update needed (current: $current_tag)"
        fi
        echo ""
    done <<< "$helm_images"
    
    # Write update count for SLI metric
    echo "$update_count" > "update_images"
    
    # Process updates
    if [[ -n "$updated_images" && "$update_count" -gt 0 ]]; then
        echo "========================================"
        echo "Updates Available: $update_count image(s)"
        echo "========================================"
        echo "Constructing Helm upgrade command..."
        
        set_flags=$(construct_set_flags "$MAPPING_FILE" "$updated_images")
        
        # Construct Helm upgrade command
        helm_upgrade_command="helm upgrade $HELM_RELEASE $HELM_REPO_NAME/$HELM_CHART_NAME -n $NAMESPACE --kube-context $CONTEXT --reuse-values $set_flags"
        
        if [[ "$HELM_APPLY_UPGRADE" == "true" ]]; then
            echo "Applying Helm upgrade..."
            helm repo add "$HELM_REPO_NAME" "$HELM_REPO_URL" || true
            helm repo update
            echo "Running command: $helm_upgrade_command"
            $helm_upgrade_command || { echo "❌ Helm upgrade failed."; exit 1; }
            echo "✅ Helm upgrade completed successfully!"
        else
            echo "Helm upgrade command (not applied):"
            echo "$helm_upgrade_command"
            echo ""
            echo "To apply this update, set HELM_APPLY_UPGRADE=true or run the command above manually."
            echo "true: $helm_upgrade_command" > "helm_update_required"
        fi
    else
        echo "========================================"
        echo "✅ No updates required"
        echo "========================================"
        echo "Helm release '$HELM_RELEASE' is up-to-date."
        echo "0" > "update_images"
    fi
}

# Run main function
main
