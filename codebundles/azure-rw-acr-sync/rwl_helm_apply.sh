
#!/bin/bash

# set -euo pipefail

# Variables
NAMESPACE="${1:?Namespace is required as the first argument}"
RELEASE_NAME="${2:?Release name is required as the second argument}"
IMAGE_UPDATES_JSON="${3:?Path to the JSON file with image updates is required as the third argument}"
TEMP_DIR=$(mktemp -d)

# Ensure cleanup of temp files
trap 'rm -rf "$TEMP_DIR"' EXIT

# Functions
function log {
    echo "[INFO] $1"
}

function check_dependencies {
    for cmd in helm yq jq; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "[ERROR] $cmd is required but not installed. Exiting."
            exit 1
        fi
    done
}

function read_current_values {
    log "Fetching current Helm values for release $RELEASE_NAME in namespace $NAMESPACE"
    helm get values "$RELEASE_NAME" --namespace "$NAMESPACE" -o yaml > "$TEMP_DIR/current_values.yaml"
}

function update_images {
    log "Updating images based on $IMAGE_UPDATES_JSON"

    while IFS= read -r line; do
        IMAGE_PATH=$(echo "$line" | jq -r '.image_path')
        NEW_IMAGE=$(echo "$line" | jq -r '.new_image')

        log "Updating image path $IMAGE_PATH to $NEW_IMAGE"
        yq eval -i "(. | select(. == \"$IMAGE_PATH\")).image = \"$NEW_IMAGE\"" "$TEMP_DIR/current_values.yaml"
    done < <(jq -c '.updates[]' "$IMAGE_UPDATES_JSON")
}

function render_updated_values {
    log "Rendering updated Helm values"
    yq eval "$TEMP_DIR/current_values.yaml" > "$TEMP_DIR/updated_values.yaml"
}

function apply_updates {
    log "Applying updated values to Helm release $RELEASE_NAME in namespace $NAMESPACE"
    helm upgrade "$RELEASE_NAME" . --namespace "$NAMESPACE" -f "$TEMP_DIR/updated_values.yaml"
}

# Main script execution
check_dependencies
read_current_values
update_images
render_updated_values
apply_updates

log "Image update process completed for release $RELEASE_NAME in namespace $NAMESPACE"
