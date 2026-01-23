"""
SLX utility functions for getting current SLX information.
"""

import os
import json
import requests
from typing import Optional, Dict
from robot.api.deco import keyword
from robot.libraries.BuiltIn import BuiltIn


@keyword("Get Current SLX Short Name")
def get_current_slx_short_name() -> Optional[str]:
    """
    Get the short name of the current SLX from environment variables.
    
    Returns the short name of the SLX that this SLI/runbook is attached to,
    or None if it cannot be determined.
    
    Example:
        ${current_slx}=    Get Current SLX Short Name
        Log    Running in SLX: ${current_slx}
    """
    try:
        # Try to get from RW_SLX environment variable (standard for SLI execution)
        slx_name = os.getenv("RW_SLX")
        if slx_name:
            # Remove workspace prefix if present (workspace--slxname -> slxname)
            if "--" in slx_name:
                short_name = slx_name.split("--", 1)[1]
                BuiltIn().log(f"Found SLX from RW_SLX env var: {short_name}", level="INFO")
                return short_name
            return slx_name
        
        # Fall back to RW_SLX_NAME (if it exists)
        slx_name = os.getenv("RW_SLX_NAME")
        if slx_name:
            if "--" in slx_name:
                return slx_name.split("--", 1)[1]
            return slx_name
        
        # Last resort: try getting from runsession details (requires RW_SESSION_ID)
        from RW.Workspace.workspace_utils import import_runsession_details
        
        runsession_json = import_runsession_details()
        if not runsession_json:
            BuiltIn().log("Could not retrieve runsession details", level="WARN")
            return None
        
        runsession = json.loads(runsession_json)
        
        # Get the most recent runRequest
        run_requests = runsession.get("runRequests", [])
        if not run_requests:
            BuiltIn().log("No runRequests found in runsession", level="WARN")
            return None
        
        # Get the SLX name from the first/current runRequest
        # The slxName is in format "workspace--slxshortname"
        slx_name = run_requests[0].get("slxName", "")
        
        if not slx_name:
            BuiltIn().log("No slxName found in runRequest", level="WARN")
            return None
        
        # Extract the short name (remove workspace prefix)
        if "--" in slx_name:
            short_name = slx_name.split("--", 1)[1]
            BuiltIn().log(f"Current SLX short name: {short_name}", level="INFO")
            return short_name
        
        return slx_name
        
    except Exception as e:
        BuiltIn().log(f"Error getting current SLX short name: {str(e)}", level="WARN")
        return None


@keyword("Get Current SLI Interval Seconds")
def get_current_sli_interval_seconds(slx_short_name: Optional[str] = None) -> Optional[int]:
    """
    Get the intervalSeconds from the SLI's spec configuration.
    
    Args:
        slx_short_name: Optional SLX short name. If not provided, attempts to auto-detect.
    
    Returns the intervalSeconds value from the SLI spec, or None if it cannot be determined.
    Defaults to 60 seconds if not found.
    
    Example:
        ${interval}=    Get Current SLI Interval Seconds    my-slx-name
        Log    SLI runs every ${interval} seconds
    """
    try:
        from RW.Workspace.workspace_utils import import_platform_variable
        from RW import platform
        
        # Get workspace and API info
        ws = import_platform_variable("RW_WORKSPACE")
        root = import_platform_variable("RW_WORKSPACE_API_URL")
        
        # Get SLX short name (use provided or try to auto-detect)
        if not slx_short_name:
            slx_short_name = get_current_slx_short_name()
            if not slx_short_name:
                BuiltIn().log("Could not determine SLX, defaulting to 60 seconds", level="WARN")
                return 60
        else:
            BuiltIn().log(f"Using provided SLX: {slx_short_name}", level="INFO")
        
        # Build authenticated session
        token = os.getenv("RW_USER_TOKEN")
        if token:
            sess = requests.Session()
            sess.headers.update({
                "Content-Type": "application/json",
                "Authorization": f"Bearer {token}",
            })
        else:
            sess = platform.get_authenticated_session()
        
        # Handle workspace prefix
        workspace_path = ws.lstrip('/')
        if workspace_path.startswith('workspaces/'):
            workspace_path = workspace_path[len('workspaces/'):]
        
        # Handle case where root might already include "/workspaces" suffix
        base_url = root.rstrip('/')
        if base_url.endswith('/workspaces'):
            slx_url = f"{base_url}/{workspace_path}/slxs/{slx_short_name}"
        else:
            slx_url = f"{base_url}/workspaces/{workspace_path}/slxs/{slx_short_name}"
        
        try:
            response = sess.get(slx_url, timeout=120)
            response.raise_for_status()
            slx_data = response.json()
            
            # Navigate to sli.spec.intervalSeconds (correct path based on SLX structure)
            sli_spec = slx_data.get("sli", {}).get("spec", {})
            interval = sli_spec.get("intervalSeconds")
            
            if interval:
                BuiltIn().log(f"Found SLI interval: {interval} seconds", level="INFO")
                return int(interval)
            
            # Default to 60 if not found
            BuiltIn().log("intervalSeconds not found in SLI spec, defaulting to 60 seconds", level="INFO")
            return 60
            
        except (requests.RequestException, json.JSONDecodeError) as e:
            BuiltIn().log(f"Error fetching SLX details: {str(e)}, defaulting to 60 seconds", level="WARN")
            return 60
        
    except Exception as e:
        BuiltIn().log(f"Error getting SLI interval: {str(e)}, defaulting to 60 seconds", level="WARN")
        return 60
