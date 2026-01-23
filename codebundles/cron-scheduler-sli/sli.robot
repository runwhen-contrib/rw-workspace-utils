*** Settings ***
Documentation       Generic Cron Scheduler SLI that runs a runbook on a cron schedule.
...                 This SLI checks if the current time matches the configured cron schedule,
...                 and if so, executes all tasks from the runbook attached to the specified SLX.
Metadata            Author    stewartshea
Metadata            Display Name    Cron Scheduler SLI
Metadata            Supports    Generic    Cron    Scheduler    Workspace

Library             BuiltIn
Library             RW.Core
Library             RW.Workspace
Library             RW.Cron
Library             OperatingSystem

Suite Setup         Suite Initialization

*** Keywords ***
Suite Initialization
    ${CRON_SCHEDULE}=    RW.Core.Import User Variable    CRON_SCHEDULE
    ...    type=string
    ...    description=Cron schedule expression (e.g., "0 */2 * * *" for every 2 hours, "*/15 * * * *" for every 15 minutes)
    ...    pattern=\w*
    ...    example=0 */2 * * *
    ...    default=0 * * * *
    Set Suite Variable    ${CRON_SCHEDULE}    ${CRON_SCHEDULE}

    ${TARGET_SLX}=    RW.Core.Import User Variable    TARGET_SLX
    ...    type=string
    ...    description=The short name of the target SLX whose runbook should be executed when the cron schedule matches. If empty, uses the current SLX (the SLX this SLI is attached to).
    ...    pattern=\w*
    ...    example=my-slx-shortname
    ...    default=${EMPTY}
    
    # If TARGET_SLX is not provided, use the current SLX
    ${target_slx_empty}=    Run Keyword And Return Status    Should Be Empty    ${TARGET_SLX}
    IF    ${target_slx_empty}
        ${TARGET_SLX}=    RW.Workspace.Get Current SLX Short Name
        ${still_empty}=    Run Keyword And Return Status    Should Be Empty    ${TARGET_SLX}
        IF    ${still_empty} or $TARGET_SLX is None
            RW.Core.Add Issue
            ...    severity=2
            ...    expected=TARGET_SLX should be provided or SLI should be attached to an SLX
            ...    actual=Could not determine TARGET_SLX from configuration or current SLX context
            ...    title=Cron Scheduler Configuration Error - Missing TARGET_SLX
            ...    reproduce_hint=Provide TARGET_SLX parameter or ensure this SLI is properly attached to an SLX
            ...    details=The cron scheduler could not determine which SLX runbook to execute. Either specify TARGET_SLX explicitly or attach this SLI to an SLX.
            ...    next_steps=Add TARGET_SLX parameter to the SLI configuration, or verify the SLI is attached to an SLX with a runbook.
            RW.Core.Push Metric    -1
            Return From Keyword
        END
        RW.Core.Add To Report    Using current SLX: ${TARGET_SLX}
    END
    
    Set Suite Variable    ${TARGET_SLX}    ${TARGET_SLX}

    # Get the SLI interval from the SLX spec automatically (pass TARGET_SLX)
    ${RUN_INTERVAL_SECONDS}=    RW.Workspace.Get Current SLI Interval Seconds    ${TARGET_SLX}
    RW.Core.Add To Report    Detected SLI interval: ${RUN_INTERVAL_SECONDS} seconds
    Set Suite Variable    ${RUN_INTERVAL_SECONDS}    ${RUN_INTERVAL_SECONDS}

    ${DRY_RUN}=    RW.Core.Import User Variable    DRY_RUN
    ...    type=string
    ...    description=If true, only check the cron schedule and report but don't execute the runbook
    ...    enum=[true,false]
    ...    pattern=\w*
    ...    default=false
    Set Suite Variable    ${DRY_RUN}    ${DRY_RUN}

