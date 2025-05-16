"""
Workspace keyword library for performing tasks for interacting with Workspace resources.

Scope: Global
"""

import re, logging, json, jmespath, requests, os, time
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
    # ------------------------------------------------------------------ #
    # 1)  Gather workspace-scoped variables
    # ------------------------------------------------------------------ #
    try:
        rw_workspace        = import_platform_variable("RW_WORKSPACE")
        rw_workspace_api_url = import_platform_variable("RW_WORKSPACE_API_URL")
    except ImportError:
        return []

    # ------------------------------------------------------------------ #
    # 2)  Fetch all SLXs for the workspace
    # ------------------------------------------------------------------ #
    session = platform.get_authenticated_session()
    url     = f"{rw_workspace_api_url}/{rw_workspace}/slxs"

    try:
        resp = session.get(url, timeout=10)
        resp.raise_for_status()
        all_slxs = resp.json().get("results", [])
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


    # ── 2.  Normalise search set once  ──────────────────────────────────────
    wanted = {
        (t["name"].lower(), str(t["value"]).lower())
        for t in tag_list
        if isinstance(t, dict) and t.get("name") is not None
    }

    if not wanted:
        return []

    # ── 3.  Fetch SLXs ──────────────────────────────────────────────────────
    session = platform.get_authenticated_session()
    url     = f"{rw_workspace_api_url}/{rw_workspace}/slxs"

    try:
        resp = session.get(url, timeout=10)
        resp.raise_for_status()
        results = resp.json().get("results", [])
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

    # ── 4.  Filter in a single pass ─────────────────────────────────────────
    matches = []
    for slx in results:
        for tag in slx.get("spec", {}).get("tags", []):
            pair = (tag.get("name", "").lower(), str(tag.get("value", "")).lower())
            if pair in wanted:
                matches.append(slx)
                break                    # stop after first hit for this SLX

    return matches
    # s = platform.get_authenticated_session()
    # url = f"{rw_workspace_api_url}/{rw_workspace}/slxs"
    # matching_slxs = []

    # try:
    #     response = s.get(url, timeout=10)
    #     response.raise_for_status()  # Ensure we raise an exception for bad responses
    #     all_slxs = response.json()  # Parse the JSON content
    #     results = all_slxs.get("results", [])

    #     for result in results:
    #         tags = result.get("spec", {}).get("tags", [])
    #         for tag in tags:
    #             if any(
    #                 tag_item["name"] == tag["name"]
    #                 and tag_item["value"] == tag["value"]
    #                 for tag_item in tag_list
    #             ):
    #                 matching_slxs.append(result)
    #                 break

    #     return matching_slxs
    # except (
    #     requests.ConnectTimeout,
    #     requests.ConnectionError,
    #     json.JSONDecodeError,
    # ) as e:
    #     warning_log(
    #         f"Exception while trying to get SLXs in workspace {rw_workspace}: {e}",
    #         str(e),
    #         str(type(e)),
    #     )
    #     platform_logger.exception(e)
    #     return []


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

def import_runsession_details(rw_runsession=None):
    """
    Fetch full RunSession details in JSON format.
    If RW_USER_TOKEN is set, use it instead of the built-in token,
    which can be useful for testing.

    :param rw_runsession: (optional) The run session ID to fetch. 
                          If not provided, uses RW_SESSION_ID from platform variables.
    :return: JSON-encoded string of the run session details or None on error.
    """
    try:
        if not rw_runsession:
            rw_runsession = import_platform_variable("RW_SESSION_ID")

        rw_workspace = import_platform_variable("RW_WORKSPACE")
        rw_workspace_api_url = import_platform_variable("RW_WORKSPACE_API_URL")
    except ImportError:
        BuiltIn().log("Failure importing required variables", level='WARN')
        return None

    url = f"{rw_workspace_api_url}/{rw_workspace}/runsessions/{rw_runsession}"
    BuiltIn().log(f"Importing runsession variable with URL: {url}, runsession {rw_runsession}", level='INFO')
    
    # Use RW_USER_TOKEN if it is set, otherwise use the authenticated session
    user_token = os.getenv("RW_USER_TOKEN")
    if user_token:
        headers = {"Authorization": f"Bearer {user_token}"}
        session = requests.Session()
        session.headers.update(headers)
    else:
        session = platform.get_authenticated_session()

    try:
        rsp = session.get(url, timeout=10, verify=platform.REQUEST_VERIFY)
        rsp.raise_for_status()
        return json.dumps(rsp.json())
    except (requests.ConnectTimeout, requests.ConnectionError, json.JSONDecodeError) as e:
        warning_log(f"Exception while trying to get runsession details: {e}", str(e), str(type(e)))
        platform_logger.exception(e)
        return json.dumps(None)



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

