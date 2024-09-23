*** Settings ***
Metadata          Author    stewartshea
Documentation     This CodeBundle will sync all of the images needed to operate RunWhen (Local + Runner components), to Azure ACR using the az cli. 
Metadata          Supports     Azure,ACR
Suite Setup       Suite Initialization
Library           BuiltIn
Library           RW.Core
Library           RW.platform
Library           OperatingSystem
Library           RW.CLI


*** Keywords ***
Suite Initialization
    ${ACR_REGISTRY}=    RW.Core.Import User Variable    ACR_REGISTRY
    ...    type=string
    ...    description=The name of the Azure Container Registry to import images into. 
    ...    pattern=\w*
    ...    example=myacr.azurecr.io
    ...    default=myacr.azurecr.io
    ${azure_credentials}=    RW.Core.Import Secret
    ...    azure_credentials
    ...    type=string
    ...    description=The secret containing AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_CLIENT_SECRET, AZURE_SUBSCRIPTION_ID
    ...    pattern=\w*

*** Tasks ***
Sync RunWhen Local Images into Azure Container Registry `${ACR_REGISTRY}`
    [Documentation]    Sync latest images for RunWhen into ACR
    [Tags]    azure    acr    registry    runwhen
    ${node_usage_details}=    RW.CLI.Run Bash File
    ...    bash_file=sync_with_az_import.sh
    ...    env=${env}
    ...    include_in_history=False
    ...    show_in_rwl_cheatsheet=false
