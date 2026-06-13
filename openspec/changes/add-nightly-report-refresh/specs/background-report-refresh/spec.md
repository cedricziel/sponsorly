## ADDED Requirements

### Requirement: Single background processing task

The app SHALL register exactly one `BGProcessingTask` identifier (e.g. `com.cedricziel.sponsorly.nightly-refresh`) for warming report data. It MUST request execution that requires external power (charging) and SHOULD permit network access. The task identifier MUST be declared in `BGTaskSchedulerPermittedIdentifiers`, and `UIBackgroundModes` MUST include `processing`. The app MUST NOT register multiple distinct background-refresh task identifiers.

#### Scenario: Task registered at launch

- **WHEN** the app launches
- **THEN** it registers a handler for the single nightly-refresh task identifier with the scheduler

#### Scenario: Scheduled to run overnight while charging

- **WHEN** the app schedules the task
- **THEN** the request requires external power and sets an `earliestBeginDate` in the future (treated as a floor, not a guaranteed run time)

### Requirement: Prioritized, resumable work queue

When the task runs, it SHALL drain a single prioritized work queue in this order: (1) the active profile's spend-overview reports, (2) other connected profiles' spend-overview reports, (3) heavy reports such as search-term harvesting. The queue covers all connected profiles × all report types. After each item the task MUST check the expiration handler / remaining time; if the window is cut short it MUST persist progress and reschedule itself to continue with the remaining items.

#### Scenario: Priority ordering

- **WHEN** the queue is built for multiple connected profiles
- **THEN** the active profile's spend-overview items are processed before other profiles' overviews, and harvesting reports are processed last

#### Scenario: Window cut short mid-queue

- **WHEN** the OS expiration handler fires before the queue is empty
- **THEN** the task marks the in-flight item as not-completed, stops cleanly, and schedules a follow-up task so the remaining items run in a later window

#### Scenario: Progress persists across windows

- **WHEN** the task ran in a prior window and completed some items
- **THEN** a subsequent run skips already-fresh items and resumes with the still-stale ones (no full restart)

### Requirement: Reschedule lifecycle

When the queue drains with time remaining, the task SHALL reschedule itself for the next night. The task MUST mark its `BGTask` completed (success or not) exactly once. A new request MUST be scheduled on app background/launch so refresh continues even if a prior window was skipped.

#### Scenario: Queue fully drained

- **WHEN** the task finishes all queued items
- **THEN** it completes the current task as successful and schedules the next nightly request

#### Scenario: Task never ran (OS skipped the window)

- **WHEN** the device was not in a state allowing the task to run
- **THEN** the next time the app schedules, a fresh request is enqueued and freshness is not falsely implied to the user

### Requirement: Headless authentication

The task SHALL refresh reports without user interaction. The LWA refresh token MUST be readable from the Keychain while the device is locked after first unlock (`AfterFirstUnlock` accessibility), and the token exchange and report fetches reuse the same repositories used on-screen. A profile whose token cannot be refreshed MUST be skipped and recorded as `failed` for its entries without aborting the whole queue.

#### Scenario: Token refresh while locked

- **WHEN** the task runs while the device is locked but has been unlocked since boot
- **THEN** it reads the refresh token, obtains an access token, and fetches reports

#### Scenario: One profile's auth fails

- **WHEN** a connected profile's token cannot be refreshed
- **THEN** that profile's items are skipped and marked `failed`, and the queue continues with the remaining profiles

### Requirement: Background work reuses the durable store and repositories

The task SHALL write all fetched results into the `report-store`, reusing the same `ReportingRepository` lifecycle (create → poll → download → decode) used on-screen. It MUST NOT hand-roll Amazon Ads requests. While an item is being fetched, its store entry status SHOULD be `refreshing`.

#### Scenario: Results land in the durable store

- **WHEN** the task fetches a report for a profile
- **THEN** the decoded rows are written to the `report-store` with `refreshedAt` updated, so the next app open renders them without a network fetch
