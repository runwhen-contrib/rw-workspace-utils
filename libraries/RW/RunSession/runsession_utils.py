import re, logging, json, jmespath, requests, os
from datetime import datetime
from robot.libraries.BuiltIn import BuiltIn


def count_open_issues(data: str):
    """Return a count of issues that have not been closed."""
    open_issues = 0 
    runsession = json.loads(data) 
    for run_request in runsession.get("runRequests", []):
        for issue in run_request.get("issues", []): 
            if not issue["closed"]:
                open_issues+=1
    return(open_issues)

def get_open_issues(data: str):
    """Return a count of issues that have not been closed."""
    open_issue_list = []
    runsession = json.loads(data) 
    for run_request in runsession.get("runRequests", []):
        for issue in run_request.get("issues", []): 
            if not issue["closed"]:
                open_issue_list.append(issue)
    return open_issue_list

def generate_open_issue_markdown_table(data_list):
    """Generates a markdown report sorted by severity."""
    severity_mapping = {1: "Critical", 2: "High", 3: "Medium", 4: "Low"}
    
    # Sort data by severity (ascending order)
    sorted_data = sorted(data_list, key=lambda x: x.get("severity", 4))
    
    markdown_output = ""
    for data in sorted_data:
        severity = severity_mapping.get(data.get("severity", 4), "Unknown")
        title = data.get("title", "N/A")
        next_steps = data.get("nextSteps", "N/A").strip()
        details = data.get("details", "N/A")
        
        markdown_output += f"## {title}\n\n**Severity:** {severity}\n\n**Next Steps:**\n{next_steps}\n\n"
        markdown_output += f"**Details:**\n```json\n{details}\n```\n\n"
    
    return markdown_output
