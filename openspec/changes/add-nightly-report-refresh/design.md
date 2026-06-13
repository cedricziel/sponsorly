## Context

Report data is slow to fetch (Amazon's async Reporting v3 lifecycle takes minutes) and currently transient: results land in `.cachesDirectory` via `ReportCache`, which iOS evicts under storage pressure, and a fetch only runs when a view appears. The result is on-screen waits and disappearing data.

This change introduces two new capabilities — a durable, queryable `report-store` and a single `background-report-refresh` task — and rewires `spend-overview` and `search-term-harvesting` onto the store. Constraints from the project: `SWIFT_STRICT_CONCURRENCY=complete`; MVVM + Repository layering; all Amazon Ads/LWA calls go through swift-amazon-ads (this change adds orchestration and storage, no new endpoint, so no upstream library PR); TDD with pure-function and mocked-network seams; XcodeGen-generated project (`xcodegen generate` after adding files); Info.plist managed in `project.yml`.

Today's relevant code: [ReportCache.swift](Sponsorly/Features/Reports/ReportCache.swift) (the cache being replaced), [ReportingRepository.swift](Sponsorly/Features/Reports/ReportingRepository.swift) (the fetch lifecycle, reused as-is), and the two call sites [SpendOverviewViewModel.swift](Sponsorly/Features/Reports/SpendOverviewViewModel.swift) and [HarvestViewModel.swift](Sponsorly/Features/Harvesting/HarvestViewModel.swift).

## Goals / Non-Goals

**Goals:**

- Report data survives storage-pressure eviction and app restarts (durable store in Application Support).
- The morning app open renders warm data with no on-screen network wait, for the active profile at minimum.
- One background task, with a prioritized resumable queue, warms all connected profiles × all report types over one or more nights.
- The store exposes freshness metadata so the queue can pick stale items and the UI can show a "last updated" age.
- Ship in two independently shippable PRs; PR1 (store) is a pure storage refactor with no behavior change.

**Non-Goals:**

- Guaranteeing the task runs at a specific time — `earliestBeginDate` is a floor; the OS decides.
- Push/server-driven refresh, silent push, or any backend component.
- Changing the report fetch lifecycle itself or optimizing Amazon's poll latency.
- Storing report rows as individual relational records, or building a general-purpose offline sync engine.
- Migrating existing `.cachesDirectory` entries (they're disposable; the store simply re-fetches).

## Decisions

### D1: SwiftData over a relocated file cache or Core Data

Use SwiftData with a `CachedReport` `@Model`, one entry per cache key. **Why:** the background queue needs to _query_ "which entries are stale, across all profiles, what's already done tonight" — a directory of JSON blobs can't answer that without listing-and-parsing everything, and the freshness metadata (`refreshedAt`, `status`) is naturally relational. SwiftData lands in Application Support (eviction-proof) for free and integrates with the Observation-based stack. **Alternatives:** (a) just move `ReportCache` to Application Support — fixes durability but not queryability, so the queue stays awkward; rejected because the queue is the point. (b) Core Data — more boilerplate, no benefit at this scale on iOS 26. (c) GRDB/SQLite — extra dependency, against the system-framework default.

### D2: Report-level entries with a payload blob, not row-level entities

`CachedReport` stores the decoded rows as a single `payload: Data` blob (the encoded `[Row]`), not thousands of per-row `@Model` objects. **Why:** report rows number in the thousands; modeling each relationally explodes the store and buys nothing — nothing queries an individual row, only whole reports. The blob keeps writes cheap and decoding identical to today. Identity fields (`profileId`, `reportTypeId`, `startDate`, `endDate`, `timeUnit`) and metadata (`refreshedAt`, `status`) are first-class columns for querying. **Alternative:** row-level entities for in-store aggregation — rejected; aggregation already lives as pure static funcs on the view models.

### D3: `@ModelActor` `ReportStore` as the single context owner

Wrap the `ModelContext` in a `@ModelActor` `ReportStore`. Both the `@MainActor` view models and the off-main-actor background task talk to it through `async` methods. **Why:** `ModelContext` is not `Sendable`; under strict concurrency a shared context across the UI/background boundary is a data race. A `@ModelActor` serializes all access through one owner. The `ModelContainer` is created once in `SponsorlyApp` and injected. **Alternative:** separate contexts per actor with manual merge — more moving parts, merge-conflict handling, rejected.

### D4: One `BGProcessingTask`, internal prioritized resumable queue

Register a single identifier `com.cedricziel.sponsorly.nightly-refresh` as a `BGProcessingTask` requiring external power. The handler builds a queue ordered: active-profile overview → other-profile overviews → harvesting tail; drains it, checking `task.expirationHandler` / remaining time after each item; on expiration it stops cleanly and schedules a follow-up; on drain it schedules the next night. **Why not multiple tasks:** the OS grants one opportunistic window and no extra total budget for more identifiers — multiple registrations just fragment scheduling and multiply expiration bookkeeping. Resumability (driven by D1's staleness query) is what makes "grab everything" feasible across nights. **Alternative:** `BGAppRefreshTask` — ~30s budget can't fit a multi-minute poll loop; rejected.

### D5: Resumability via store state, not a separate journal

"What's left to do" is derived each run from the store's staleness query (`status != fresh` for the current windows), not from a persisted queue cursor. **Why:** the store is already the source of truth for freshness; a separate journal could drift from it. Marking an item `refreshing` at fetch start and `fresh`/`failed` at end makes a resumed run naturally skip completed items. **Trade-off:** an item left `refreshing` by a hard kill must be reclaimed (treat `refreshing` older than one window as stale).

### D6: Headless auth via `AfterFirstUnlock` Keychain accessibility

The LWA refresh token's Keychain item uses `kSecAttrAccessibleAfterFirstUnlock` so the locked-device nightly run can read it. Token exchange and fetches reuse the existing repositories (`ReportingRepository`, plus the LWA/scoped-client path). A profile whose token can't be refreshed is skipped and its entries marked `failed`; the queue continues. **Why:** background runs happen while locked; `WhenUnlocked` would fail silently at 3am. `AfterFirstUnlock` is the standard, accepted by the user.

### D7: Two-PR split

PR1: introduce `ReportStore` + `CachedReport`, swap both call sites, delete `ReportCache` — pure refactor, same observable behavior, plus the "last updated" age plumbing. PR2: add the scheduler, queue policy, Info.plist/entitlement changes, and task registration in `SponsorlyApp`. **Why:** PR1 de-risks the durability win and is shippable alone; PR2 builds on a store that already persists.

## Risks / Trade-offs

- **OS may rarely/never run the task** (low battery, Force-Quit, unused app) → UI shows a real "last updated" age and falls back to on-appear top-up refresh, so the app is never _dependent_ on the background run; it's an optimization.
- **SwiftData under strict concurrency is fiddly** → confine all `ModelContext` use to the `@ModelActor`; never pass `ModelContext`/models across actors — pass `Sendable` value types (decoded rows, metadata structs) out.
- **Background window cut short mid-fetch** → mark in-flight item not-completed, reschedule; an interrupted Amazon report may be reused via the existing 425-duplicate path on retry.
- **`refreshing` left stale by a hard kill** → reclaim entries `refreshing` for longer than one expected window as stale (D5 trade-off).
- **"Grab everything" cost on metered networks** → require external power (charging); the task also commonly runs on Wi-Fi, but do not gate on it strictly to avoid never running.
- **Coordination with in-flight changes** → `add-spend-overview` and `add-search-term-harvesting` edit the same call sites; this change rebases PR1's swap on top after they land/archive.

## Migration Plan

1. Land/archive `add-spend-overview` and `add-search-term-harvesting` first (they own the call sites).
2. PR1: add `ReportStore`/`CachedReport`, point both view models at it, delete `ReportCache`; `xcodegen generate`; ship. Existing `.cachesDirectory` entries are abandoned (re-fetched on demand) — no data migration needed.
3. PR2: add Info.plist keys (`BGTaskSchedulerPermittedIdentifiers`, `UIBackgroundModes: processing`) and `AfterFirstUnlock` Keychain accessibility in `project.yml`; add `BackgroundRefreshScheduler` + queue policy; register and schedule in `SponsorlyApp`.

- **Rollback:** PR2 is removable on its own (stop registering/scheduling the task); the store keeps working as an on-appear durable cache. PR1 rollback would restore `ReportCache` — avoid by validating PR1 behavior parity before PR2.

## Open Questions

- Staleness rule specifics: is an entry stale purely when its date window no longer ends yesterday, or also on a `refreshedAt` age threshold for today-inclusive ranges? (Leaning: window-roll for immutable ranges, short age threshold for volatile "today" data.)
- Reclaim threshold for a stuck `refreshing` entry — one expected window, or a fixed duration (e.g. 6h)?
- Should the nightly queue also prefetch the next day's window proactively, or only refresh what already exists plus the active profile's overview?
