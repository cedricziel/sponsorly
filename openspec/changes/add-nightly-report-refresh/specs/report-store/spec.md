## ADDED Requirements

### Requirement: Durable report persistence

The system SHALL persist decoded report rows in a store located in Application Support (or another directory the OS does not evict under storage pressure), keyed by the full report cache key: `profileId`, `reportTypeId`, `startDate`, `endDate`, and `timeUnit`. Stored entries MUST survive app termination and OS storage-pressure eviction, unlike the previous `.cachesDirectory` cache.

#### Scenario: Saved report survives storage pressure

- **WHEN** a report is saved to the store and the OS would evict caches under storage pressure
- **THEN** the stored entry remains readable on the next launch

#### Scenario: Round-trip by cache key

- **WHEN** rows are saved for a given cache key and later loaded with the same key
- **THEN** the store returns the identical decoded rows

#### Scenario: Distinct keys do not collide

- **WHEN** two reports differ only in `timeUnit` (e.g. `SUMMARY` vs `DAILY`)
- **THEN** they are stored and retrieved as separate entries

### Requirement: Per-entry freshness metadata

Each stored entry SHALL carry a `refreshedAt` timestamp and a `status` of `fresh`, `stale`, `refreshing`, or `failed`. The store SHALL expose queries to list entries by staleness so that callers and the background refresh queue can decide what to fetch.

#### Scenario: Freshness recorded on save

- **WHEN** rows are saved
- **THEN** the entry's `refreshedAt` is set to the save time and `status` is `fresh`

#### Scenario: Staleness query

- **WHEN** the store is asked for stale entries given a staleness rule (e.g. a report whose date window now ends before yesterday, or `refreshedAt` older than a threshold)
- **THEN** it returns only the entries that match, excluding entries currently marked `refreshing`

#### Scenario: Failure is recorded, last-good payload retained

- **WHEN** a refresh attempt for an existing entry fails
- **THEN** the entry's `status` becomes `failed` while its previously stored payload remains loadable

### Requirement: Single serialized store owner under strict concurrency

The store SHALL be a `@ModelActor` (or equivalent single serialized owner of the SwiftData `ModelContext`) so the off-main-actor background task and the `@MainActor` view models can read and write through it without violating `SWIFT_STRICT_CONCURRENCY=complete`. Callers MUST NOT share a raw `ModelContext` across isolation boundaries.

#### Scenario: Concurrent access from background and UI

- **WHEN** the background refresh task writes an entry while a view model reads from the store
- **THEN** both operations complete without a data race and the reader observes a consistent entry

### Requirement: Drop-in replacement for the cache-first read path

The store SHALL support the existing cache-first-then-refresh call pattern: callers load any stored rows for a key immediately (rendering them), then trigger a refresh that saves back into the store. Replacing `ReportCache` with the store MUST NOT change the observable behavior of the spend overview or harvesting features beyond added durability and freshness metadata.

#### Scenario: Cache-first render then refresh

- **WHEN** a view model loads a key that has a stored entry and then completes a network refresh
- **THEN** the stored rows render first and are replaced by the refreshed rows, which are written back to the store
