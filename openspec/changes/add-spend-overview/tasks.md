## 1. Async report pipeline

- [x] 1.1 Add a `ReportConfiguration` builder (adProduct=SPONSORED_PRODUCTS, reportTypeId, timeUnit, groupBy, columns, format=GZIP_JSON, dates)
- [x] 1.2 Add `actor ReportingRepository` with `requestReport(config) -> reportId` (`createAsyncReport`) over the scoped client
- [x] 1.3 `pollUntilReady(reportId)` — poll `getAsyncReport` with capped exponential backoff until COMPLETED / FAILURE / timeout
- [x] 1.4 `ReportDownloader`: download the report URL and decompress (try URLSession auto-decompress; fall back to a gunzip helper) → JSON rows
- [x] 1.5 Verify the gzip path against a real report early; keep the rest of the pipeline decompression-agnostic
- [x] 1.6 Decode report rows into metric models; unit tests for decode + the poll state machine (mocked URL protocol)

## 2. Report cache

- [x] 2.1 Add a disk cache keyed by `(profileId, reportTypeId, startDate, endDate, timeUnit)` (Caches dir, JSON)
- [x] 2.2 Immutable past-day ranges long-lived; today-inclusive ranges short TTL / always refresh
- [x] 2.3 Unit tests for cache round-trip + key/expiry behavior

## 3. Budget usage (live today)

- [x] 3.1 Add `BudgetUsageRepository` calling `spCampaignsBudgetUsage` over the scoped client
- [x] 3.2 Approximate today's spend as Σ(`budget × budgetUsagePercent`); paged
- [x] 3.3 Unit tests with a mocked URL protocol

## 4. View model + aggregation

- [ ] 4.1 Add `@MainActor @Observable SpendOverviewViewModel` orchestrating: live today (budget usage), summary report (headline + top campaigns), daily report (trend)
- [ ] 4.2 Aggregate headline (sum), top campaigns (sort by spend), ACOS = spend ÷ sales (nil-safe), trend series
- [ ] 4.3 Render cached immediately + refresh in background; per-source partial failure (live tile can succeed while reports are still generating)
- [ ] 4.4 Unit tests for aggregation (ACOS nil-safe, sorting, sums)

## 5. Overview UI (Reports tab)

- [ ] 5.1 Replace `ReportsView` placeholder with the dashboard; gate on active profile (prompt + account switcher)
- [ ] 5.2 Metric tiles (Spend / Sales / ACOS) using the profile's currency code
- [ ] 5.3 Live "today so far" tile (labeled approximate)
- [ ] 5.4 30-day spend trend with **Swift Charts**
- [ ] 5.5 Top-campaigns list (top 5) with spend + ACOS
- [ ] 5.6 Loading indicator (keeps cached content), "updating" while reports generate, error+retry, pull-to-refresh
- [ ] 5.7 `#Preview`s for populated / loading / no-active-profile states

## 6. Wire-up & verification

- [ ] 6.1 Run `xcodegen generate` after adding the new files
- [ ] 6.2 Build for the simulator
- [ ] 6.3 Run tests
- [ ] 6.4 Run `swiftformat` + `swiftlint` (lint clean)
- [ ] 6.5 On device: select a profile, confirm today tile is live, the report headline/trend/top-campaigns populate (confirms the async + gzip pipeline against the real API)
- [ ] 6.6 Commit as semantic commits (pipeline, cache, budget usage, view model, UI), one logical change per commit
