## ADDED Requirements

### Requirement: Harvesting reads from the durable report store

Search-term harvesting SHALL store and load its search-term report rows through the durable `report-store` instead of the evictable `.cachesDirectory` cache, keyed by the same report cache key. The on-screen behavior (generate → score → review → apply) MUST be unchanged beyond gaining durability and participation in the nightly queue.

#### Scenario: Harvest report served from the durable store

- **WHEN** a search-term report for a campaign was previously fetched and stored
- **THEN** harvesting loads it from the store without re-running the async report lifecycle

### Requirement: Harvesting participates in the nightly queue as the heavy tail

Search-term harvesting reports SHALL be enqueued in the nightly background refresh after all profiles' spend-overview reports. Because they are heavy and the queue is resumable, they MAY complete across multiple nights rather than in a single window.

#### Scenario: Harvesting deferred behind overviews

- **WHEN** the nightly queue contains both overview and harvesting reports
- **THEN** harvesting reports are processed only after every profile's overview reports

#### Scenario: Heavy reports span multiple windows

- **WHEN** the background window ends before all harvesting reports are fetched
- **THEN** the remaining harvesting reports are resumed in a later window without restarting completed ones
