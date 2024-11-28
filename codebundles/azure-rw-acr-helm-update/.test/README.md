export NAMESPACE=""
export REGISTRY_NAME=""
export HELM_RELEASE=""

## Infrastructure
The infrastructure (e.g. task build-infra) will deploy an AKS cluster, ready for installation of the runwhen-local helm chart. 

```
az login --use-device-code
source terraform/tf.secret
task build-infra
```
Note > Currently the private ACR registry must exist, and the AKS cluster must be manually linked to it. 
Note > When testing locally with AKS and Kubernetes, you must fetch credentials with the --admin flag (e.g. az aks get-credentials --resource-group [rg] --name [cluster_name] --overwrite-existing --admin). This is done in the terraform, however, note that it changes the context name by adding an `-admin` suffix. This is not required when testing in the RunWhen Platform, as it will properly use kubelogin. 

The next step is to use `task install-rwl-helm` to deploy the helm chart, which uses the values.yaml to set some configurations. 
```
task install-rwl-helm
```

The values.yaml contents are currently hard coded and should be parameterized if frequent testing is required. Of note, they set the images to a private registry, 
which needs to already exist and should be prepulated with runwhen images (azure-rw-acr-sync can help with this). For propet testing, 
a few versions of images should exist, such as 2 versions of runwhen-local and 2 versions of the opentelemetry collector image - this makes it 
easy to set the helm chart to install an older version, which should result in accurate upgrade recommendations from the codebundles. 

You can easily update the values.yaml as you see fit, and run the following task: 
```
task upgrade-rwl-helm
```
