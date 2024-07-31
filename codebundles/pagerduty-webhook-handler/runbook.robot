*** Settings ***
Metadata          Author    stewartshea
Documentation     This CodeBundle will inspect pagerduty webhook payload data (stored in the RunWhen Platform), parse the data for SLX hints, and add Tasks to the RunSession
Metadata          Supports     PagerDuty
Suite Setup       Suite Initialization
Library           BuiltIn
Library           RW.Core
Library           RW.platform
Library           OperatingSystem
Library           RW.CLI
Library           RW.Workspace

*** Keywords ***
Suite Initialization
    ${WEBHOOK_DATA}=     RW.Core.Import Memo Variable    WEBHOOK_DATA
    ${WEBHOOK_JSON}=    Evaluate    json.loads(r'''${WEBHOOK_DATA}''')    json
    ${RW_WORKSPACE_API_URL}=    RW.Core.Import Platform Variable    RW_WORKSPACE_API_URL
    ${RW_WORKSPACE}=    RW.Core.Import Platform Variable    RW_WORKSPACE
    ${RW_SESSION_ID}=    RW.Core.Import Platform Variable    RW_SESSION_ID
    Set Suite Variable    ${env}    {"WEBHOOK_DATA":"${WEBHOOK_DATA}"}
    Set Suite Variable    ${WEBHOOK_JSON}    ${WEBHOOK_JSON}
    Set Suite Variable    ${RW_WORKSPACE_API_URL}    ${RW_WORKSPACE_API_URL}
    Set Suite Variable    ${RW_WORKSPACE}    ${RW_WORKSPACE}
    Set Suite Variable    ${RW_SESSION_ID}    ${RW_SESSION_ID}

    # ${SESSION}=          RW.Core.Get Authenticated Session
*** Tasks ***
Run SLX Tasks with matching PagerDuty Webhook Service ID
    [Documentation]    Parse the webhook details and route to the right SLX
    [Tags]    webhook    grafana    alertmanager    alert    runwhen
    IF    $WEBHOOK_JSON["event"]["event_type"] == "incident.triggered"
        Log    Running SLX Tasks that match PagerDuty Service ID ${WEBHOOK_JSON["event"]["data"]["service"]["id"]}
        ${slx_list}=    RW.Workspace.Get SLXs with Tag
        ...    tag_list=[{"name": "pagerduty_service", "value": "${WEBHOOK_JSON["event"]["data"]["service"]["id"]}"}]
        ...    rw_workspace_api_url=${RW_WORKSPACE_API_URL}
        ...    rw_workspace=${RW_WORKSPACE}
        Log    Results: ${slx_list}
        FOR    ${slx}    IN    @{slx_list} 
            Log    ${slx["shortName"]} has matched
            ${runrequest}=    RW.Workspace.Run Tasks for SLX
            ...    slx=${slx["shortName"]}
            ...    rw_workspace_api_url=${RW_WORKSPACE_API_URL}
            ...    rw_workspace=${RW_WORKSPACE}
            ...    rw_runsession=${RW_SESSION_ID}
        END
    END