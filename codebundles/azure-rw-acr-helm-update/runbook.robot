*** Settings ***
Documentation       Checks (or applies) RunWhen image updates with Helm CLI if any updated images exist in the upstream ACR registry. 
Metadata            Author    stewartshea
Metadata            Display Name    RunWhen Local Helm Update (ACR)
Metadata            Supports    Azure    ACR    Update    RunWhen    Helm

Library             BuiltIn
Library             RW.Core
Library             RW.CLI
Library             RW.platform
Library             OperatingSystem


Suite Setup         Suite Initialization
*** Tasks ***
Apply Available RunWhen Helm Images in ACR Registry`${REGISTRY_NAME}`
    [Documentation]    Count the number of running RunWhen images that have updates available in ACR (via Helm CLI). 
    [Tags]    acr    update    codecollection    utility    helm    runwhen
    ${rwl_image_updates}=    RW.CLI.Run Bash File
    ...    bash_file=helm_update.sh
    ...    env=${env}
    ...    secret_file__kubeconfig=${kubeconfig}
    ...    timeout_seconds=300
    ...    include_in_history=false
    ...    show_in_rwl_cheatsheet=false
    RW.Core.Add Pre To Report    ${rwl_image_updates.stdout}
    
    # Check for script failures
    IF    ${rwl_image_updates.returncode} != 0
        RW.Core.Add Issue
        ...    title=Helm Image Update Check Failed for ${HELM_RELEASE} in ${NAMESPACE}
        ...    severity=2
        ...    next_steps=Check Azure subscription access and credentials.\nVerify kubeconfig has access to cluster ${CONTEXT}.\nEnsure Helm release ${HELM_RELEASE} exists in namespace ${NAMESPACE}.\nVerify ACR registry ${REGISTRY_NAME} is accessible.\nReview script output for specific errors.
        ...    expected=Helm image update check should complete successfully.
        ...    actual=Helm image update check failed with return code ${rwl_image_updates.returncode}.
        ...    reproduce_hint=${rwl_image_updates.cmd}
        ...    details=Error Output:\n${rwl_image_updates.stderr}\n\nFull Output:\n${rwl_image_updates.stdout}
    END
    
    ${has_subscription_error}=    Evaluate    "Failed to set subscription" in """${rwl_image_updates.stdout}${rwl_image_updates.stderr}"""
    IF    ${has_subscription_error}
        RW.Core.Add Issue
        ...    title=Azure Subscription Access Failed for Helm Update Check
        ...    severity=2
        ...    next_steps=Verify AZURE_RESOURCE_SUBSCRIPTION_ID is correct.\nCheck Azure credentials have access to the subscription.\nEnsure azure_credentials secret contains valid AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_CLIENT_SECRET.\nRun 'az account show' to verify current subscription.
        ...    expected=Azure subscription should be accessible with provided credentials.
        ...    actual=Failed to set or access Azure subscription.
        ...    reproduce_hint=${rwl_image_updates.cmd}
        ...    details=Script Output:\n${rwl_image_updates.stdout}\n\nError Output:\n${rwl_image_updates.stderr}
    END
    
    ${has_helm_error}=    Evaluate    "No images found for Helm release" in """${rwl_image_updates.stdout}"""
    IF    ${has_helm_error}
        RW.Core.Add Issue
        ...    title=Helm Release ${HELM_RELEASE} Not Found in Namespace ${NAMESPACE}
        ...    severity=2
        ...    next_steps=Verify Helm release name ${HELM_RELEASE} is correct.\nCheck namespace ${NAMESPACE} exists and contains the Helm release.\nVerify kubeconfig has proper permissions.\nRun 'helm list -n ${NAMESPACE} --kube-context ${CONTEXT}' to see available releases.
        ...    expected=Helm release ${HELM_RELEASE} should exist in namespace ${NAMESPACE}.
        ...    actual=No images found for Helm release ${HELM_RELEASE}.
        ...    reproduce_hint=${rwl_image_updates.cmd}
        ...    details=Script Output:\n${rwl_image_updates.stdout}
    END
    
    # Check for available updates
    ${update_command}=    RW.CLI.Run Cli
    ...    cmd=[ -f "helm_update_required" ] && cat "helm_update_required" | grep true | awk -F ":" '{print $2}' | tr -d '\n'
    ...    env=${env}
    ...    include_in_history=false 
    IF    "${update_command.stdout}" != "" and "${HELM_APPLY_UPGRADE}" == "false"
        RW.Core.Add Issue
        ...    severity=3
        ...    next_steps=Manually update RunWhen helm release with the following command, or set HELM_APPLY_UPGRADE=true to automatically apply updates.
        ...    expected=RunWhen Local helm releases should be up to date.
        ...    actual=RunWhen Local helm release is not up to date.
        ...    title=RunWhen Local image updates are available for namespace ${NAMESPACE} in cluster ${CONTEXT}
        ...    reproduce_hint=${rwl_image_updates.cmd}
        ...    details=Run the following command:\n ${update_command.stdout}
    END

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
    ${azure_credentials}=    RW.Core.Import Secret
    ...    azure_credentials
    ...    type=string
    ...    description=The secret containing AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_CLIENT_SECRET, AZURE_SUBSCRIPTION_ID
    ...    pattern=\w*
    ${REGISTRY_REPOSITORY_PATH}=    RW.Core.Import User Variable    REGISTRY_REPOSITORY_PATH
    ...    type=string
    ...    description=The name root path of the repository for image storage.   
    ...    pattern=\w*
    ...    example=runwhen
    ...    default=runwhen
    ${HELM_APPLY_UPGRADE}=    RW.Core.Import User Variable    HELM_APPLY_UPGRADE
    ...    type=string
    ...    description=Set to true in order to automatically apply the suggested Helm upgrade   
    ...    pattern=\w*
    ...    example=false
    ...    default=false
    ${NAMESPACE}=    RW.Core.Import User Variable    NAMESPACE
    ...    type=string
    ...    description=Which Namespace to evaluate for RunWhen Helm Updates  
    ...    pattern=\w*
    ...    example=runwhen-local
    ...    default=runwhen-local
    ${CONTEXT}=    RW.Core.Import User Variable    CONTEXT
    ...    type=string
    ...    description=The Kubernetes Context to use  
    ...    pattern=\w*
    ...    example=default
    ...    default=default
    ${HELM_RELEASE}=    RW.Core.Import User Variable    HELM_RELEASE
    ...    type=string
    ...    description=The Helm release name to update  
    ...    pattern=\w*
    ...    example=runwhen-local
    ...    default=runwhen-local
    ${AZURE_RESOURCE_SUBSCRIPTION_ID}=    RW.Core.Import User Variable    AZURE_RESOURCE_SUBSCRIPTION_ID
    ...    type=string
    ...    description=The Azure Subscription ID for the resource.  
    ...    pattern=\w*
    Set Suite Variable    ${AZURE_RESOURCE_SUBSCRIPTION_ID}    ${AZURE_RESOURCE_SUBSCRIPTION_ID}
    ${REF}=    RW.Core.Import User Variable    REF
    ...    type=string
    ...    description=The git reference (branch) for codecollection image tagging (e.g., main, dev)  
    ...    pattern=\w*
    ...    example=main
    ...    default=main

    Set Suite Variable
    ...    ${env}
    ...    {"KUBECONFIG":"./${kubeconfig.key}", "HELM_RELEASE":"${HELM_RELEASE}","REGISTRY_NAME":"${REGISTRY_NAME}", "NAMESPACE":"${NAMESPACE}","CONTEXT":"${CONTEXT}", "HELM_APPLY_UPGRADE":"${HELM_APPLY_UPGRADE}", "REGISTRY_REPOSITORY_PATH":"${REGISTRY_REPOSITORY_PATH}", "AZURE_RESOURCE_SUBSCRIPTION_ID":"${AZURE_RESOURCE_SUBSCRIPTION_ID}", "REF":"${REF}"}
