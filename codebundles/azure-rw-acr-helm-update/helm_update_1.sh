#!/bin/bash

# Variables (Replace with your values)
REGISTRY_NAME="runwhensandboxacr.azurecr.io"  # Full Azure Container Registry URL
NAMESPACE="runwhen-local-beta"  # Kubernetes namespace
HELM_RELEASE="runwhen-local"  # Helm release name
CONTEXT="cluster1"  # Kubernetes context to use

# Function to get images from Helm manifests
extract_images_from_helm() {
    helm get manifest "$HELM_RELEASE" -n "$NAMESPACE" --kube-context "$CONTEXT" \
    | grep -oP '(?<=image: ).*' \
    | sed 's/"//g' \
    | sort -u
}

# Function to get images from running pods in the cluster
extract_images_from_kubectl() {
    kubectl get pods -n "$NAMESPACE" --context "$CONTEXT" -o json \
    | jq -r '.items[].spec.containers[].image' \
    | sort -u
}

# Function to parse image into components
parse_image() {
    local image=$1
    local registry repo tag

    registry=$(echo "$image" | cut -d '/' -f 1)
    repo=$(echo "$image" | cut -d '/' -f 2- | cut -d ':' -f 1)
    tag=$(echo "$image" | awk -F ':' '{print $NF}')

    echo "$registry" "$repo" "$tag"
}

# Function to check if a newer image exists based on tags
check_for_newer_image() {
    local image=$1
    read -r registry repo tag <<< "$(parse_image "$image")"

    if [[ "$registry" != "$REGISTRY_NAME" ]]; then
        echo "Skipping image $image (not in $REGISTRY_NAME)."
        return 1
    fi

    echo "Checking repository $repo in registry $REGISTRY_NAME for newer tags..."

    # Try to fetch tags using `show-tags`
    tag_list=$(az acr repository show-tags --name "${REGISTRY_NAME%%.*}" --repository "$repo" --query "[]" -o tsv 2>/dev/null)

    if [[ -z "$tag_list" ]]; then
        echo "No tags found for repository $repo."
        return 1
    fi

    # Check if the current tag exists in the tag list
    if ! echo "$tag_list" | grep -q "$tag"; then
        echo "Current tag $tag not found in repository $repo."
        return 1
    fi

    # Check if newer tags exist
    echo "Found tags for $repo: $tag_list"
    for t in $tag_list; do
        if [[ "$t" > "$tag" ]]; then
            echo "Newer tag found: $t"
            return 0
        fi
    done

    echo "No newer tags found for $repo:$tag."
    return 1
}

# Main script logic
echo "Extracting images for Helm release '$HELM_RELEASE' in namespace '$NAMESPACE' on context '$CONTEXT'..."

helm_images=$(extract_images_from_helm)
kubectl_images=$(extract_images_from_kubectl)

# Combine and deduplicate images
all_images=$(echo -e "$helm_images\n$kubectl_images" | sort -u)

if [[ -z "$all_images" ]]; then
    echo "No images found for Helm release '$HELM_RELEASE' or running pods in namespace '$NAMESPACE'."
    exit 1
fi

echo "Found images:"
echo "$all_images"

needs_update=false
while IFS= read -r image; do
    echo "Checking image $image for newer versions..."
    if check_for_newer_image "$image"; then
        needs_update=true
    fi
done <<< "$all_images"

if $needs_update; then
    echo "Helm release '$HELM_RELEASE' has newer images available. Consider updating."
    exit 0
else
    echo "Helm release '$HELM_RELEASE' is up-to-date."
    exit 0
fi
