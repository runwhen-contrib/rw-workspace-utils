import subprocess
import yaml
import json
import re
from typing import Dict, List, Optional
import requests
from azure.identity import DefaultAzureCredential
from azure.containerregistry import ContainerRegistryClient

def pull_helm_chart(chart_name: str, repo_url: str) -> str:
    """
    Pull Helm chart from the specified repository
    
    :param chart_name: Name of the chart to pull
    :param repo_url: URL of the Helm chart repository
    :return: Path to the pulled Helm chart
    """
    try:
        import tempfile
        import os
        chart_dir = tempfile.mkdtemp(prefix='helm-chart-')
        
        # Pull the Helm chart using the correct command
        cmd = [
            'helm', 'pull', 
            chart_name,
            '--repo', repo_url,
            '--untar', 
            '--destination', chart_dir
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        if result.returncode != 0:
            raise Exception(f"Failed to pull Helm chart: {result.stderr.strip()}")
        
        # Verify the chart was pulled successfully
        chart_contents = os.listdir(chart_dir)
        if not chart_contents:
            raise Exception("No content found in the Helm chart directory.")
        
        return os.path.join(chart_dir, chart_contents[0])
    
    except Exception as e:
        print(f"Error pulling Helm chart: {e}")
        raise

def get_release_images(release_name: str, namespace: str) -> List[str]:
    """
    Get images currently deployed in the Helm release
    
    :param release_name: Name of the Helm release
    :param namespace: Kubernetes namespace
    :return: List of images in the release
    """
    try:
        # Get release manifest
        cmd = [
            'helm', 'get', 'manifest', 
            release_name, 
            '-n', namespace
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        if result.returncode != 0:
            raise Exception(f"Error retrieving release manifest: {result.stderr}")
        
        # Extract images using regex
        images = set(re.findall(r'image:\s*([^\s]+)', result.stdout))
        
        return list(images)
    
    except Exception as e:
        print(f"Failed to get release images: {e}")
        return []

def initialize_acr_client(registry_details: str):
    """
    Initialize Azure Container Registry client
    
    :param registry_details: Registry details (format: "registry.azurecr.io,subscription_id")
    :return: Azure Container Registry client
    """
    try:
        # Parse registry details
        registry_url, _ = registry_details.split(',')
        
        # Use DefaultAzureCredential for authentication
        credential = DefaultAzureCredential()
        
        return ContainerRegistryClient(
            endpoint=f"https://{registry_url}", 
            credential=credential
        )
    except Exception as e:
        print(f"Failed to initialize ACR client: {e}")
        return None

def check_acr_image_updates(registry_client, image_name: str, current_tag: str, registry_url: str) -> Optional[Dict]:
    try:
        repository = image_name.split(f"{registry_url}/")[1]

        # Attempt to list tags
        try:
            tags = [tag.name for tag in registry_client.list_tags(repository)]
        except AttributeError:
            # Fallback to REST API
            from azure.identity import DefaultAzureCredential
            import requests

            credential = DefaultAzureCredential()
            token = credential.get_token("https://management.azure.com/.default").token

            headers = {
                "Authorization": f"Bearer {token}",
                "Accept": "application/json"
            }

            response = requests.get(
                f"https://{registry_url}/acr/v1/{repository}/_tags",
                headers=headers
            )

            if response.status_code == 200:
                tags = [tag["name"] for tag in response.json().get("tags", [])]
            else:
                raise Exception(f"Failed to fetch tags: {response.status_code} {response.text}")

        if current_tag not in tags:
            return {
                "current_tag": current_tag,
                "available_tags": tags,
                "recommended_tag": tags[-1] if tags else None
            }

        return None

    except Exception as e:
        print(f"ACR update check failed for {image_name}: {e}")
        return None


def find_image_path_in_values(chart_path: str, image: str) -> Optional[str]:
    """
    Find the path to update in values.yaml for a specific image
    
    :param chart_path: Path to the Helm chart directory
    :param image: Base image name to locate
    :return: Path in values.yaml to update
    """
    try:
        with open(f'{chart_path}/values.yaml', 'r') as f:
            values = yaml.safe_load(f)
        
        def find_image_path(data, target_image, current_path=''):
            if isinstance(data, dict):
                for key, value in data.items():
                    new_path = f"{current_path}.{key}" if current_path else key
                    if isinstance(value, str) and target_image in value:
                        return new_path
                    
                    result = find_image_path(value, target_image, new_path)
                    if result:
                        return result
            
            return None
        
        return find_image_path(values, image.split('/')[-1])
    
    except Exception as e:
        print(f"Error finding image path: {e}")
        return None

def generate_helm_update_command(
    release_name: str, 
    namespace: str, 
    chart_path: str, 
    image: str, 
    new_tag: str
) -> str:
    """
    Generate Helm upgrade command
    
    :param release_name: Name of the Helm release
    :param namespace: Kubernetes namespace
    :param chart_path: Path to Helm chart
    :param image: Base image name
    :param new_tag: New image tag
    :return: Helm upgrade command
    """
    # Find the path in values.yaml
    update_path = find_image_path_in_values(chart_path, image)
    
    if not update_path:
        raise ValueError(f"Could not find update path for image {image}")
    
    return (
        f"helm upgrade {release_name} {chart_path} "
        f"--set {update_path}={image}:{new_tag} "
        f"-n {namespace}"
    )

def update_helm_release_images(
    repo_url: str, 
    chart_name: str,
    release_name: str, 
    namespace: str, 
    registry_type: str, 
    registry_details: str
) -> Dict:
    """
    Update Helm release images
    
    :param repo_url: URL of the Helm chart repository
    :param chart_name: Name of the chart to pull
    :param release_name: Name of the Helm release
    :param namespace: Kubernetes namespaceACR
    :param registry_type: Type of container registry (e.g., 'acr')
    :param registry_details: Registry-specific connection details
    :return: Dictionary of update results
    """
    # Pull Helm chart
    chart_path = pull_helm_chart(chart_name, repo_url)
    
    # Get current images
    current_images = get_release_images(release_name, namespace)
    
    # Prepare update results
    update_results = {
        'updates_available': False,
        'update_details': []
    }
    
    # Initialize registry client if ACR
    registry_client = None
    registry_url = None
    if registry_type.lower() == 'acr':
        registry_client = initialize_acr_client(registry_details)
        registry_url = registry_details.split(',')[0]
    
    # Check for updates
    for image_full in current_images:
        try:
            # Parse image name and tag
            parts = image_full.split(':')
            image_name = parts[0]
            current_tag = parts[1] if len(parts) > 1 else 'latest'
            
            # Check updates based on registry type
            update_info = None
            if registry_type.lower() == 'acr' and registry_client:
                update_info = check_acr_image_updates(
                    registry_client, 
                    image_name, 
                    current_tag, 
                    registry_url
                )
            
            # Process updates
            if update_info:
                # Generate update command
                update_cmd = generate_helm_update_command(
                    release_name,
                    namespace,
                    chart_path,
                    image_name,
                    update_info['recommended_tag']
                )
                
                update_results['updates_available'] = True
                update_results['update_details'].append({
                    'image': image_full,
                    'current_tag': update_info['current_tag'],
                    'recommended_tag': update_info['recommended_tag'],
                    'update_command': update_cmd
                })
        
        except Exception as e:
            print(f"Could not process update for {image_full}: {e}")
    
    return update_results