# Cron Scheduler SLI

A generic SLI codebundle that functions as a cron scheduler, allowing you to run a runbook on a regular schedule based on cron expressions.

## Overview

This SLI runs on a regular interval (typically every 60 seconds) and checks if the current time matches a configured cron schedule. When the schedule matches (within the run interval window), it automatically executes all tasks from the runbook attached to a specified SLX.

## Use Cases

- **Scheduled Maintenance**: Run maintenance tasks at specific times (e.g., "0 2 * * *" for 2 AM daily)
- **Periodic Health Checks**: Execute health checks at regular intervals (e.g., "*/15 * * * *" for every 15 minutes)
- **Hourly Reports**: Generate reports on the hour (e.g., "0 * * * *")
- **Weekly Cleanup**: Run cleanup tasks weekly (e.g., "0 0 * * 0" for Sunday midnight)
- **Business Hours Automation**: Run tasks only during business hours (e.g., "0 9-17 * * 1-5" for 9 AM-5 PM weekdays)

## How It Works

1. The SLI runs at its configured interval (default: every 60 seconds)
2. On each run, it checks if the current time matches the cron schedule
3. If the time matches (within the run interval window), it:
   - Looks up the runbook attached to the target SLX (or current SLX if TARGET_SLX not specified)
   - Executes all tasks from that runbook
   - Pushes a metric indicating success or failure
4. If the time doesn't match, it reports the next scheduled run time

## Usage Patterns

### Self-Scheduling (Most Common)
The simplest pattern - the SLI triggers its own runbook:
- Don't specify `TARGET_SLX` (leave it empty)
- The SLI automatically uses the SLX it's attached to
- Perfect for scheduled tasks where the SLI and runbook are together

### Cross-SLX Scheduling
For more complex orchestration:
- Specify `TARGET_SLX` to trigger a different SLX's runbook
- Useful for centralized scheduling or coordinating multiple workflows

## Configuration

### Required Variables

- **CRON_SCHEDULE** - The cron schedule expression
  - Format: Standard 5-field cron expression (minute hour day month weekday)
  - Example: `0 */2 * * *` (every 2 hours at minute 0)
  - Example: `*/15 * * * *` (every 15 minutes)
  - Example: `0 9 * * 1-5` (9 AM on weekdays)
  - Default: `0 * * * *` (every hour)

### Optional Variables

- **TARGET_SLX** - The short name of the target SLX whose runbook should be executed
  - This is the SLX shortName (not the full name with workspace prefix)
  - **If not provided, uses the current SLX** (the SLX this SLI is attached to)
  - This allows the SLI to trigger its own runbook on a schedule
  - Example: `my-maintenance-slx`
  - Default: Current SLX (auto-detected)

- **DRY_RUN** - Set to `true` to test without executing the runbook (default: `false`)
  - When enabled, the SLI will check the schedule and report what would happen
  - Useful for testing cron expressions before enabling execution

## Cron Expression Format

The cron schedule uses the standard 5-field format:

```
* * * * *
│ │ │ │ │
│ │ │ │ └─── Day of week (0-6, Sunday=0)
│ │ │ └───── Month (1-12)
│ │ └─────── Day of month (1-31)
│ └───────── Hour (0-23)
└─────────── Minute (0-59)
```

### Common Examples

- `0 * * * *` - Every hour at minute 0
- `*/15 * * * *` - Every 15 minutes
- `0 */2 * * *` - Every 2 hours
- `0 9 * * *` - Every day at 9 AM
- `0 9 * * 1-5` - Every weekday at 9 AM
- `0 0 * * 0` - Every Sunday at midnight
- `30 14 1 * *` - 2:30 PM on the 1st of every month
- `0 9-17 * * 1-5` - Every hour from 9 AM to 5 PM on weekdays

## Metrics

The SLI pushes a metric with the following values:

- **1** - Runbook was successfully executed
- **0** - Not time to run yet (schedule not matched)
- **-1** - Execution failed (runbook trigger failed)

You can use these metrics to:
- Monitor successful executions
- Alert on execution failures
- Track scheduling accuracy

## Example Configurations

### Self-Scheduling (Simple)

```yaml
CRON_SCHEDULE: "0 * * * *"
DRY_RUN: "false"
```

This will execute the current SLX's runbook every hour at minute 0.

### Cross-SLX Scheduling

```yaml
CRON_SCHEDULE: "0 * * * *"
TARGET_SLX: "database-maintenance"
DRY_RUN: "false"
```

This will execute the `database-maintenance` SLX's runbook every hour at minute 0.

### Daily Report at 9 AM

```yaml
CRON_SCHEDULE: "0 9 * * *"
TARGET_SLX: "daily-report-generator"
RUN_INTERVAL_SECONDS: "60"
DRY_RUN: "false"
```

This will execute the `daily-report-generator` runbook every day at 9:00 AM.

### Every 15 Minutes Health Check

```yaml
CRON_SCHEDULE: "*/15 * * * *"
TARGET_SLX: "service-health-check"
RUN_INTERVAL_SECONDS: "60"
DRY_RUN: "false"
```

This will execute the `service-health-check` runbook every 15 minutes.

## Testing

To test your cron schedule without executing the runbook:

1. Set `DRY_RUN: "true"`
2. Run the SLI and check the report
3. Verify the cron schedule is valid and the next run time is correct
4. Once confirmed, set `DRY_RUN: "false"` to enable execution

## Notes

- The SLI checks if the current time is within `RUN_INTERVAL_SECONDS` of a scheduled cron time
- This means if your SLI runs every 60 seconds, it will trigger if within 60 seconds of the scheduled time
- Ensure your `RUN_INTERVAL_SECONDS` matches your actual SLI run interval for accurate scheduling
- The cron schedule uses UTC time by default
- Invalid cron expressions will cause the SLI to fail with an error message

## Troubleshooting

### Runbook Not Executing

- Verify the `TARGET_SLX` short name is correct
- Check that the target SLX has a runbook configured
- Ensure the SLI has permissions to execute tasks in the workspace
- Review the SLI report for error messages

### Schedule Not Matching

- Verify your cron expression is valid using the "Validate Cron Schedule" output
- Check the "Next scheduled run" time in the report
- Check the "Detected SLI interval" in the report to see what interval was auto-detected
- Remember that cron schedules use UTC time

### Testing Cron Expressions

Use `DRY_RUN: "true"` to test your cron expression:
- The SLI will validate the expression
- It will show the next scheduled run time
- It will report whether the current time matches
- No runbook execution will occur
