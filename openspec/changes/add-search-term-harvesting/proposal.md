## Why

The auto campaign is a discovery engine: Amazon matches products to real customer search queries, some of which convert well. Today there's no way to act on that — you'd have to read a search-term report by hand, decide what's working, and manually re-key it into a targeted campaign. This change adds the **search-term harvesting** workflow: surface the auto campaign's winning (and wasteful) search terms, let the user review them, and on approval **graduate winners into a Manual-Exact campaign and negate them in the auto campaign**. It's also the app's **first write operations** — the move from read-only browser to optimization tool.

## What Changes

- Add a **search-term report** (`spSearchTerm`) for a selected campaign — a new report type that **reuses the existing async report pipeline** (create → poll → download → gunzip → decode).
- **Score** each search term against user-tunable criteria into two buckets: **Graduate** (≥ orders, ≥ clicks, ACOS ≤ target) and **Negate** (≥ clicks, 0 orders). Defaults pre-filled; adjustable in the wizard.
- A **review-and-approve wizard**: the user sets criteria, sees the candidate buckets, checks which terms to action, and picks the **target Manual-Exact campaign/ad group** (no naming convention assumed).
- On approve, perform the app's first **writes**: **create exact keywords** in the target manual ad group, and **negative-exact** the same terms in the source auto campaign. Report per-term outcomes (added / negated / skipped-duplicate / failed).

## Capabilities

### New Capabilities

- `search-term-harvesting`: Discover an auto campaign's converting/wasteful search terms (search-term report), review them against tunable criteria, and on approval graduate winners to exact keywords in a chosen manual campaign while negating them in the auto campaign.

### Modified Capabilities

<!-- None — additive. Reuses the report pipeline and scoped client. -->

## Impact

- **New code:** a `Harvesting` feature — a `SearchTermReportRow` model + `spSearchTerm` report config (reusing `ReportingRepository`), a scorer (graduate/negate buckets), `KeywordWriteRepository` (`CreateSponsoredProductsKeywords` + `CreateSponsoredProductsNegativeKeywords`), a multi-step review wizard, and a results screen.
- **Modified code:** an entry point into the wizard (e.g. from a campaign's detail, for auto campaigns).
- **Dependencies:** the async report pipeline (`spSearchTerm`), the SP v3 write endpoints, and the active-profile `ScopedClient`. SP v3 batch writes return **per-item success/error** — the UI maps that to per-term outcomes.
- **First write operations — handle with care:** confirm before writing; treat duplicates gracefully (a keyword that already exists isn't a failure); partial success is normal; surface a clear per-term result. No bulk undo in v1 (note it).
- **Out of scope:** rule-based/automated promotion (review-and-approve only); phrase/broad match (exact only); creating the target campaign inline (pick an existing one for v1); naming-convention auto-pairing of auto↔manual (deferred); Sponsored Brands/Display; bid optimization beyond a suggested starting bid.
