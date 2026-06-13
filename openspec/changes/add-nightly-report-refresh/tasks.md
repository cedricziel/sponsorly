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

- [x] 5.1 `project.yml` Info.plist: added `UIBackgroundModes: [processing]` and `BGTaskSchedulerPermittedIdentifiers: [com.cedricziel.sponsorly.nightly-refresh]`
- [x] 5.2 Keychain is already `AfterFirstUnlockThisDeviceOnly` (1.2); `xcodegen generate`; app builds green

## 6. Refresh queue policy (PR2)

- [x] 6.1 Added `RefreshQueueTests` (ordering: active overview → other overviews → harvesting tail; active-not-in-list ignored; cache-key shape) and `NightlyRefreshEngineTests` (full drain, skip-already-fresh, cut-short→incomplete, missing-client→failed) — `Sponsorly/Background/`
- [x] 6.2 `RefreshQueueBuilder.build(profiles:active:)` (pure) + `RefreshTask`/`RefreshReportKind`/`RefreshProfileRef` with `cacheKey`/`request` derivation matching the on-screen shape. Reclaim handled by `ReportStore.isStale` (`refreshing` past `reclaimAfter`); resumable skip via new `ReportStore.needsRefresh`
- [x] 6.3 `ReportingReportRefresher` (live) marks `refreshing` → `ReportingRepository.fetchRows` → `save`/`markFailed`; `NightlyRefreshEngine` drains with a mockable `ReportRefreshing` seam, skips fresh, stops on `shouldContinue`, marks a profile `failed` when no client and continues

## 7. Background task wiring (PR2)

- [x] 7.1 `BackgroundRefreshScheduler.register()` (single identifier) + `schedule()` (requires external power + network, future `earliestBeginDate`)
- [x] 7.2 `handle(_:)` reschedules next-night first, wires `expirationHandler` to a `CancellationFlag`, drains via `runRefresh(shouldContinue:)`, and calls `setTaskCompleted` exactly once with the drain result. Headless bootstrap builds providers per region (LWAAuthService), discovers profiles, builds the queue
- [x] 7.3 `SponsorlyApp.init` registers; `.onChange(of: scenePhase)` schedules on background; `xcodegen generate`; builds green

## 8. Verification (PR2)

- [~] 8.1 **Deferred (manual device path).** Triggering the live `BGProcessingTask` needs an on-device/simulator lldb `_simulateLaunchForTaskWithIdentifier:` against a running app — out of scope for the unit seam and the user's preference against slow sim cycles. The drain logic it would exercise is unit-covered (below). To run later: launch on device, background, pause in lldb, `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.cedricziel.sponsorly.nightly-refresh"]`.
- [x] 8.2 Covered by `NightlyRefreshEngineTests`: cut-short → `completed == false` (handler reschedules a follow-up before draining); resumed run skips already-`fresh` items; a profile with no client is marked `failed` and the queue continues. Reschedule-on-drain/cut-short is in `handle(_:)` by inspection.
- [x] 8.3 Full suite **101/101 pass**; `swiftformat` clean; `swiftlint` clean. PR2 ready to commit.