def import_related_runsession_details(
    json_string: str,
    api_token: platform.Secret = None,
    poll_interval: float = 5.0,
    max_wait_seconds: float = 300.0
) -> str:
    """
    This keyword:
      1. Parses the provided JSON string into a Python dictionary.
      2. Extracts the 'runsessionId' from the 'notes' field in the dictionary.
      3. Polls the indicated RunSession until the runRequests stop growing for
         three consecutive checks, or until max_wait_seconds passes.
      4. Returns the final RunSession JSON (as a string) once stable, or None on error
         (and raises a TimeoutError if stability is never reached).

    :param json_string: (str) The full JSON of some record containing 'notes',
                        which in turn contains a 'runsessionId'.
    :param api_token: (platform.Secret) Optional. If provided, will be used as the bearer token
                      for the polling requests. Otherwise, logic will attempt to use
                      RW_USER_TOKEN or the default platform-authenticated session.
    :param poll_interval: (float) Seconds to sleep between polls. Defaults to 5s.
    :param max_wait_seconds: (float) Maximum total seconds before timing out. Defaults to 300s.
    :return: (str) JSON-encoded string containing the final RunSession details once stable,
                   or None if there's an error fetching it.
    :raises TimeoutError: If the RunSession never stabilizes within max_wait_seconds.
    """

    # 1) Parse out the runsessionId from the JSON string
    data = json.loads(json_string)
    notes_str = data.get("notes", "{}")
    try:
        notes_data = json.loads(notes_str)
    except json.JSONDecodeError:
        BuiltIn().log("Unable to parse 'notes' field as JSON. Returning None.", level="WARN")
        return None

    runsession_id = notes_data.get("runsessionId")
    if not runsession_id:
        BuiltIn().log(
            "No 'runsessionId' found in 'notes' field. Returning None.", 
            level="WARN"
        )
        return None

    # 2) Gather workspace/env variables needed for polling
    try:
        rw_workspace = import_platform_variable("RW_WORKSPACE")
        rw_workspace_api_url = import_platform_variable("RW_WORKSPACE_API_URL")
    except ImportError as e:
        BuiltIn().log(f"Failure importing required variables: {e}", level="WARN")
        return None

    # Build the endpoint URL
    endpoint = f"{rw_workspace_api_url}/{rw_workspace}/runsessions/{runsession_id}"

    BuiltIn().log(f"Polling RunSession for stability: {endpoint}", level="INFO")

    # 3) Construct a requests.Session that uses either:
    #    - The explicitly-provided api_token (platform.Secret) if given
    #    - The RW_USER_TOKEN if set
    #    - Otherwise, the default platform.get_authenticated_session()
    if api_token:
        # Use the platform.Secret for Bearer auth
        headers = {
            "Authorization": f"Bearer {api_token.value}",
            "Accept": "application/json"
        }
        session = requests.Session()
        session.headers.update(headers)
    else:
        user_token = os.getenv("RW_USER_TOKEN")
        if user_token:
            session = requests.Session()
            session.headers.update({"Authorization": f"Bearer {user_token}"})
        else:
            session = platform.get_authenticated_session()

    stable_count = 0
    last_length = None
    start_time = time.time()

    # 4) Poll the RunSession until stable or timeout
    while True:
        try:
            resp = session.get(endpoint, timeout=10, verify=platform.REQUEST_VERIFY)
            resp.raise_for_status()
            session_data = resp.json()
        except (requests.RequestException, json.JSONDecodeError) as e:
            BuiltIn().log(
                f"Error fetching RunSession {runsession_id}: {e}",
                level="WARN"
            )
            return None

        # Count the runRequests
        run_requests = session_data.get("runRequests", [])
        current_length = len(run_requests)

        # Check if count is stable
        if last_length is not None and current_length == last_length:
            stable_count += 1
        else:
            stable_count = 0
        last_length = current_length

        # If stable for 3 consecutive polls, return
        if stable_count >= 3:
            BuiltIn().log(
                f"RunSession {runsession_id} is stable with {current_length} runRequests.",
                level="INFO"
            )
            return json.dumps(session_data)  # return the final JSON as a string

        # Check for timeout
        elapsed = time.time() - start_time
        if elapsed > max_wait_seconds:
            raise TimeoutError(
                f"RunSession {runsession_id} did not stabilize within {max_wait_seconds} seconds."
            )

        # Sleep before next poll
        time.sleep(poll_interval)

