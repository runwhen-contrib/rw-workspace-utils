#!/bin/bash

# Variables
export REGISTRY_NAME="${REGISTRY_NAME:-myacr.azurecr.io}"  # Full Azure Container Registry URL
export NAMESPACE="${NAMESPACE:-runwhen-local}"  # Kubernetes namespace
export HELM_RELEASE="${HELM_RELEASE:-runwhen-local}"  # Helm release name
export CONTEXT="${CONTEXT:-cluster1}"  # Kubernetes context to use
export MAPPING_FILE="image_mappings.yaml"  # Generic mapping file
export HELM_APPLY_UPGRADE="${HELM_APPLY_UPGRADE:-false}"  # Set to "true" to apply upgrades
export REGISTRY_REPOSITORY_PATH="${REGISTRY_REPOSITORY_PATH:-runwhen}"  # Default repository root path

export HELM_REPO_URL="${HELM_REPO_URL:-https://runwhen-contrib.github.io/helm-charts}"
export HELM_REPO_NAME="${HELM_REPO_NAME:-runwhen-contrib}"
export HELM_CHART_NAME="${HELM_CHART_NAME:-runwhen-local}"
export WORKDIR="${WORKDIR:-./helm_work}" 

# Clean temp update file
rm -rf $WORKDIR || true
mkdir -p $WORKDIR
cp ../$MAPPING_FILE . || true

# Function to parse image into components
parse_image() {
    local image=$1
    local registry repo tag

    registry=$(echo "$image" | cut -d '/' -f 1)
    repo=$(echo "$image" | cut -d '/' -f 2- | cut -d ':' -f 1)
    tag=$(echo "$image" | awk -F ':' '{print $NF}')

    echo "$registry" "$repo" "$tag"
}

# Resolve ${REGISTRY_REPOSITORY_PATH}
resolve_REGISTRY_REPOSITORY_PATH() {
    local input=$1
    echo "$input" | sed "s|\$REGISTRY_REPOSITORY_PATH|$REGISTRY_REPOSITORY_PATH|g" | xargs
}

# Construct --set flags
construct_set_flags() {
    local mapping_file=$1
    local updated_images=$2
    local set_flags=""
    local resolved_mapping_file=$(mktemp)

    # Resolve placeholders in mapping file
    sed "s|\$REGISTRY_REPOSITORY_PATH|$REGISTRY_REPOSITORY_PATH|g" "$mapping_file" > "$resolved_mapping_file"

    while IFS= read -r line; do
        repo=$(echo "$line" | awk '{print $1}')
        tag=$(echo "$line" | awk '{print $2}')

        if [[ -z "$repo" || -z "$tag" ]]; then
            continue
        fi

        normalized_repo=$(resolve_REGISTRY_REPOSITORY_PATH "$repo")
        set_path=$(yq eval ".images[] | select(.image == \"$normalized_repo\") | .set_path" "$resolved_mapping_file" 2>/dev/null)
        if [[ -n "$set_path" ]]; then
            set_flags+="--set $set_path=$tag "
        else
            echo "No mapping found for repository '$normalized_repo'. Skipping."
        fi
    done <<< "$updated_images"

    # Cleanup
    rm -f "$resolved_mapping_file"

    echo "$set_flags"
}

# Main script logic
echo "Extracting images for Helm release '$HELM_RELEASE' in namespace '$NAMESPACE' on context '$CONTEXT'..."

helm_images=$(helm get manifest "$HELM_RELEASE" -n "$NAMESPACE" --kube-context "$CONTEXT" | grep -oP '(?<=image: ).*' | sed 's/"//g' | sort -u)
kubectl_images=$(kubectl get pods -n "$NAMESPACE" --context "$CONTEXT" -o json | jq -r '.items[].spec.containers[].image' | sort -u)

# Combine and deduplicate images
all_images=$(echo -e "$helm_images\n$kubectl_images" | sort -u)

if [[ -z "$all_images" ]]; then
    echo "No images found for Helm release '$HELM_RELEASE' or running pods in namespace '$NAMESPACE'."
    exit 1
fi

echo "Found images:"
echo "$all_images"

updated_images=""
while IFS= read -r image; do
    echo "Checking image $image for newer versions..."
    read -r registry repo current_tag <<< "$(parse_image "$image")"

    # Fetch latest tag
    tag_list=$(az acr repository show-tags --name "${REGISTRY_NAME%%.*}" --repository "$repo" --query "[]" -o tsv 2>/dev/null)
    latest_tag=$(echo "$tag_list" | sort -V | tail -n 1)

    if [[ "$latest_tag" != "$current_tag" ]]; then
        echo "Updating $repo from $current_tag to $latest_tag"
        if [[ -n "$repo" && -n "$latest_tag" ]]; then
            updated_images+="$repo $latest_tag"$'\n'
        fi
    fi
done <<< "$all_images"

echo "$updated_images" >> $WORKDIR/update_images

if [[ -n "$updated_images" ]]; then
    echo "Constructing Helm upgrade command..."
    set_flags=$(construct_set_flags "$MAPPING_FILE" "$updated_images")
    helm_upgrade_command="helm upgrade $HELM_RELEASE $HELM_REPO_NAME/$HELM_CHART_NAME -n $NAMESPACE --kube-context $CONTEXT --reuse-values $set_flags"
    if [[ "$HELM_APPLY_UPGRADE" == "true" ]]; then
        echo "Applying Helm upgrade..."
        helm repo add $HELM_REPO_NAME $HELM_REPO_URL
        $helm_upgrade_command
    else
        echo "Helm upgrade command (not applied):"
        echo "$helm_upgrade_command"
        echo "true: $helm_upgrade_command" >> $WORKDIR/helm_update_required
    fi
else
    echo "No updates required. Helm release '$HELM_RELEASE' is up-to-date."
fi
