# Tasks

PR1 = groups 1–4 (durable store, pure refactor + freshness age). PR2 = groups 5–8 (background task). Land/archive `add-spend-overview` and `add-search-term-harvesting` before group 3. TDD: write the failing test first in each implementation task.

## 1. Coordination & prerequisites

- [x] 1.1 Confirm `add-spend-overview` and `add-search-term-harvesting` are landed/archived; rebase this change's call-site edits onto their final shape — both features' code (caching, 425-reuse, Overview tab) is already in `main`; call sites are stable. Group 2 (new files) proceeds now; group 3 (call-site swap) pauses for explicit confirmation of remaining in-progress tasks.
- [x] 1.2 Verify how the LWA refresh token is stored today and confirm/raise its Keychain accessibility to `kSecAttrAccessibleAfterFirstUnlock` — already `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` in `KeychainTokenStorage.swift:29` (stricter than required; headless locked reads already work). No change needed.

## 2. ReportStore — model & store (PR1)

- [x] 2.1 Write failing tests: `ReportStoreTests` (in-memory `ModelContainer`) covering round-trip by key, distinct-key isolation (SUMMARY vs DAILY), `refreshedAt`/`status` on save, staleness query (excludes in-flight `refreshing` until reclaim), failure preserving last-good payload, and the pure `isStale` rules. **Written; run deferred** (slow simulator cycle — batch later).
- [x] 2.2 Add `CachedReport` `@Model` (identity columns + `payload: Data`, `refreshedAt`, `statusRaw`/`status`), `RefreshStatus`, `ReportMetadata`, and `StalenessPolicy` value types — `Sponsorly/Features/Reports/CachedReport.swift`
- [x] 2.3 Implement `ReportStore` as a `@ModelActor`: `load(_:as:)`, `metadata(_:)`, `save(_:for:now:)`, `markRefreshing`/`markFailed`, `staleKeys(now:policy:)`. Returns only `Sendable` values across the boundary; in-memory `fetch` to avoid the non-Sendable `#Predicate` KeyPath — `Sponsorly/Features/Reports/ReportStore.swift`
- [x] 2.4 Staleness rule as a pure static `isStale(_:endDate:refreshedAt:now:policy:)` (immutable past ranges never stale by age; today-inclusive use `volatileTTL`; `refreshing` reclaimed past `reclaimAfter`); tested directly
- [x] 2.5 `xcodegen generate`; app target builds green for iPhone 17 Pro simulator (one `#Predicate` Sendable warning eliminated by the in-memory fetch)

## 3. Swap call sites onto ReportStore (PR1)

- [x] 3.1 Container wired in `SponsorlyApp` via `.modelContainer(ReportStore.sharedContainer)`; view models use the shared `ReportStore.shared` (which the background task will reuse). `ReportCacheKey` relocated into `CachedReport.swift`.
- [x] 3.2 Repointed [SpendOverviewViewModel.swift](Sponsorly/Features/Reports/SpendOverviewViewModel.swift) to `ReportStore` — same store-first render → refresh → save shape; TTL arg dropped (store owns staleness)
- [x] 3.3 Repointed [HarvestViewModel.swift](Sponsorly/Features/Harvesting/HarvestViewModel.swift) to `ReportStore` at its report fetch call site
- [x] 3.4 Deleted `ReportCache.swift`; removed the dead `ReportCacheTests` and renamed the file to `BudgetUsageRepositoryTests.swift`; `xcodegen generate`; app builds green; no remaining `ReportCache` refs

## 4. Freshness in the UI (PR1)

- [x] 4.1 Added `private(set) var lastUpdated: Date?` to `SpendOverviewViewModel`, set from the store entry's `refreshedAt` on store-render and from the save time on refresh
- [x] 4.2 Added `FreshnessLabel` ("Updated N ago", relative, secondary styling) to the overview; wired it above the headline tiles; added a stale-state `#Preview` and a `SpendOverviewViewModel.preview(updatedAgo:)` factory
- [~] 4.3 App builds green; `swiftformat` clean; `swiftlint` clean (no `make` targets — ran the tools directly). **Full suite: 92/92 pass.** Manual simulator launch deferred per the user's preference against slow sim cycles; rely on build + previews + tests. **Commit not yet made** (awaiting user go-ahead).

## 5. Project config for background execution (PR2)

- [ ] 5.1 In `project.yml` Info.plist: add `BGTaskSchedulerPermittedIdentifiers` with `com.cedricziel.sponsorly.nightly-refresh` and `UIBackgroundModes` including `processing`
- [ ] 5.2 Ensure the `AfterFirstUnlock` Keychain accessibility from 1.2 is in place; `xcodegen generate`; build

## 6. Refresh queue policy (PR2)

- [ ] 6.1 Write failing tests for queue ordering (active-profile overview → other profiles' overviews → harvesting tail), next-item selection from staleness, and the reschedule decision (drain vs cut-short)
- [ ] 6.2 Implement the queue policy as pure funcs: build the work list from connected profiles × report types, order by priority, and select the next stale item; reclaim `refreshing` items older than one window
- [ ] 6.3 Implement the per-item fetch step reusing `ReportingRepository` (no hand-rolled Ads requests): mark `refreshing` → fetch → `save`/`markFailed`; one failed profile is skipped, not fatal (mocked-network tests)

## 7. Background task wiring (PR2)

- [ ] 7.1 Implement `BackgroundRefreshScheduler`: register the single task handler, schedule a request (requires external power, future `earliestBeginDate`), and a `schedule()` called on app background/launch
- [ ] 7.2 Implement the task handler: drain the queue, check `expirationHandler`/remaining time after each item, complete the task exactly once, and reschedule (follow-up on cut-short, next-night on drain)
- [ ] 7.3 Register and schedule from `SponsorlyApp`; `xcodegen generate`; build

## 8. Verification (PR2)

- [ ] 8.1 Exercise the task via the scheduler debug path (`e -l objc -- (void)[...]` launch simulation / `simctl` background-fetch trigger) and confirm entries land in the store with updated `refreshedAt`
- [ ] 8.2 Verify a cut-short window reschedules and a resumed run skips already-`fresh` items; verify a profile auth failure skips without aborting the queue
- [ ] 8.3 Run full test suite; `make lint` and `make format`; commit PR2
