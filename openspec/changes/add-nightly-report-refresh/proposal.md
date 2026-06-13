## Why

Report data is both **slow to fetch** and **transient**. Amazon's async Reporting v3 lifecycle (create → poll → download → gunzip → decode) takes minutes, and today it only runs when a view appears — so the user waits, on screen, every time. Worse, results land in `.cachesDirectory`, which iOS evicts under storage pressure, so even a freshly-fetched report can vanish before the next launch. The fix is to make report data **durable** and to **warm it overnight** so the morning open is instant.

## What Changes

- **Replace `ReportCache` with a durable, queryable `ReportStore`** backed by SwiftData in Application Support (eviction-proof). One entry per report cache key (`profileId`, `reportTypeId`, `startDate`, `endDate`, `timeUnit`) holding the decoded rows as a `payload` blob plus metadata: `refreshedAt` and `status` (`fresh` / `stale` / `refreshing` / `failed`). Modeled as a `@ModelActor` so the off-main-actor background task and the `@MainActor` view models share one serialized `ModelContext` under strict concurrency. **BREAKING** at the storage layer only — call sites keep their cache-first-then-refresh shape.
- **Add a single `BGProcessingTask` "nightly-refresh"** that warms reports overnight while charging. It drains one prioritized, resumable work queue: the active profile's spend overview first, then other connected profiles' overviews, then the heavy harvesting reports as the tail. It checks the expiration handler after each item, reschedules itself with the remainder if the OS cuts the window short, and reschedules for the next night when the queue drains. Scope is **all connected profiles × all report types** ("grab everything"), made feasible by resumability across multiple nights.
- **Surface report freshness in the UI.** `earliestBeginDate` is a floor, not a guarantee — the OS decides when (and whether) the task runs. Views show a "last refreshed N ago" age rather than implying live freshness.
- Background orchestration is **app-side**; swift-amazon-ads stays transport-only. Keychain `AfterFirstUnlock` accessibility is acceptable so the headless task can exchange the LWA refresh token while the device is locked (after one unlock since boot).

Ships as **two PRs**: PR1 = `ReportStore` replaces `ReportCache` as a pure storage refactor (same behavior at both call sites). PR2 = the `BGProcessingTask` on top.

## Capabilities

### New Capabilities

- `report-store`: Durable, queryable persistence for decoded report rows keyed by report cache key, with per-entry freshness metadata (`refreshedAt`, `status`). Replaces the in-memory/Caches-directory `ReportCache`. A `@ModelActor` repository (`ReportStore`); no view, reused by existing view models. Test seam: mocked SwiftData in-memory `ModelContainer` driving load/save/staleness queries — pure-function for key derivation and staleness rules.
- `background-report-refresh`: A single `BGProcessingTask` that warms `report-store` overnight via a prioritized, resumable work queue across all connected profiles and report types, rescheduling on expiration and nightly. App-side orchestration (scheduler + queue policy); repositories reused for the actual fetches. Test seam: pure-function for queue ordering / next-item selection / reschedule decision; mocked-network repositories for the fetch step.

### Modified Capabilities

- `spend-overview`: Reads from `report-store` instead of `ReportCache`; gains a "last refreshed" age in its requirements. Refresh on appear becomes a top-up over already-warm data rather than the sole fetch path.
- `search-term-harvesting`: Same storage swap (`ReportStore` for `ReportCache`) at its report fetch call site; participates in the nightly queue as the heavy tail.

## Impact

- **Code:** new `Sponsorly/Features/Reports/ReportStore.swift` (+ `CachedReport` `@Model`); `BackgroundRefreshScheduler` + queue policy (likely `Sponsorly/Background/`); `ReportCache.swift` removed. Call-site edits in [SpendOverviewViewModel.swift](Sponsorly/Features/Reports/SpendOverviewViewModel.swift) and [HarvestViewModel.swift](Sponsorly/Features/Harvesting/HarvestViewModel.swift). `SponsorlyApp` registers the task and owns the `ModelContainer`.
- **Project config:** `project.yml` Info.plist gains `BGTaskSchedulerPermittedIdentifiers` and `UIBackgroundModes` (`processing`); Keychain item accessibility set to `AfterFirstUnlock`. Run `xcodegen generate` after adding the new files.
- **Dependencies:** SwiftData (system framework) added; swift-amazon-ads unchanged (no upstream PR needed — this is orchestration + storage, not a new endpoint).
- **Coordination:** in-progress changes `add-spend-overview` and `add-search-term-harvesting` touch the same cache call sites. Land/archive those first; this change rebases its storage swap on top of whatever they ship.
