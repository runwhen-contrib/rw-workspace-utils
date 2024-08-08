"""
Workspace keyword library for performing tasks for interacting with Workspace resources.

Scope: Global
"""

import re, logging, json, jmespath, requests, os
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
) -> list:
    """Given a list of tags, return all SLXs in the workspace that have those tags.

    Args:
        tag_list (list): the given list of tags as dictionaries

    Returns:
        list: List of SLXs that match the given tags
    """
    try:
        runrequest_id = import_platform_variable("RW_RUNREQUEST_ID")
        rw_runsession = import_platform_variable("RW_SESSION_ID")
        rw_workspace = import_platform_variable("RW_WORKSPACE")
        rw_workspace_api_url = import_platform_variable("RW_WORKSPACE_API_URL")
    except ImportError:
        return None

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
                if any(
                    tag_item["name"] == tag["name"]
                    and tag_item["value"] == tag["value"]
                    for tag_item in tag_list
                ):
                    matching_slxs.append(result)
                    break

        return matching_slxs
    except (
        requests.ConnectTimeout,
        requests.ConnectionError,
        json.JSONDecodeError,
    ) as e:
        warning_log(
            f"Exception while trying to get SLXs in workspace {rw_workspace}: {e}",
            str(e),
            str(type(e)),
        )
        platform_logger.exception(e)
        return []


def run_tasks_for_slx(
    slx: str,
) -> list:
    """Given an slx and a runsession, add runrequest with all slx tasks to runsession.

    Args:
        slx (string): slx short name

    Returns:
        list: List of SLXs that match the given tags
    """
    try:
        runrequest_id = import_platform_variable("RW_RUNREQUEST_ID")
        rw_runsession = import_platform_variable("RW_SESSION_ID")
        rw_workspace = import_platform_variable("RW_WORKSPACE")
        rw_workspace_api_url = import_platform_variable("RW_WORKSPACE_API_URL")
    except ImportError:
        return None
    s = platform.get_authenticated_session()


    # Get all tasks for slx and concat into string separated by ||
    slx_url = f"{rw_workspace_api_url}/{rw_workspace}/slxs/{slx}/runbook"

    try:
        slx_response = s.get(slx_url, timeout=10)
        slx_response.raise_for_status()
        slx_data = slx_response.json()  # Parse JSON content
        tasks = slx_data.get("status", {}).get("codeBundle", {}).get("tasks", [])
    except (
        requests.ConnectTimeout,
        requests.ConnectionError,
        json.JSONDecodeError,
    ) as e:
        BuiltIn().log(
            f"Exception while trying to fetch list of slx tasks : {e}",
            str(e),
            str(type(e)),
        )
        platform_logger.exception(e)
        tasks_string = ""  # Set to empty string if errored

    runrequest_details = {
        "runRequests": [
            {
                "slxName": f"{rw_workspace}--{slx}",
                "taskTitles": tasks
            }
        ]
    }

    # Add RunRequest
    rs_url = f"{rw_workspace_api_url}/{rw_workspace}/runsessions/{rw_runsession}"

    try:
        response = s.patch(rs_url, json=runrequest_details, timeout=10)
        response.raise_for_status()  # Ensure we raise an exception for bad responses
        return response.json()

    except (
        requests.ConnectTimeout,
        requests.ConnectionError,
        json.JSONDecodeError,
    ) as e:
        BuiltIn().log(
            f"Exception while trying add runrequest to runsession {rw_runsession} : {e}",
            str(e),
            str(type(e)),
        )
        platform_logger.exception(e)
        return []


## This is an edit of the core platform keyword that was having trouble
## This has been been rewritten to avoid debugging core keywords that follow
## a separate build process. This may need to be refactored into the runtime later. 
## The main difference here is that we fetch the memo from the runsession instead
## of the runrequest - and as well we return valid json, which wouldn't be appropriate
## for all memo keys, but works for the Json payload. 
def import_memo_variable(key: str):
    """If this is a runbook, the runsession / runrequest may have been initiated with
    a memo value. Get the value for key within the memo, or None if there was no
    value found or if there was no memo provided (e.g. with an SLI)
    """
    try:
        runrequest_id = str(import_platform_variable("RW_RUNREQUEST_ID"))
        rw_runsession = import_platform_variable("RW_SESSION_ID")
        rw_workspace = import_platform_variable("RW_WORKSPACE")
        rw_workspace_api_url = import_platform_variable("RW_WORKSPACE_API_URL")
    except ImportError:
        BuiltIn().log(f"Failure importing required variables", level='WARN')
        return None

    s = platform.get_authenticated_session()
    url = f"{rw_workspace_api_url}/{rw_workspace}/runsessions/{rw_runsession}"
    BuiltIn().log(f"Importing memo variable with URL: {url}, runrequest {runrequest_id}", level='INFO')

    try:
        rsp = s.get(url, timeout=10, verify=platform.REQUEST_VERIFY)
        run_requests = rsp.json().get("runRequests", [])
        for run_request in run_requests:
            if str(run_request.get("id")) == runrequest_id:
                memo_list = run_request.get("memo", [])
                if isinstance(memo_list, list):
                    for memo in memo_list:
                        if isinstance(memo, dict) and key in memo:
                            # Ensure the value is JSON-serializable
                            ## TODO Handle non json memo data
                            value = memo[key]
                            try:
                                json.dumps(value)  # Check if value is JSON serializable
                                return json.dumps(value)  # Return as JSON string
                            except (TypeError, ValueError):
                                BuiltIn().log(f"Value for key '{key}' is not JSON-serializable: {value}", level='WARN')
                                return json.dumps(str(value))  # Convert non-serializable value to string
        return json.dumps(None)
    except (requests.ConnectTimeout, requests.ConnectionError, json.JSONDecodeError) as e:
        warning_log(f"Exception while trying to get memo: {e}", str(e), str(type(e)))
        platform_logger.exception(e)
        return json.dumps(None)

def import_platform_variable(varname: str) -> str:
    """
    Imports a variable set by the platform, raises error if not available.

    :param str: Name to be used both to lookup the config val and for the
        variable name in robot
    :return: The value found
    """
    if not varname.startswith("RW_"):
        raise ValueError(
            f"Variable {varname!r} is not a RunWhen platform variable, Use Import User Variable keyword instead."
        )
    val = os.getenv(varname)
    if not val:
        raise ImportError(f"Import Platform Variable: {varname} has no value defined.")
    return val
