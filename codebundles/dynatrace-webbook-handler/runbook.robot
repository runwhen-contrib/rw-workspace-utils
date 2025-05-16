*** Settings ***
Metadata          Author    stewartshea
Documentation     This CodeBundle inspects the dynatrace webhook payload data (stored in the RunWhen Platform) and starts a RunSession from the available data. 
Metadata          Supports     Dynatrace   Webhook
Metadata          Display Name     Dynatrace Webhook Handler
Suite Setup       Suite Initialization
Library           BuiltIn
Library           RW.Core
Library           RW.platform
Library           OperatingSystem
Library           RW.CLI
Library           RW.Workspace
Library           RW.Dynatrace
Library           Collections

*** Keywords ***
Suite Initialization
    ${DRY_RUN_MODE}=    RW.Core.Import User Variable    DRY_RUN_MODE
    ...    type=string
    ...    description=Whether to capture the webhook details in dry-run mode, reporting what tasks will be run but not executing them. True or False  
    ...    pattern=\w*
    ...    example=true
    ...    default=true
    Set Suite Variable    ${DRY_RUN_MODE}    ${DRY_RUN_MODE}
    ${WEBHOOK_DATA}=     RW.Workspace.Import Memo Variable    
    ...    key=webhookJson
    ${WEBHOOK_JSON}=    Evaluate    json.loads(r'''${WEBHOOK_DATA}''')    json
    Set Suite Variable    ${WEBHOOK_JSON}    ${WEBHOOK_JSON}
    ${CURRENT_SESSION}=      RW.Workspace.Import Runsession Details
    Set Suite Variable    ${CURRENT_SESSION}

    # # Local test data
    # ${WEBHOOK_DATA}=     RW.Core.Import User Variable    WEBHOOK_DATA
    # ${WEBHOOK_JSON}=    Evaluate    json.loads(r'''${WEBHOOK_DATA}''')    json
    # Set Suite Variable    ${WEBHOOK_JSON}

*** Tasks ***
Start RunSession From Dynatrace Webhook Details
    [Documentation]    Parse the dynatrace webhook and route and SLX where entities match search results
    [Tags]    webhook    dynatrace    alert    runwhen

    RW.Core.Add To Report    Dynatrace Problem Details:\n ${WEBHOOK_JSON["problemDetailsMarkdown"]}
    RW.Core.Add Pre To Report    Full payload:\n ${WEBHOOK_JSON}


    IF    '${WEBHOOK_JSON["state"]}' == 'OPEN'
        # # 1) Gather the impacted entities list that came in the webhook
        ${entity_names}=    RW.Dynatrace.Parse Dynatrace Entities    ${WEBHOOK_JSON}
        RW.Core.Add Pre To Report      Found entity names: ${entity_names}

        # 2) Find any slxs that might reference those entity names
        ${slx_list}=        RW.Workspace.Get Slxs With Entity Reference    ${entity_names}
        Log                 Found SLXs: ${slx_list}
        
        #Perform Task Seach
        ${persona_search_tasks}=    RW.Workspace.Perform Task Search With Persona
        ...    query="${slx_list[0]} Health"
        ...    persona="${CURRENT_SESSION["personaShortName"]}"
        ...    slx_scope=${slx_list}


        # 3) Add those SLXs to the RunSession
        IF  len(${slx_list}) > 0
            FOR    ${slx}    IN    @{slx_list} 
                RW.Core.Add To Report    ${slx["shortName"]} has matched
                #${runrequest}=    RW.Workspace.Run Tasks for SLX
                # ...    slx=${slx["shortName"]}
            END
        END
    END