*** Tasks ***
Check Cron Schedule and Execute Runbook for SLX `${TARGET_SLX}`
    [Documentation]    Check if the current time matches the cron schedule and execute the target SLX runbook if it does
    [Tags]    cron    scheduler    sli    automation

    # Validate the cron schedule
    ${is_valid}=    RW.Cron.Validate Cron Schedule    ${CRON_SCHEDULE}
    IF    not ${is_valid}
        RW.Core.Add To Report    ERROR: Invalid cron schedule: ${CRON_SCHEDULE}
        RW.Core.Add Issue
        ...    severity=2
        ...    expected=Valid cron schedule expression in standard 5-field format
        ...    actual=Invalid cron schedule: ${CRON_SCHEDULE}
        ...    title=Cron Scheduler Configuration Error - Invalid Cron Expression
        ...    reproduce_hint=Check the CRON_SCHEDULE parameter syntax (format: minute hour day month weekday)
        ...    details=The provided cron schedule "${CRON_SCHEDULE}" is not a valid cron expression. Use standard 5-field cron syntax (e.g., "0 */2 * * *" for every 2 hours).
        ...    next_steps=Update CRON_SCHEDULE to a valid cron expression. Examples: "0 * * * *" (hourly), "*/15 * * * *" (every 15 min), "0 9 * * 1-5" (9 AM weekdays).
        RW.Core.Push Metric    -1
        Return From Keyword
    END

    # Get the next scheduled run time for reporting
    ${next_run}=    RW.Cron.Get Next Cron Run Time    ${CRON_SCHEDULE}
    RW.Core.Add To Report    Cron schedule: ${CRON_SCHEDULE}
    RW.Core.Add To Report    Next scheduled run: ${next_run}
    RW.Core.Add To Report    Target SLX: ${TARGET_SLX}
    RW.Core.Add To Report    Run interval: ${RUN_INTERVAL_SECONDS} seconds

    # Check if the current time matches the cron schedule
    ${is_time_to_run}=    RW.Cron.Check Cron Schedule Match    
    ...    ${CRON_SCHEDULE}    
    ...    ${RUN_INTERVAL_SECONDS}

    IF    ${is_time_to_run}
        RW.Core.Add To Report    ✓ Cron schedule matched! Time to execute runbook.
        
        IF    '${DRY_RUN}' == 'true'
            RW.Core.Add To Report    DRY RUN MODE: Would execute runbook for SLX ${TARGET_SLX}
            ${metric_value}=    Set Variable    0
        ELSE
            RW.Core.Add To Report    Creating new runsession for SLX ${TARGET_SLX}...
            
            # Create a new runsession with all tasks from the target SLX runbook
            ${result}=    RW.Workspace.Create RunSession For SLX    ${TARGET_SLX}    cronScheduler
            
            IF    $result is not None
                RW.Core.Add To Report    ✓ Successfully created runsession for SLX ${TARGET_SLX}
                RW.Core.Add Pre To Report    RunSession:\n${result}
                ${metric_value}=    Set Variable    1
            ELSE
                RW.Core.Add To Report    ✗ Failed to create runsession for SLX ${TARGET_SLX}
                RW.Core.Add Issue
                ...    severity=2
                ...    expected=Successfully create runsession for SLX ${TARGET_SLX}
                ...    actual=Failed to create runsession - API call returned None or failed
                ...    title=Cron Scheduler Execution Failed for SLX ${TARGET_SLX}
                ...    reproduce_hint=Verify the SLX "${TARGET_SLX}" exists and has a runbook configured
                ...    details=The cron scheduler matched the schedule and attempted to create a runsession for SLX ${TARGET_SLX}, but the API request failed. This could be due to: SLX not found, no runbook configured, insufficient permissions, or API connectivity issues.
                ...    next_steps=Verify SLX name "${TARGET_SLX}" is correct, check that the SLX exists in the workspace, ensure it has a runbook configured, and verify the SLI has permissions to create runsessions.
                ${metric_value}=    Set Variable    -1
            END
        END
    ELSE
        RW.Core.Add To Report    Schedule not matched. Waiting for next scheduled time: ${next_run}
        ${metric_value}=    Set Variable    0
    END

    # Push metric: 1 = runbook executed, 0 = not time yet, -1 = execution failed
    RW.Core.Push Metric    ${metric_value}
