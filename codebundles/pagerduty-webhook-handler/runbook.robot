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
    ${WEBHOOK_DATA}=     RW.Workspace.Import Memo Variable    
    ...    key=webhookJson
    ${WEBHOOK_JSON}=    Evaluate    json.loads(r'''${WEBHOOK_DATA}''')    json
    Set Suite Variable    ${WEBHOOK_JSON}    ${WEBHOOK_JSON}

*** Tasks ***
Run SLX Tasks with matching PagerDuty Webhook Service ID
    [Documentation]    Parse the webhook details and route to the right SLX
    [Tags]    webhook    grafana    alertmanager    alert    runwhen
    IF    $WEBHOOK_JSON["event"]["eventType"] == "incident.triggered"
        Log    Running SLX Tasks that match PagerDuty Service ID ${WEBHOOK_JSON["event"]["data"]["service"]["id"]}
        ${slx_list}=    RW.Workspace.Get SLXs with Tag
        ...    tag_list=[{"name": "pagerduty_service", "value": "${WEBHOOK_JSON["event"]["data"]["service"]["id"]}"}]
        Log    Results: ${slx_list}
        FOR    ${slx}    IN    @{slx_list} 
            Log    ${slx["shortName"]} has matched
            ${runrequest}=    RW.Workspace.Run Tasks for SLX
            ...    slx=${slx["shortName"]}
        END
    END