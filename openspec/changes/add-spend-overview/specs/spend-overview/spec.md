## ADDED Requirements

### Requirement: Spend & efficiency headline

The app SHALL show, for the active profile, the last-30-days total **spend**, **sales**, and **ACOS** (spend ÷ sales, shown as a percentage), sourced from an async Sponsored Products report grouped by campaign and summed.

#### Scenario: Headline shown for the active profile

- **WHEN** an active profile is selected and the Reports tab is opened
- **THEN** the app shows the 30-day total spend, sales, and ACOS for that profile

#### Scenario: ACOS with zero sales

- **WHEN** the period has spend but no attributed sales
- **THEN** ACOS SHALL be shown as not-applicable (e.g. "—") rather than a division-by-zero value

#### Scenario: No active profile

- **WHEN** no active profile is selected
- **THEN** the Reports tab SHALL prompt the user to select an account instead of loading data

### Requirement: Live "today" spend

The app SHALL show an approximate "today so far" spend for the active profile, derived from the synchronous budget-usage endpoint (per-campaign `budget × budgetUsagePercent`, summed), independent of the async report pipeline.

#### Scenario: Today tile is live

- **WHEN** the overview loads
- **THEN** the today tile reflects current budget usage without waiting for an async report to generate

### Requirement: 30-day spend trend

The app SHALL show a daily spend trend for the last 30 days for the active profile, rendered as a chart, sourced from a daily-granularity report.

#### Scenario: Trend rendered

- **WHEN** the daily report is available
- **THEN** the app renders a 30-day spend-per-day chart

### Requirement: Top campaigns by spend

The app SHALL list the active profile's top campaigns by spend for the period, each with its spend and ACOS, from the campaign-grouped report.

#### Scenario: Top campaigns listed

- **WHEN** the campaign-grouped report is available
- **THEN** the app lists campaigns ordered by descending spend, each showing spend and ACOS

### Requirement: Asynchronous report retrieval with caching

The app SHALL retrieve performance data via the async report lifecycle (create → poll until completed → download → decompress → decode), SHALL cache completed reports for immutable past-day ranges so the overview can render previously fetched data immediately, and SHALL refresh in the background.

#### Scenario: Cached data shown immediately, then refreshed

- **WHEN** the overview opens and a cached report for the range exists
- **THEN** the app shows the cached figures immediately and refreshes them in the background

#### Scenario: Report still generating

- **WHEN** a requested report has not finished generating
- **THEN** the app SHALL keep polling (with backoff) and indicate that data is updating, without blocking the rest of the screen

#### Scenario: Report generation fails or times out

- **WHEN** report generation fails or exceeds the polling budget
- **THEN** the app SHALL surface a non-blocking error with a retry, keeping any cached data visible

### Requirement: Overview refresh and loading feedback

The app SHALL let the user pull-to-refresh the overview and SHALL show a loading indicator while data is being fetched, keeping any already-shown content visible during a refresh.

#### Scenario: Pull to refresh

- **WHEN** the user pull-to-refreshes the overview
- **THEN** the app refetches the live today tile and re-requests the reports, updating the tiles, trend, and top campaigns when ready
