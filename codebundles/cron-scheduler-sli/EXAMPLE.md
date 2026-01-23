# Cron Scheduler SLI - Configuration Examples

This document provides practical examples of how to configure the Cron Scheduler SLI for various use cases.

## Two Main Usage Patterns

### Pattern 1: Self-Scheduling (No TARGET_SLX)
The SLI triggers the runbook of the same SLX it's attached to. This is the simplest and most common pattern.
- Just set `CRON_SCHEDULE`
- The SLI automatically uses the current SLX
- Perfect for scheduled maintenance, reports, backups, etc.

### Pattern 2: Cross-SLX Scheduling (With TARGET_SLX)
The SLI triggers a different SLX's runbook. Useful for centralized scheduling.
- Set both `CRON_SCHEDULE` and `TARGET_SLX`
- The SLI acts as a scheduler that triggers other SLXs
- Perfect for orchestrating multiple workflows

## Example 1: Self-Scheduling SLI (Triggers Its Own Runbook)

The simplest configuration - the SLI triggers the runbook of the SLX it's attached to:

### SLI Configuration
```yaml
CRON_SCHEDULE: "0 * * * *"
DRY_RUN: "false"
```

### What This Does
- Runs every hour at minute 0 (e.g., 1:00, 2:00, 3:00)
- Automatically uses the SLX this SLI is attached to (no TARGET_SLX needed)
- Automatically detects the SLI's run interval from the SLX spec
- Executes all tasks from the current SLX's runbook
- Perfect for scheduled maintenance tasks where the SLI and runbook are in the same SLX

## Example 2: Triggering a Different SLX

Schedule a database backup by triggering a different SLX:

### SLI Configuration
```yaml
CRON_SCHEDULE: "0 * * * *"
TARGET_SLX: "postgres-backup-slx"
DRY_RUN: "false"
```

### What This Does
- Runs every hour at minute 0
- Executes all tasks from the `postgres-backup-slx` runbook (different from the SLX this SLI is in)
- Automatically detects the SLI's run interval
- Useful when you have a central scheduler SLX that triggers other SLXs

## Example 3: Business Hours Health Check (Self-Scheduling)

Run health checks every 15 minutes during business hours (9 AM - 5 PM, Monday-Friday):

### SLI Configuration
```yaml
CRON_SCHEDULE: "*/15 9-17 * * 1-5"
DRY_RUN: "false"
```

### What This Does
- Runs every 15 minutes (at :00, :15, :30, :45) between 9 AM and 5 PM
- Only on weekdays (Monday=1 through Friday=5)
- Uses the current SLX (no TARGET_SLX needed)
- Executes the health check runbook during business hours only

## Example 4: Daily Report at 9 AM (Self-Scheduling)

Generate a daily report every morning at 9:00 AM:

### SLI Configuration
```yaml
CRON_SCHEDULE: "0 9 * * *"
DRY_RUN: "false"
```

### What This Does
- Runs once per day at 9:00 AM UTC
- Uses the current SLX's runbook
- Perfect for morning reports, daily summaries, etc.

## Example 5: Weekly Cleanup on Sundays (Self-Scheduling)

Run cleanup tasks every Sunday at midnight:

### SLI Configuration
```yaml
CRON_SCHEDULE: "0 0 * * 0"
DRY_RUN: "false"
```

### What This Does
- Runs once per week on Sunday (0) at midnight (00:00)
- Uses the current SLX's runbook
- Executes cleanup tasks like log rotation, temporary file cleanup, etc.

## Example 6: Every 5 Minutes Monitoring

Frequent monitoring check every 5 minutes:

### SLI Configuration
```yaml
CRON_SCHEDULE: "*/5 * * * *"
TARGET_SLX: "critical-service-monitor-slx"
DRY_RUN: "false"
```

### What This Does
- Runs every 5 minutes (at :00, :05, :10, :15, :20, :25, :30, :35, :40, :45, :50, :55)
- Executes monitoring checks for critical services
- Provides frequent status updates

## Example 7: Monthly Report on First Day

Generate a monthly report on the 1st of each month at 8:00 AM:

### SLI Configuration
```yaml
CRON_SCHEDULE: "0 8 1 * *"
TARGET_SLX: "monthly-report-slx"
DRY_RUN: "false"
```

### What This Does
- Runs once per month on the 1st day at 8:00 AM
- Perfect for monthly billing reports, usage summaries, etc.

## Example 8: Testing a New Schedule (Dry Run)

Before enabling a new schedule, test it first:

### SLI Configuration
```yaml
CRON_SCHEDULE: "30 */2 * * *"
TARGET_SLX: "new-maintenance-task-slx"
DRY_RUN: "true"
```

### What This Does
- Tests the schedule "30 */2 * * *" (every 2 hours at :30)
- Reports what would happen without actually executing the runbook
- Shows the next scheduled run time
- Validates the cron expression

### After Testing
Once you've verified the schedule is correct, change `DRY_RUN` to `"false"` to enable execution.

## Understanding the Timing Window

The `RUN_INTERVAL_SECONDS` parameter is important:

- If your SLI runs every 60 seconds, set `RUN_INTERVAL_SECONDS: "60"`
- The SLI will trigger if the current time is within this window of a scheduled time
- Example: With a 60-second window and schedule "0 * * * *" (hourly):
  - If the SLI runs at 3:00:30, it will trigger (30 seconds after 3:00:00)
  - If the SLI runs at 3:01:30, it won't trigger (90 seconds after 3:00:00)

## Troubleshooting

### Schedule Not Triggering

1. Check the SLI report for the "Next scheduled run" time
2. Verify your cron expression is valid
3. Ensure `RUN_INTERVAL_SECONDS` matches your SLI's actual run interval
4. Remember that cron schedules use UTC time

### Wrong SLX or Missing TARGET_SLX

If you see "Failed to trigger runbook execution" or "Could not determine TARGET_SLX":
1. If using TARGET_SLX, verify the short name is correct
2. If not using TARGET_SLX, ensure the SLI is attached to an SLX
3. Check that the target SLX exists in your workspace
4. Ensure the target SLX has a runbook configured

## Advanced Patterns

### Multiple Schedules for the Same SLX

If you need multiple schedules, create multiple SLI instances with different cron expressions:

- SLI 1: `CRON_SCHEDULE: "0 9 * * *"` (morning run)
- SLI 2: `CRON_SCHEDULE: "0 17 * * *"` (evening run)
- Both targeting the same `TARGET_SLX`

### Coordinating Multiple Tasks

To run multiple different tasks on the same schedule:
1. Create a "coordinator" runbook that calls other runbooks
2. Set that as your `TARGET_SLX`
3. The coordinator runbook can then trigger multiple other SLXs in sequence
