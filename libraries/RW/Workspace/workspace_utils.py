"""
Workspace keyword library for performing tasks for interacting with Workspace resources.

Scope: Global
"""
import re, logging, json, jmespath, requests
from datetime import datetime
from robot.libraries.BuiltIn import BuiltIn

from RW import platform
from RW.Core import Core

# import bare names for robot keyword names
# from .platform_utils import *


logger = logging.getLogger(__name__)

ROBOT_LIBRARY_SCOPE = "GLOBAL"

SHELL_HISTORY: list[str] = []
SECRET_PREFIX = "secret__"
SECRET_FILE_PREFIX = "secret_file__"


def get_slxs_with_tag(
    tag_list: list,
    rw_workspace_api_url: str,
    rw_workspace: str,
) -> list:
    """Given a list of tags, return all SLXs in the workspace that have those tags.

    Args:
        tag_list (list): the given list of tags as dictionaries

    Returns:
        list: List of SLXs that match the given tags
    """
    s = platform.get_authenticated_session()
    url = f"{rw_workspace_api_url}/{rw_workspace}/slxs"
    matching_slxs = []
    
    try:
        response = s.get(url, timeout=10)
        response.raise_for_status()  # Ensure we raise an exception for bad responses
        all_slxs = response.json()  # Parse the JSON content
        results = all_slxs.get("results", [])
        
        for result in results:
            tags = result.get("spec", {}).get("tags", [])
            for tag in tags:
                if any(tag_item["name"] == tag["name"] and tag_item["value"] == tag["value"] for tag_item in tag_list):
                    matching_slxs.append(result)
                    break

        return matching_slxs
    except (requests.ConnectTimeout, requests.ConnectionError, json.JSONDecodeError) as e:
        warning_log(f"Exception while trying to get SLXs in workspace {rw_workspace}: {e}", str(e), str(type(e)))
        platform_logger.exception(e)
        return []

def run_tasks_for_slx(
    slx: str,
    rw_workspace_api_url: str,
    rw_workspace: str,
    rw_runsession: str
) -> list:
    """Given a list of tags, return all SLXs in the workspace that have those tags.

    Args:
        tag_list (list): the given list of tags as dictionaries

    Returns:
        list: List of SLXs that match the given tags
    """
    s = platform.get_authenticated_session()
    runrequest_details = {"runsession": rw_runsession}
    url = f"{rw_workspace_api_url}/{rw_workspace}/slxs/{slx}/runbook/runs"
    
    try:
        response = s.post(url, json=runrequest_details, timeout=10)
        response.raise_for_status()  # Ensure we raise an exception for bad responses
        return response.json()

    except (requests.ConnectTimeout, requests.ConnectionError, json.JSONDecodeError) as e:
        warning_log(f"Exception while trying add runrequest to runsession {rw_runsession} : {e}", str(e), str(type(e)))
        platform_logger.exception(e)
        return []