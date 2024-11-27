*** Settings ***
Documentation       Determines if any RunWhen Local images have available updates in the private Azure Container Registry service.
Metadata            Author    stewartshea
Metadata            Display Name    RunWhen Local Helm Update Check (ACR)
Metadata            Supports    Azure    ACR    Update    RunWhen    Helm

Library             BuiltIn
Library             RW.Core
Library             RW.CLI
Library             RW.platform
Library             RW.Helm
Library             OperatingSystem


Suite Setup         Suite Initialization
*** Tasks ***
Check for Available RunWhen Helm Images in ACR Registry`${REGISTRY_NAME}`
    [Documentation]    Count the number of running RunWhen images that have updates available in ACR (via Helm CLI). 
    [Tags]    acr    update    codecollection    utility    helm    runwhen
    # ${codecollection_images}=    RW.CLI.Run Bash File
    # ...    bash_file=helm_update.sh
    # ...    env=${env}
    # ...    timeout_seconds=300
    # ...    include_in_history=false
    # ...    show_in_rwl_cheatsheet=false
    ${images}=    RW.Helm.Update Helm Release Images
    ...    repo_url=https://runwhen-contrib.github.io/helm-charts
    ...    chart_name=runwhen-local
    ...    release_name=runwhen-local
    ...    namespace=runwhen-local-beta
    ...    registry_type=acr
    ...    registry_details=runwhensandboxacr.azurecr.io, 2a0cf760-baef-4446-b75c-75c4f8a6267f
    

    # ${image_update_count}=    RW.CLI.Run Cli
    # ...    cmd=[ -f "${OUTPUT_DIR}/azure-rw-acr-sync/cc_images_to_update.json" ] && cat "${OUTPUT_DIR}/azure-rw-acr-sync/cc_images_to_update.json" | jq 'if . == null or . == [] then 0 else length end' | tr -d '\n' || echo -n 0
    # ...    env=${env}
    # ...    include_in_history=false
    # RW.Core.Push Metric    ${total_images}

    # Set Global Variable    ${outdated_codecollection_images}    ${image_update_count.stdout}

*** Keywords ***
Suite Initialization

    ${REGISTRY_NAME}=    RW.Core.Import User Variable    REGISTRY_NAME
    ...    type=string
    ...    description=The name of the Azure Container Registry to import images into. 
    ...    pattern=\w*
    ...    example=myacr.azurecr.io
    ...    default=myacr.azurecr.io
    ${kubeconfig}=    RW.Core.Import Secret
    ...    kubeconfig
    ...    type=string
    ...    description=The kubeconfig used to fetch the Helm release details
    ...    pattern=\w*

    Set Suite Variable
    ...    ${env}
    ...    {"REGISTRY_NAME":"${REGISTRY_NAME}", "WORKDIR":"${OUTPUT DIR}/azure-rw-acr-sync", "TMPDIR":"/var/tmp/runwhen"}
