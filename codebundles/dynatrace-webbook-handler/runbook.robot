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
    ...    description=Whether to capture the webhook details in dry-run mode, reporting what tasks will be run but not executing them. True or False  
    ...    enum=[true,false]
    ...    default=true
    Set Suite Variable    ${DRY_RUN_MODE}    ${DRY_RUN_MODE}

    # ${WEBHOOK_DATA}=     RW.Workspace.Import Memo Variable    
    # ...    key=webhookJson
    # ${WEBHOOK_JSON}=    Evaluate    json.loads(r'''${WEBHOOK_DATA}''')    json
    # Set Suite Variable    ${WEBHOOK_JSON}    ${WEBHOOK_JSON}
    ${CURRENT_SESSION}=      RW.Workspace.Import Runsession Details
    Set Suite Variable    ${CURRENT_SESSION}

    # Local test data
    ${WEBHOOK_DATA}=     RW.Core.Import User Variable    WEBHOOK_DATA
    ${WEBHOOK_JSON}=    Evaluate    json.loads(r'''${WEBHOOK_DATA}''')    json
    Set Suite Variable    ${WEBHOOK_JSON}

*** Tasks ***
Start RunSession From Dynatrace Webhook Details
    # [Documentation]    Parse the dynatrace webhook and route and SLX where entities match search results
    # [Tags]    webhook    dynatrace    alert    runwhen

    # RW.Core.Add To Report    Dynatrace Problem Details:\n ${WEBHOOK_JSON["problemDetailsMarkdown"]}
    # RW.Core.Add Pre To Report    Full payload:\n ${WEBHOOK_JSON}


    # IF    '${WEBHOOK_JSON["state"]}' == 'OPEN'
    #     # # 1) Gather the impacted entities list that came in the webhook
    #     ${entity_names}=    RW.Dynatrace.Parse Dynatrace Entities    ${WEBHOOK_JSON}
    #     RW.Core.Add Pre To Report      Found entity names: ${entity_names}

    #     # 2) Find any slxs that might reference those entity names
    #     ${slx_list}=        RW.Workspace.Get Slxs With Entity Reference    ${entity_names}
    #     Log                 Found SLXs: ${slx_list}
        
    #     #Perform Task Seach
    #     ${persona_search_tasks}=    RW.Workspace.Perform Task Search With Persona
    #     ...    query="${slx_list[0]} Health"
    #     ...    persona="${CURRENT_SESSION["personaShortName"]}"
    #     ...    slx_scope=${slx_list}


    #     # 3) Add those SLXs to the RunSession
    #     IF  len(${slx_list}) > 0
    #         FOR    ${slx}    IN    @{slx_list} 
    #             RW.Core.Add To Report    ${slx["shortName"]} has matched
    #             #${runrequest}=    RW.Workspace.Run Tasks for SLX
    #             # ...    slx=${slx["shortName"]}
    #         END
    #     END
    # END
    [Documentation]    Parse webhook ➜ match SLXs ➜ search tasks ➜ (optionally) patch RunSession
    [Tags]    webhook    dynatrace    alert    runwhen

    RW.Core.Add To Report    Dynatrace problem state: ${WEBHOOK_JSON["state"]}
    RW.Core.Add Pre To Report    Full payload:\n${WEBHOOK_JSON}

    IF    '${WEBHOOK_JSON["state"]}' == 'OPEN'
        # 1) Extract impacted entities
        ${entity_names}=    RW.Dynatrace.Parse Dynatrace Entities    ${WEBHOOK_JSON}
        RW.Core.Add To Report    Impacted entities: ${entity_names}

        # 2) Resolve SLXs
        ${slx_list}=    RW.Workspace.Get Slxs With Entity Reference    ${entity_names}
        IF    len(${slx_list}) == 0
            RW.Core.Add To Report    No SLX matched impacted entities – stopping handler.
        ELSE
            ${slx_scopes}=    Create List
            FOR    ${slx}    IN    @{slx_list}
                Append To List    ${slx_scopes}    ${slx["shortName"]}
            END
            ${qry}=    Set Variable    ${slx_scopes[0]} Health
            RW.Core.Add To Report    SLX matches: ${slx_scopes}; query='${qry}'

            # 3) Get persona / confidence threshold
            ${persona}=    RW.RunSession.Get Persona Details
            ...            persona=${CURRENT_SESSION_JSON["personaShortName"]}
            ${run_confidence}=    Set Variable    ${persona["spec"]["run"]["confidenceThreshold"]}

            # 4) Admin-level discovery (report only)
            ${admin_search}=    RW.Workspace.Perform Task Search
            ...                query=${qry}
            ...                slx_scope=${slx_scopes}
            ${admin_md}=       RW.Workspace.Build Task Report Md    ${admin_search}    0
            RW.Core.Add To Report    \# Tasks visible to Admin (not executed)
            RW.Core.Add Pre To Report    ${admin_md}

            # 5) Persona-restricted discovery
            ${persona_search}=    RW.Workspace.Perform Task Search With Persona
            ...                    query=${qry}
            ...                    persona=${CURRENT_SESSION_JSON["personaShortName"]}
            ...                    slx_scope=${slx_scopes}
            ${tasks_md}=          RW.Workspace.Build Task Report Md
            ...                    search_response=${persona_search}
            ...                    score_threshold=${run_confidence}
            RW.Core.Add To Report    \# Tasks meeting confidence ≥${run_confidence}
            RW.Core.Add Pre To Report    ${tasks_md}

            # 6) Optional RunSession patch
            IF    '${DRY_RUN_MODE}' == 'false'
                RW.Core.Add To Report    Dry-run disabled – previewing patch …
                ${preview}=    RW.RunSession.Add Tasks to RunSession From Search
                ...            search_response=${persona_search}
                ...            score_threshold=${run_confidence}
                ...            dry_run=True

                IF    ${preview} == {}
                    RW.Core.Add To Report    No tasks cleared confidence threshold – nothing to patch.
                ELSE
                    Log    ${len(${preview["runRequests"]})} task(s) will be added – sending patch.
                    ${patch}=    RW.RunSession.Add Tasks to RunSession From Search
                    ...          search_response=${persona_search}
                    ...          score_threshold=${run_confidence}
                    ...          dry_run=False

                    IF    ${patch} == {}
                        RW.Core.Add Issue
                        ...    severity=3
                        ...    expected=RunSession patch succeeds
                        ...    actual=Patch returned empty response
                        ...    title=Failed to add tasks to RunSession ${CURRENT_SESSION_JSON["id"]}
                        ...    reproduce_hint=Re-run webhook handler in debug
                        ...    next_steps=Inspect backend logs or contact RunWhen support
                    END
                END
            ELSE
                RW.Core.Add To Report    Dry-run mode active – no RunSession patch executed.
            END
        END
    ELSE
        RW.Core.Add To Report    Problem state '${WEBHOOK_JSON["state"]}' – handler only processes OPEN events.
    END