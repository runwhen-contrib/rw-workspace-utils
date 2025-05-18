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
Library           RW.RunSession

*** Keywords ***
Suite Initialization
    ${DRY_RUN_MODE}=    RW.Core.Import User Variable    DRY_RUN_MODE
    ...    description=Whether to capture the webhook details in dry-run mode, reporting what tasks will be run but not executing them. True or False  
    ...    enum=[true,false]
    ...    default=true
    ${CURRENT_SESSION}=      RW.Workspace.Import Runsession Details
    ${CURRENT_SESSION_JSON}=    Evaluate    json.loads(r'''${CURRENT_SESSION}''')    json
    Set Suite Variable    ${CURRENT_SESSION_JSON}

    ${WEBHOOK_DATA}=     RW.Workspace.Import Memo Variable    
    ...    key=webhookJson
    ${WEBHOOK_JSON}=    Evaluate    json.loads(r'''${WEBHOOK_DATA}''')    json
    Set Suite Variable    ${WEBHOOK_JSON}    ${WEBHOOK_JSON}

    # # Local test data
    # ${WEBHOOK_DATA}=     RW.Core.Import User Variable    WEBHOOK_DATA
    # ${WEBHOOK_JSON}=    Evaluate    json.loads(r'''${WEBHOOK_DATA}''')    json
    # Set Suite Variable    ${WEBHOOK_JSON}

*** Tasks ***
Add Tasks to RunSession from AlertManager Webhook Details
    [Documentation]    Parse the alertmanager webhook commonLabels and route and SLX where commonLabels match SLX tags
    [Tags]    webhook    grafana    alertmanager    alert    runwhen

    RW.Core.Add To Report    Webhook received with state: ${WEBHOOK_JSON["status"]}

    IF    $WEBHOOK_JSON["status"] == "firing"
        Log    Parsing webhook data ${WEBHOOK_JSON}
        ${persona}=    RW.RunSession.Get Persona Details
        ...    persona=${CURRENT_SESSION_JSON["personaShortName"]}
        ${run_confidence}=    Set Variable     ${persona["spec"]["run"]["confidenceThreshold"]}
        ${common_labels_list}=    Evaluate
        ...    [f"{k}:{v}" for k, v in ${WEBHOOK_JSON["commonLabels"]}.items()]
        
        RW.Core.Add To Report    RunSession assigned to ${persona}, with run confidence ${run_confidence}, looking to scope search to the following commonLabels ${common_labels_list}
        
        ${slx_list}=    RW.Workspace.Get Slxs With Tag
        ...    tag_list=${common_labels_list}
        
        IF  len(${slx_list}) == 0

            RW.Core.Add To Report    Could not match commonLabels to any SLX tags. Cannot continue with RunSession.
        ELSE

            RW.Core.Add To Report    Found SLX matches..continuing on with search. 
            FOR    ${slx}    IN    @{slx_list} 
                Log    ${slx["shortName"]} has matched
                ${scope}=    Create List    ${slx["shortName"]}
                ${qry}=      Set Variable    ${slx["shortName"]} Health

                # Perform search with Admin permissions - These tasks will never be run
                ${admin_search}=    RW.Workspace.Perform Task Search
                ...    query=${qry}
                ...    slx_scope=${scope}

                ${admin_tasks_results}=    RW.Workspace.Build Task Report Md 
                ...    search_response=${admin_search}
                ...    score_threshold=0
                RW.Core.Add To Report    \# Tasks found with Admin permissions (these will NOT be run)
                RW.Core.Add Pre To Report    ${admin_tasks_results}


                # Perform search with Persona that is attached to the RunSession
                ${search_with_persona}=    RW.Workspace.Perform Task Search With Persona
                ...    query=${qry}
                ...    slx_scope=${scope}
                ...    persona=${CURRENT_SESSION_JSON["personaShortName"]}
                RW.Core.Add To Report    \# Tasks found with Engineering Assistant permissions (${CURRENT_SESSION_JSON["personaShortName"]})

                ${tasks_to_run}=    RW.Workspace.Build Task Report Md 
                ...    search_response=${search_with_persona}
                ...    score_threshold=${run_confidence}
                RW.Core.Add Pre To Report    ${tasks_to_run}

                IF    $DRY_RUN_MODE == "false"
                    RW.Core.Add To Report    Dry-run mode is false. Adding tasks to RunSesssion...
                    # Preview first – cheap and tells us whether there is anything to do
                    ${patch_preview}=    RW.RunSession.Add Tasks to RunSession From Search
                    ...    search_response=${search_with_persona}
                    ...    score_threshold=${run_confidence}
                    ...    dry_run=True

                    IF    ${patch_preview} == {}
                        RW.Core.Add To Report    No tasks exceeded confidence ${run_confidence} for ${slx["shortName"]}. Skipping patch.    INFO
                    ELSE
                        Log    ${len(${patch_preview["runRequests"]})} task(s) will be added – sending patch.    INFO

                        ${patch_result}=    RW.RunSession.Add Tasks to RunSession From Search
                        ...    search_response=${search_with_persona}
                        ...    score_threshold=${run_confidence}
                        ...    dry_run=False

                        IF    ${patch_result} == {}
                            RW.Core.Add Issue
                            ...    severity=3
                            ...    expected=RunSession patch should be successful
                            ...    actual=RunSession patch failed – empty response
                            ...    title=Could not patch RunSession `${CURRENT_SESSION_JSON["id"]}` with tasks from `${slx["shortName"]}`
                            ...    reproduce_hint=Apply patch to RunSession ${CURRENT_SESSION_JSON["id"]}
                            ...    details=See debug logs or backend response body.
                            ...    next_steps=Inspect runrequest logs or contact RunWhen support.
                        END
                    END
                END            
            END        
        
        END
    END