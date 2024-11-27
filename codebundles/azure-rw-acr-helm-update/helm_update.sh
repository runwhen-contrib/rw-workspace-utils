#!/bin/bash

# Constants
OUTPUT_DIR=/robot_logs/az

HELM_RELEASE="runwhen-local"
NAMESPACE="runwhen-local-beta"
CLONE_DIR="$OUTPUT_DIR/helm-chart"
RENDERED_MANIFESTS="$OUTPUT_DIR/rendered-manifests.yaml"
OUTPUT_JSON="$OUTPUT_DIR/images_to_update.json"
REGISTRY_LOGIN="runwhensandboxacr.azurecr.io"

# Cleanup
cleanup() {
    rm -rf "$CLONE_DIR" "$RENDERED_MANIFESTS" "$OUTPUT_JSON"
}
trap cleanup EXIT

# Fetch Helm chart
fetch_helm_chart() {
    echo "Fetching Helm chart for release '$HELM_RELEASE'..."
    mkdir -p "$CLONE_DIR"
    helm pull runwhen-local --repo https://runwhen-contrib.github.io/helm-charts --untar --untardir "$CLONE_DIR"
    if [[ $? -ne 0 ]]; then
        echo "Failed to fetch Helm chart. Ensure it exists in the specified repo."
        exit 1
    fi
    echo "Helm chart fetched successfully."
}

# Retrieve rendered manifests
retrieve_rendered_manifests() {
    echo "Retrieving rendered manifests for release '$HELM_RELEASE'..."
    helm get manifest "$HELM_RELEASE" --namespace "$NAMESPACE" > "$RENDERED_MANIFESTS"
    if [[ $? -ne 0 ]]; then
        echo "Failed to retrieve rendered manifests. Ensure the release exists."
        exit 1
    fi
    echo "Rendered manifests saved to $RENDERED_MANIFESTS."
}

# Parse images from templates and manifests
parse_images() {
    echo "Parsing images from templates and manifests..."

    # Extract images from templates
    echo "Processing templates..."
    find "$CLONE_DIR" -type f -name "*.yaml" | while read -r file; do
        yq eval '.. | select(has("image")) | .image' "$file" 2>/dev/null | grep -Eo '^[^:]+:[^"]+$' | while read -r image; do
            echo "Found image in templates: $image"
            images["$image"]="$file"
        done
    done

    # Extract images from rendered manifests
    echo "Processing rendered manifests..."
    yq eval '.. | select(has("image")) | .image' "$RENDERED_MANIFESTS" 2>/dev/null | grep -Eo '^[^:]+:[^"]+$' | while read -r image; do
        echo "Found image in manifests: $image"
        images["$image"]="rendered"
    done
}

# Validate image format
is_valid_image() {
    local image=$1
    [[ $image =~ ^[a-zA-Z0-9.-]+/[a-zA-Z0-9._/-]+:[a-zA-Z0-9._-]+$ ]]
}

# Check for newer tags in the registry
check_for_newer_tags() {
    echo "Checking for newer tags in registry '$REGISTRY'..."
    for image in "${!images[@]}"; do
        if ! is_valid_image "$image"; then
            echo "Skipping invalid image: $image"
            continue
        fi

        local registry repo tag
        read -r registry repo tag <<<"$(echo "$image" | awk -F'[/:]' '{print $1, $2"/"$3, $NF}')"

        if [[ $registry != $REGISTRY ]]; then
            echo "Skipping non-registry image: $image"
            continue
        fi

        echo "Checking repository $repo for newer tags..."
        tags=$(az acr repository show-tags --name "${registry%%.*}" --repository "$repo" --query "[]" -o tsv 2>/dev/null)
        if [[ $? -ne 0 || -z $tags ]]; then
            echo "Failed to fetch tags for $repo."
            continue
        fi

        for t in $tags; do
            if [[ $t > $tag ]]; then
                echo "Newer tag found for $image: $t"
                images_to_update["$image"]="$t"
                break
            fi
        done
    done
}

# Generate upgrade commands
generate_upgrade_commands() {
    echo "Generating Helm upgrade commands..."
    > "$OUTPUT_JSON"

    for image in "${!images_to_update[@]}"; do
        new_tag=${images_to_update[$image]}
        path=${images["$image"]}
        echo "{\"image\": \"$image\", \"new_tag\": \"$new_tag\", \"path\": \"$path\"}" >> "$OUTPUT_JSON"

        if [[ -n $path && $path != "rendered" ]]; then
            echo "helm upgrade $HELM_RELEASE $CLONE_DIR --namespace $NAMESPACE --reuse-values --set $path.image.tag=$new_tag"
        else
            echo "Rendered manifest images cannot be dynamically updated via Helm."
        fi
    done
}

# Main logic
fetch_helm_chart
retrieve_rendered_manifests
declare -A images
declare -A images_to_update
parse_images
check_for_newer_tags
generate_upgrade_commands

echo "Image update checks complete. Results saved to $OUTPUT_JSON."
