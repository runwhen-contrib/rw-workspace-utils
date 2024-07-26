*** Settings ***
Metadata          Author    stewartshea
Documentation     This CodeBundle will inspect webhook payload data (stored in the RunWhen Platform), parse the data for SLX hints, and add Tasks to the RunSession
Metadata          Supports     RunWhen
Suite Setup       Suite Initialization
Library           BuiltIn
Library           RW.Core
Library           RW.platform
Library           OperatingSystem
Library           RW.CLI

*** Keywords ***
Suite Initialization
    # ${WEBHOOK_SOURCE}=    RW.Core.Import User Variable    WEBHOOK_SOURCE
    # ...    type=string
    # ...    description=The name of the webhook source that can be used to determine the appropriate template.
    # ...    pattern=\w*
    # ...    example=PagerDuty | AlertManager | ServiceNow 
    # Set Suite Variable    ${WEBHOOK_SOURCE}    ${WEBHOOK_SOURCE}
    ${WEBHOOK_DATA}=     RW.Core.Import Memo Variable    WEBHOOK_DATA
    Set Suite Variable    ${env}    {"WEBHOOK_DATA":"${WEBHOOK_DATA}"}
    # ${SESSION}=          RW.Core.Get Authenticated Session
*** Tasks ***
Parse Webhook Payload and Route
    [Documentation]    Parse the webhook details and route to the right SLX
    [Tags]    webhook
    ${rsp}=    RW.CLI.Run Cli
    ...    cmd=echo '''${WEBHOOK_DATA}'''