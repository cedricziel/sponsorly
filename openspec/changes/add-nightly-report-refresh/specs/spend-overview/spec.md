## ADDED Requirements

### Requirement: Overview reads from the durable report store

The spend overview SHALL read its cached report rows from the durable `report-store` instead of the evictable `.cachesDirectory` cache. On appear it renders any stored rows immediately, then performs a top-up refresh that writes back into the store. When the nightly background task has already warmed the store, opening the overview MUST render without waiting on a network fetch.

#### Scenario: Warm open after nightly refresh

- **WHEN** the nightly task warmed the active profile's overview overnight and the user opens the overview
- **THEN** the headline, trend, and top campaigns render immediately from the store with no on-screen wait

#### Scenario: Cold open still works

- **WHEN** no stored entry exists for the current window
- **THEN** the overview fetches it on appear exactly as before, then stores the result

### Requirement: Report freshness indicator

The overview SHALL display the age of the data it is showing (e.g. "Updated 6h ago"), derived from the store entry's `refreshedAt`. It MUST NOT imply live freshness when the data is stale, since the background task's run time is OS-governed and not guaranteed.

#### Scenario: Age shown from stored timestamp

- **WHEN** the overview renders rows whose store entry was refreshed earlier
- **THEN** it shows a relative "last updated" age based on `refreshedAt`

#### Scenario: Stale data is not presented as live

- **WHEN** the stored data is older than the expected refresh cadence
- **THEN** the overview communicates staleness rather than implying the figures are current
