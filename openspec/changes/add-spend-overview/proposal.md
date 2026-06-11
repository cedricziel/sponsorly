## Why

Sponsorly can browse the whole Sponsored Products tree, but it can't answer the one question an advertiser opens the app to ask: **"how much am I spending, and is it working?"** This change turns the empty Reports tab into a **spend & efficiency overview** for the active profile — the moment the app becomes an advertising _tool_, not an entity browser. It also introduces the async Reporting API machinery every future metrics feature will reuse.

## What Changes

- Replace the Reports placeholder with a **Spend Overview** for the active profile:
  - **Headline (last 30 days):** total **spend, sales, and ACOS** (spend ÷ sales).
  - **Today so far:** a live spend + budget-pacing tile.
  - **Trend:** a 30-day daily spend chart (Swift Charts).
  - **Top campaigns by spend** (with each campaign's ACOS).
- Add the **async Reporting API** flow: `createAsyncReport` → poll `getAsyncReport` until ready → download → decompress (GZIP_JSON) → decode.
- Add the **budget-usage** call (`spCampaignsBudgetUsage`) for the live "today" tile.
- **Cache** report results (past-day reports are immutable) so the overview shows instantly and refreshes in the background.

## Capabilities

### New Capabilities

- `spend-overview`: A performance overview for the active profile — 30-day spend/sales/ACOS, live today spend, a spend trend, and top campaigns by spend — built on the async Reporting API (with caching) plus the sync budget-usage endpoint.

### Modified Capabilities

<!-- None — additive; consumes the existing scoped client. -->

## Impact

- **New code:** the `Reports` feature becomes a `SpendOverview` (tiles + Swift Charts trend + top-campaigns list); a `ReportingRepository` (create → poll-with-backoff → download → decompress → decode), a report cache, a `BudgetUsageRepository`, the `SpendOverviewViewModel`, and metric models.
- **Modified code:** `ReportsView` replaces its `ContentUnavailableView`; reads the active profile / scoped client from the shared `AccountsViewModel`, like every other data screen.
- **Dependencies:** the wired `AmazonAdsReportingAPIv3` (`createAsyncReport` / `getAsyncReport`) and `AmazonAdsSponsoredProductsAPIv3` (`spCampaignsBudgetUsage`) over the active-profile scoped transport; **Swift Charts** (system framework) for the trend.
- **Domain facts:** reports are **asynchronous** (request → poll PENDING→PROCESSING→COMPLETED → download from an S3 URL) and returned as **GZIP_JSON**. One summary report (grouped by campaign) feeds both the headline and top campaigns; one daily report feeds the trend; budget usage (`budget × budgetUsagePercent`) approximates today's spend. Everything is scoped by `Amazon-Advertising-API-Scope: <active profileId>`.
- **Out of scope:** Sponsored Brands & Display; ad-group / keyword / target-level reports; a custom date-range picker (fixed last-30-days + today for v1); CSV/export; any write operations.