def get_slxs_with_entity_reference(
    entity_refs: list[str],
) -> list:
    """Return all SLXs that reference (by alias, tag, configProvided, or additionalContext)
    any of the entity identifiers in *entity_refs*.

    Args:
        entity_refs (list[str]): Identifiers (e.g. “CUSTOM_DEVICE-…”, resource names, etc.)
                                 to look for.  Matching is **case-insensitive** and done
                                 with simple substring search.

    Returns:
        list: SLX objects that contain at least one of the identifiers.
    """
    # ------------------------------------------------------------------ #
    # 1)  Gather workspace-scoped variables
    # ------------------------------------------------------------------ #
    try:
        rw_workspace        = import_platform_variable("RW_WORKSPACE")
        rw_workspace_api_url = import_platform_variable("RW_WORKSPACE_API_URL")
    except ImportError:
        return []

    # ------------------------------------------------------------------ #
    # 2)  Fetch all SLXs for the workspace
    # ------------------------------------------------------------------ #
    session = platform.get_authenticated_session()
    url     = f"{rw_workspace_api_url}/{rw_workspace}/slxs"

    try:
        resp = session.get(url, timeout=10)
        resp.raise_for_status()
        all_slxs = resp.json().get("results", [])
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

    # ------------------------------------------------------------------ #
    # 3)  Build a lowercase set of search terms for fast membership tests
    # ------------------------------------------------------------------ #
    search_terms = {s.lower() for s in entity_refs if isinstance(s, str) and s}

    # ------------------------------------------------------------------ #
    # 4)  Scan each SLX for any occurrence of the search terms
    # ------------------------------------------------------------------ #
    matching_slxs: list = []

    for slx in all_slxs:
        spec = slx.get("spec", {})
        corpus = [spec.get("alias", "")]

        # b) tags
        for t in spec.get("tags", []):
            name  = t.get("name", "")
            value = t.get("value", "")
            corpus.extend([name, value, f"{name}:{value}"])   # <- add pair

        # c) configProvided
        for cp in spec.get("configProvided", []):
            name  = cp.get("name", "")
            value = cp.get("value", "")
            corpus.extend([name, value, f"{name}:{value}"])   # <- add pair

        # d) additionalContext
        add_ctx = spec.get("additionalContext", {})
        for k, v in add_ctx.items():
            corpus.extend([k, str(v), f"{k}:{v}"])            # <- add pair

        joined = " ".join(corpus).lower()
        if any(term in joined for term in search_terms):
            matching_slxs.append(slx)

    return matching_slxs

def perform_task_search_with_persona(
    query: str,
    persona: str,
    slx_scope: list = None,
) -> dict:
    """
    Perform a task search in the current workspace using a specific persona.

    :param query: The search query (string).
    :param persona: Persona shortname or fully-qualified (<workspace>--<persona>).
    :param slx_scope: A list of slxShortNames to limit the search scope (optional).

    :return: Parsed JSON response from the task-search endpoint.
    """
    try:
        rw_workspace = import_platform_variable("RW_WORKSPACE")
        rw_workspace_api_url = import_platform_variable("RW_WORKSPACE_API_URL")
    except ImportError as e:
        BuiltIn().log(f"Missing required platform variables: {e}", level="WARN")
        return {}

    # Normalize persona
    if "--" not in persona:
        persona = f"{rw_workspace}--{persona}"

    if slx_scope is None:
        slx_scope = []

    url = f"{rw_workspace_api_url}/{rw_workspace}/task-search"
    payload = {
        "query": [query],
        "scope": slx_scope,
        "persona": persona
    }

    user_token = os.getenv("RW_USER_TOKEN")
    if user_token:
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {user_token}"
        }
        session = requests.Session()
        session.headers.update(headers)
    else:
        session = platform.get_authenticated_session()

    BuiltIn().log(f"POST {url} with payload: {json.dumps(payload)}", level="INFO")

    try:
        response = session.post(url, json=payload, timeout=10, verify=platform.REQUEST_VERIFY)
        response.raise_for_status()
        return response.json()
    except (requests.RequestException, json.JSONDecodeError) as e:
        BuiltIn().log(f"Task search (with persona) failed: {e}", level="WARN")
        platform_logger.exception(e)
        return {}


def perform_task_search(
    query: str,
    slx_scope: list = None,
) -> dict:
    """
    Perform a task search in the current workspace with no persona.

    :param query: The search query (string).
    :param slx_scope: A list of slxShortNames to limit the search scope (optional).

    :return: Parsed JSON response from the task-search endpoint.
    """
    try:
        rw_workspace = import_platform_variable("RW_WORKSPACE")
        rw_workspace_api_url = import_platform_variable("RW_WORKSPACE_API_URL")
    except ImportError as e:
        BuiltIn().log(f"Missing required platform variables: {e}", level="WARN")
        return {}

    if slx_scope is None:
        slx_scope = []

    url = f"{rw_workspace_api_url}/{rw_workspace}/task-search"
    payload = {
        "query": [query],
        "scope": slx_scope
        # Notice: no 'persona' key here
    }

    user_token = os.getenv("RW_USER_TOKEN")
    if user_token:
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {user_token}"
        }
        session = requests.Session()
        session.headers.update(headers)
    else:
        session = platform.get_authenticated_session()

    BuiltIn().log(f"POST {url} with payload (no persona): {json.dumps(payload)}", level="INFO")

    try:
        response = session.post(url, json=payload, timeout=10, verify=platform.REQUEST_VERIFY)
        response.raise_for_status()
        return response.json()
    except (requests.RequestException, json.JSONDecodeError) as e:
        BuiltIn().log(f"Task search (no persona) failed: {e}", level="WARN")
        platform_logger.exception(e)
        return {}
