*** Settings ***
Metadata          Author    stewartshea
Documentation     This CodeBundle will inspect alertmanager webhook payload data (stored in the RunWhen Platform), parse the data for SLX hints, and add Tasks to the RunSession
Metadata          Supports     AlertManager   Webhook
Metadata          Display Name     AlertManager Webhook Handler
Suite Setup       Suite Initialization
Library           BuiltIn
Library           RW.Core
Library           RW.platform
Library           OperatingSystem
Library           RW.CLI
Library           RW.Workspace

*** Keywords ***
Suite Initialization
    ${DRY_RUN_MODE}=    RW.Core.Import User Variable    DRY_RUN_MODE
    ...    type=string
    ...    description=Whether to capture the webhook details in dry-run mode, reporting what tasks will be run but not executing them. True or False  
    ...    pattern=\w*
    ...    example=true
    ...    default=true
    ${CURRENT_SESSION}=      RW.Workspace.Import Runsession Details
    Set Suite Variable    ${CURRENT_SESSION}

    # ${WEBHOOK_DATA}=     RW.Workspace.Import Memo Variable    
    # ...    key=webhookJson
    # ${WEBHOOK_JSON}=    Evaluate    json.loads(r'''${WEBHOOK_DATA}''')    json
    # Set Suite Variable    ${WEBHOOK_JSON}    ${WEBHOOK_JSON}

    # Local test data
    ${WEBHOOK_DATA}=     RW.Core.Import User Variable    WEBHOOK_DATA
    ${WEBHOOK_JSON}=    Evaluate    json.loads(r'''${WEBHOOK_DATA}''')    json
    Set Suite Variable    ${WEBHOOK_JSON}

*** Tasks ***
Run SLX Tasks with matching AlertManager Webhook commonLabels
    [Documentation]    Parse the alertmanager webhook commonLabels and route and SLX where commonLabels match SLX tags
    [Tags]    webhook    grafana    alertmanager    alert    runwhen
    IF    $WEBHOOK_JSON["status"] == "firing"
        Log    Parsing webhook data ${WEBHOOK_JSON}
        # Parse slx details
        # ${common_labels_list}=    Evaluate    [{'name': k, 'value': v} for k, v in ${WEBHOOK_JSON["commonLabels"]}.items()]
        ${common_labels_list}=    Evaluate
        ...    [f"{k}:{v}" for k, v in ${WEBHOOK_JSON["commonLabels"]}.items()]

        # Find useful slxs for search scope
        # ${slx_list}=    RW.Workspace.Get Slxs with Entity Reference
        # ...    entity_refs=${common_labels_list}
        ${slx_list}=    RW.Workspace.Get Slxs With Tag
        ...    tag_list=${common_labels_list}
                
        Log    Results: ${slx_list}
        FOR    ${slx}    IN    @{slx_list} 
            Log    ${slx["shortName"]} has matched
            # ${runrequest}=    RW.Workspace.Run Tasks for SLX
            # ...    slx=${slx["shortName"]}
        END
    END