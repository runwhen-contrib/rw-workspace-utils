*** Settings ***
Metadata          Author    stewartshea
Documentation     This CodeBundle create a new GitHub Issue with the RunSession details. 
Metadata          Supports     GitHub
Metadata          Display Name     GitHub Create Issue
Suite Setup       Suite Initialization
Library           BuiltIn
Library           RW.Core
Library           RW.platform
Library           OperatingSystem
Library           RW.CLI
Library           RW.Workspace
Library           RW.GitHub
Library           RW.RunSession

*** Keywords ***
Suite Initialization
    ${GITHUB_REPOSITORY}=    RW.Core.Import User Variable    GITHUB_REPOSITORY
    ...    type=string
    ...    description=The GitHub owner and repository
    ...    pattern=\w*
    ...    example=runwhen-contrib/runwhen-local

   ${GITHUB_TOKEN}=    RW.Core.Import Secret    GITHUB_TOKEN
    ...    type=string
    ...    description=The secret containing the GitHub PAT. 
    ...    pattern=\w*

    ${SESSION}=    RW.Workspace.Import Runsession Details
    Set Suite Variable    ${SESSION}    ${SESSION}


*** Tasks ***
Create GitHub Issue in Repository `${GITHUB_REPOSITORY}` from RunSession
    [Documentation]    Create a GitHub Issue with the summarized details of the RunSession. Intended to be used as a final task in a workflow. 
    [Tags]    github    issue    final    ticket
    ${session_list}=    Evaluate    json.loads(r'''${SESSION}''')    json
    ${open_issue_count}=    RW.RunSession.Count Open Issues    ${SESSION}
    ${title}=        Set Variable    "[RunWhen] ${open_issue_count} open issues from ${session_list["source"]}"
    Add Pre To Report    Title: ${title}
    ${open_issues}=    RW.RunSession.Get Open Issues    ${SESSION}
    ${issue_table}=    RW.RunSession.Generate Open Issue Markdown Table    ${open_issues}
    Add Pre To Report    ${issue_table}
    ${github_issue}=    RW.GitHub.Create GitHub Issue     
    ...    title=${title}
    ...    body=${issue_table}
    ...    github_token=${GITHUB_TOKEN}
    ...    repo=${GITHUB_REPOSITORY}
    Add Pre To Report    ${github_issue}


