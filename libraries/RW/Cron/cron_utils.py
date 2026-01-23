"""
Cron utilities for parsing and checking cron schedules.

This module provides Robot Framework keywords for working with cron schedules.
"""

from datetime import datetime, timezone
from typing import Optional
from robot.api.deco import keyword
from robot.libraries.BuiltIn import BuiltIn

try:
    from croniter import croniter
except ImportError:
    croniter = None

# ──────────────────────────────────────────────────────────────────────────────
# Module-level constants
# ──────────────────────────────────────────────────────────────────────────────
ROBOT_LIBRARY_SCOPE = "GLOBAL"


@keyword("Check Cron Schedule Match")
def check_cron_schedule_match(
    cron_schedule: str,
    interval_seconds: int = 60,
    base_time: Optional[datetime] = None
) -> bool:
    """
    Check if the current time matches the given cron schedule within the interval window.
    
    Args:
        cron_schedule: A cron schedule expression (e.g., "0 */2 * * *" for every 2 hours)
        interval_seconds: The run interval in seconds (default: 60). The check will pass
                         if we're within this many seconds of a scheduled cron time.
        base_time: Optional datetime to check against (defaults to current UTC time)
    
    Returns:
        True if the current time is within interval_seconds of a scheduled cron time,
        False otherwise.
    
    Example:
        ${is_time}=    Check Cron Schedule Match    0 */2 * * *    60
        IF    ${is_time}
            Log    Time to run the scheduled task!
        END
    """
    if croniter is None:
        BuiltIn().log("croniter library not installed. Install with: pip install croniter", level="ERROR")
        return False
    
    if not cron_schedule or not cron_schedule.strip():
        BuiltIn().log("Empty cron schedule provided", level="WARN")
        return False
    
    # Validate cron expression
    if not croniter.is_valid(cron_schedule):
        BuiltIn().log(f"Invalid cron schedule: {cron_schedule}", level="ERROR")
        return False
    
    # Use provided time or current UTC time
    if base_time is None:
        base_time = datetime.now(timezone.utc)
    
    try:
        # Create croniter instance
        cron = croniter(cron_schedule, base_time)
        
        # Get the previous scheduled time
        prev_time = cron.get_prev(datetime)
        
        # Calculate the difference in seconds
        time_diff = abs((base_time - prev_time).total_seconds())
        
        # Check if we're within the interval window AFTER the scheduled time
        # This ensures we only trigger at or after the scheduled time, not before
        is_match = time_diff <= interval_seconds
        
        if is_match:
            BuiltIn().log(
                f"Cron schedule matched! Schedule: {cron_schedule}, "
                f"Last run time: {prev_time.isoformat()}, "
                f"Current time: {base_time.isoformat()}, "
                f"Difference: {time_diff:.1f}s (threshold: {interval_seconds}s)",
                level="INFO"
            )
        else:
            BuiltIn().log(
                f"Cron schedule not matched. Schedule: {cron_schedule}, "
                f"Last run time: {prev_time.isoformat()}, "
                f"Current time: {base_time.isoformat()}, "
                f"Difference: {time_diff:.1f}s (threshold: {interval_seconds}s)",
                level="DEBUG"
            )
        
        return is_match
        
    except Exception as e:
        BuiltIn().log(f"Error checking cron schedule: {str(e)}", level="ERROR")
        return False


@keyword("Get Next Cron Run Time")
def get_next_cron_run_time(
    cron_schedule: str,
    base_time: Optional[datetime] = None
) -> Optional[str]:
    """
    Get the next scheduled run time for the given cron schedule.
    
    Args:
        cron_schedule: A cron schedule expression
        base_time: Optional datetime to calculate from (defaults to current UTC time)
    
    Returns:
        ISO format string of the next run time, or None if there's an error
    
    Example:
        ${next_run}=    Get Next Cron Run Time    0 */2 * * *
        Log    Next scheduled run: ${next_run}
    """
    if croniter is None:
        BuiltIn().log("croniter library not installed", level="ERROR")
        return None
    
    if not cron_schedule or not cron_schedule.strip():
        BuiltIn().log("Empty cron schedule provided", level="WARN")
        return None
    
    if not croniter.is_valid(cron_schedule):
        BuiltIn().log(f"Invalid cron schedule: {cron_schedule}", level="ERROR")
        return None
    
    if base_time is None:
        base_time = datetime.now(timezone.utc)
    
    try:
        cron = croniter(cron_schedule, base_time)
        next_time = cron.get_next(datetime)
        return next_time.isoformat()
    except Exception as e:
        BuiltIn().log(f"Error getting next cron run time: {str(e)}", level="ERROR")
        return None


@keyword("Validate Cron Schedule")
def validate_cron_schedule(cron_schedule: str) -> bool:
    """
    Validate if a cron schedule expression is valid.
    
    Args:
        cron_schedule: A cron schedule expression to validate
    
    Returns:
        True if valid, False otherwise
    
    Example:
        ${is_valid}=    Validate Cron Schedule    0 */2 * * *
        IF    not ${is_valid}
            Fail    Invalid cron schedule provided
        END
    """
    if croniter is None:
        BuiltIn().log("croniter library not installed", level="ERROR")
        return False
    
    if not cron_schedule or not cron_schedule.strip():
        return False
    
    return croniter.is_valid(cron_schedule)
