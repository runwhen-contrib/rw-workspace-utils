#!/bin/bash

# Variables (Replace with your values)
ACR_NAME="myacr"  # Azure Container Registry name
NAMESPACE="default"  # Kubernetes namespace
HELM_RELEASE="myrelease"  # Helm release name

# Function to extract images from Helm release
extract_images() {
    helm get values "$HELM_RELEASE" -n "$NAMESPACE" --all \
    | yq eval '.image | .repository + ":" + .tag' -
}

# Function to check if a newer image exists
check_for_newer_image() {
    local image=$1
    local repo tag registry

    # Split the image into registry, repo, and tag
    registry=$(echo "$image" | cut -d '/' -f 1)
    repo=$(echo "$image" | cut -d '/' -f 2 | cut -d ':' -f 1)
    tag=$(echo "$image" | cut -d ':' -f 2)

    # List tags from the ACR
    available_tags=$(az acr repository show-tags \
        --name "$ACR_NAME" \
        --repository "$repo" \
        --query "[]" \
        -o tsv)

    # Compare the tags to find newer ones
    for available_tag in $available_tags; do
        if [[ "$available_tag" > "$tag" ]]; then
            echo "$repo:$available_tag (newer than $tag)"
            return 0
        fi
    done
    return 1
}

# Extract images and check for updates
echo "Checking Helm release '$HELM_RELEASE' in namespace '$NAMESPACE' for updates..."
images=$(extract_images)

if [[ -z "$images" ]]; then
    echo "No images found for Helm release '$HELM_RELEASE'."
    exit 1
fi

needs_update=false
echo "Found images:"
echo "$images"

while IFS= read -r image; do
    echo "Checking image $image for newer versions..."
    if check_for_newer_image "$image"; then
        echo "Newer image found for $image!"
        needs_update=true
    else
        echo "No newer image found for $image."
    fi
done <<< "$images"

if $needs_update; then
    echo "Helm release '$HELM_RELEASE' needs an update."
    exit 0
else
    echo "Helm release '$HELM_RELEASE' is up-to-date."
    exit 0
fi
