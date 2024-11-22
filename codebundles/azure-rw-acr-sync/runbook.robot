*** Settings ***
Documentation     Synchronizes CodeCollection and Helm Images for the RunWhen Runner into a private ACR Registry 
Metadata            Author    stewartshea
Metadata            Display Name    RunWhen Platform Azure ACR Image Sync
Metadata            Supports    Azure    ACR    Update    RunWhen    CodeCollection

Library             BuiltIn
Library             RW.Core
Library             RW.CLI
Library             RW.platform
Library             OperatingSystem


Suite Setup         Suite Initialization
*** Tasks ***
Sync CodeCollection Images to ACR Registry `${REGISTRY_NAME}`
    [Documentation]    Sync CodeCollection image upates that need to be synced internally to the private registry. 
    [Tags]    acr    update    codecollection    utility
    ${codecollection_images}=    RW.CLI.Run Bash File
    ...    bash_file=rwl_codecollection_updates.sh
    ...    env=${env}
    ...    secret__DOCKER_USERNAME=${DOCKER_USERNAME}
    ...    secret__DOCKER_TOKEN=${DOCKER_TOKEN}
    ...    timeout_seconds=300
    ...    include_in_history=false
    ...    show_in_rwl_cheatsheet=false

    RW.Core.Add Pre To Report    CodeCollection Image Update Output:\n${codecollection_images.stdout}

Sync RunWhen Local Image Updates to ACR Registry`${REGISTRY_NAME}`
    [Documentation]    Sync RunWhen Local image upates that need to be synced internally to the private registry. 
    [Tags]    acr    update    codecollection    utility
    ${runwhen_local_images}=    RW.CLI.Run Bash File
    ...    bash_file=rwl_helm_image_updates.sh
    ...    cmd_override=./rwl_helm_image_updates.sh https://runwhen-contrib.github.io/helm-charts runwhen-contrib runwhen-local 
    ...    env=${env}
    ...    secret__DOCKER_USERNAME=${DOCKER_USERNAME}
    ...    secret__DOCKER_TOKEN=${DOCKER_TOKEN}
    ...    timeout_seconds=300
    ...    include_in_history=false
    ...    show_in_rwl_cheatsheet=false


    RW.Core.Add Pre To Report    RunWhen Local Image Update Output:\n${runwhen_local_images.stdout}

# Sync RunWhen Local Helm Images into ACR `${ACR_REGISTRY}`
#     [Documentation]    Sync latest images for RunWhen into ACR
#     [Tags]    azure    acr    registry    runwhen
#     ${az_rw_acr_image_sync}=    RW.CLI.Run Bash File
#     ...    bash_file=codebundles/azure-rw-acr-sync/sync_with_az_import.sh
#     ...    env=${env}
#     ...    include_in_history=False
#     ...    secret__DOCKER_USERNAME=${DOCKER_USERNAME}
#     ...    secret__DOCKER_TOKEN=${DOCKER_TOKEN}
#     ...    timeout_seconds=1200
#     ${helm_output}=    RW.CLI.Run CLI
#     ...    cmd= cat ../updated_values.yaml
#     RW.Core.Add Pre To Report    Updated Helm Values for RunWhen Local:\n${helm_output.stdout}

*** Keywords ***
Suite Initialization
    ${REGISTRY_NAME}=    RW.Core.Import User Variable    REGISTRY_NAME
    ...    type=string
    ...    description=The name of the Azure Container Registry to import images into. 
    ...    pattern=\w*
    ...    example=myacr.azurecr.io
    ...    default=myacr.azurecr.io
    ${REGISTRY_REPOSITORY_PATH}=    RW.Core.Import User Variable    REGISTRY_REPOSITORY_PATH
    ...    type=string
    ...    description=The name root path of the repository for image storage.   
    ...    pattern=\w*
    ...    example=runwhen
    ...    default=runwhen
    Set Suite Variable    ${DOCKER_USERNAME}    ""
    Set Suite Variable    ${DOCKER_TOKEN}    ""
    ${USE_DOCKER_AUTH}=    RW.Core.Import User Variable
    ...    USE_DOCKER_AUTH
    ...    type=string
    ...    enum=[true,false]
    ...    description=Import the docker secret for authentication. Useful in bypassing rate limits. 
    ...    pattern=\w*
    ...    default=false
    Set Suite Variable    ${USE_DOCKER_AUTH}    ${USE_DOCKER_AUTH}
    Run Keyword If    "${USE_DOCKER_AUTH}" == "true"    Import Docker Secrets

    ${azure_credentials}=    RW.Core.Import Secret
    ...    azure_credentials
    ...    type=string
    ...    description=The secret containing AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_CLIENT_SECRET, AZURE_SUBSCRIPTION_ID
    ...    pattern=\w*
    Set Suite Variable     ${REGISTRY_REPOSITORY_PATH}    ${REGISTRY_REPOSITORY_PATH}
    Set Suite Variable     ${REGISTRY_NAME}    ${REGISTRY_NAME}
    Set Suite Variable
    ...    ${env}
    ...    {"REGISTRY_NAME":"${REGISTRY_NAME}", "WORKDIR":"${OUTPUT DIR}/azure-rw-acr-sync", "TMPDIR":"/var/tmp/runwhen", "REGISTRY_REPOSITORY_PATH":"${REGISTRY_REPOSITORY_PATH}"}


Import Docker Secrets
    ${DOCKER_USERNAME}=    RW.Core.Import Secret
    ...    DOCKER_USERNAME
    ...    type=string
    ...    description=Docker username to use if rate limited by Docker.
    ...    pattern=\w*
    ${DOCKER_TOKEN}=    RW.Core.Import Secret
    ...    DOCKER_TOKEN
    ...    type=string
    ...    description=Docker token to use if rate limited by Docker.
    ...    pattern=\w*