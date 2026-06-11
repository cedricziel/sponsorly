## Context

Every data feature so far is a synchronous "GET the list." Performance data is different: the Reporting API v3 is **asynchronous** — `createAsyncReport` → poll `getAsyncReport` (PENDING→PROCESSING→COMPLETED) → download a **GZIP_JSON** file from an S3 URL. This change introduces that machinery (reused by all future metrics) and turns the empty Reports tab into a spend overview.

Two sources feed it: the async Reporting API (`AmazonAdsReportingAPIv3`) for 30-day spend/sales/ACOS, the daily trend, and top campaigns; and the synchronous `spCampaignsBudgetUsage` (SP v3) for a live "today" tile (`budget × budgetUsagePercent`, summed). Both go over the active-profile `ScopedClient`. Trend rendering uses **Swift Charts**.

Constraints unchanged: SwiftUI, iOS 26, Swift 5.10, strict concurrency, XcodeGen, Apple HIG.

## Goals / Non-Goals

**Goals:**

- 30-day spend / sales / ACOS headline, a live today tile, a 30-day spend trend chart, and top campaigns by spend — for the active profile.
- The reusable async-report pipeline (create → poll → download → decompress → decode) with caching.

**Non-Goals:**

- Sponsored Brands & Display; ad-group / keyword / target-level reports.
- A custom date-range picker (fixed last-30-days + today for v1); CSV/export; any write operations.

## Decisions

### D1: Two data paths

Async Reporting API for the headline, trend, and top campaigns (cached); synchronous budget usage for the live "today" tile. The today tile never waits on report generation, so the overview always has _something_ immediate.

### D2: Minimize reports — one summary + one daily

Request **one** campaign-grouped **SUMMARY** report (columns incl. `cost`, `sales`, `purchases`, campaign id/name) — it serves both the headline (sum the rows) and top-campaigns (sort the rows). Request **one DAILY** report for the trend. Plus one budget-usage call. Three requests total per refresh.

### D3: Async lifecycle in a `ReportingRepository` actor

`requestReport(config) -> reportId`, then `pollUntilReady(reportId)` with capped exponential backoff (e.g. 2s→4s→…, ~2–3 min budget), then `download(url)`. Surface states: generating / ready / failed-or-timed-out. Polling runs in a background task; the UI shows cached data meanwhile.

### D4: GZIP decompression (sharpest risk)

The download is gzip-compressed JSON. First try letting `URLSession` auto-decompress (if S3 sends `Content-Encoding: gzip`); if the body is a raw `.gz` blob, Foundation can't gunzip directly (its `Compression` does zlib/lzfse, not gzip framing). Mitigation: a small gunzip helper (strip the gzip header/trailer, inflate raw DEFLATE via `Compression`), behind a `ReportDownloader` so the rest of the pipeline is agnostic. **Verify which path is needed early in apply.**

### D5: Cache immutable reports

Cache decoded report results keyed by `(profileId, reportTypeId, startDate, endDate, timeUnit)`. A range ending before today is immutable → long-lived (disk cache). A range including today is volatile → short TTL / always-refresh. On open: render cache immediately, refresh in background (spec scenario). Disk cache (Caches dir, JSON) — not `UserDefaults` (too large).

### D6: UI — Reports tab becomes the overview

`ReportsView` → a scrollable dashboard: metric tiles (Spend / Sales / ACOS), a today tile, a Swift Charts spend-trend, and a top-campaigns list. Gated on the active profile (prompt + switcher, like other screens); pull-to-refresh; loading indicator that keeps cached content visible. A `@MainActor @Observable SpendOverviewViewModel` orchestrates the repositories and cache.

### D7: Concurrency

`ReportingRepository` and `BudgetUsageRepository` are actors over the `ScopedClient`; metric models are `Sendable` (inferred). The view model is `@MainActor`. The three fetches run in parallel; today + cached headline can render before the fresh reports finish.

## Risks / Trade-offs

- **GZIP decompression** (D4) → Mitigation: try URLSession auto-decompress; fall back to a gunzip helper; isolate behind `ReportDownloader`; verify on a real report early.
- **Report latency / timeouts** → Mitigation: cache + background poll with a capped budget; today tile is always live; clear "updating" / retry states.
- **Exact report column + config names** (`cost` vs `spend`, `sales` vs `sales30d`, `reportTypeId` value, enum casings) → Mitigation: model defensively; confirm against a live report during apply (same approach that worked for campaigns).
- **Budget-usage approximation** (`budget × pct` ≈ today's spend, assumes daily budgets, SP-only) → Mitigation: label it "today so far (approx)"; it's a pacing signal, not an exact ledger.
- **Cost / rate limits** (reports are heavier than list calls) → Mitigation: cache aggressively; refresh on explicit pull or stale cache, not on every appearance.

## Open Questions

- Headline range end at **today** (volatile, re-fetch often) or **yesterday** (immutable, cache-friendly) with today shown only in the live tile? (Leaning: 30 days **ending yesterday** for the cached headline/trend, today via the live tile — cleanest caching story.)
- Top-campaigns count — top 5, 10, or all sorted? (Leaning: top 5 with a "see all" later.)
- Currency formatting — use the profile's `currencyCode` (we have it on `AdvertisingProfile`)? (Leaning: yes.)
