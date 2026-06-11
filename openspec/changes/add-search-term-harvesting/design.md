## Context

This is the app's first write feature. Reads are all in place: the async report pipeline (`ReportingRepository`), the scoped client, and the campaign browser. Harvesting adds a new report type (`spSearchTerm`, reusing the pipeline), a scorer, the SP v3 **write** endpoints (`CreateSponsoredProductsKeywords`, `CreateSponsoredProductsNegativeKeywords`), and a review-and-approve wizard. The user's accounts have no naming convention, so v1 lets the user **pick** the target manual campaign rather than auto-pairing by name.

### The workflow

```
        ┌──────────────────────────────────────────────────────────┐
        │  AUTO campaign  — discovery                               │
        │    Amazon matches products → real customer search queries │
        └───────────────┬──────────────────────────────────────────┘
                        │  ① spSearchTerm report
                        ▼
            ┌───────────────────────────┐
            │  score each search term    │   criteria (tunable, defaults):
            │  against the criteria       │     graduate: orders ≥ 2, clicks ≥ 10, ACOS ≤ target
            └───────┬───────────┬────────┘     negate:   clicks ≥ 10, orders = 0
                    ▼           ▼
            ┌────────────┐  ┌────────────┐
            │  GRADUATE  │  │   NEGATE   │
            │  winners   │  │   wasteful │
            └─────┬──────┘  └─────┬──────┘
                  │ ③ review + approve (user checks terms, picks target)
                  ▼                ▼
   ④ create EXACT keywords     ④ create NEGATIVE-EXACT
      in MANUAL ad group          in the AUTO campaign
      (your bid)                  (stop the waste / stop double-bidding)
                  │                │
                  └──── per-term results: added / negated / already-there / failed
```

### The wizard

```
   ┌─ Step 1: Criteria ─────────┐   ┌─ Step 2: Review ──────────────┐   ┌─ Step 3: Confirm ─────────┐
   │ Min orders     [ 2 ]       │   │ GRADUATE (8)                  │   │ Create 6 exact keywords   │
   │ Min clicks     [ 10 ]      │ → │  ☑ "running shoes"  3 ord 18% │ → │   in: SP|ABC|Exact ▸ AG1  │
   │ Target ACOS    [ 25% ]     │   │  ☑ "trail runners"  2 ord 22% │   │ Negate 9 terms            │
   │ Min clicks     [ 10 ]      │   │  ☐ "blue shoes"     2 ord 40% │   │   in: <auto campaign>     │
   │  (negate / 0 orders)       │   │ NEGATE (12)                   │   │                           │
   │                            │   │  ☑ "free shoes"    14 clk 0  │   │   [ Confirm ]  [ Back ]   │
   │ Target campaign  [ pick ▸ ]│   │  ☑ "kids socks"    11 clk 0  │   └───────────────────────────┘
   │            [ Next ▸ ]      │   │            [ Review ▸ ]       │            │
   └────────────────────────────┘   └───────────────────────────────┘            ▼
                                                                      ┌─ Results ──────────────────┐
                                                                      │ ✓ 5 keywords added         │
                                                                      │ • 1 already existed        │
                                                                      │ ✓ 9 negated                │
                                                                      │ ✗ 0 failed     [ Done ]    │
                                                                      └────────────────────────────┘
```

## Goals / Non-Goals

**Goals:**

- Fetch + score a campaign's search terms into graduate/negate buckets with tunable criteria (sane defaults).
- A review-and-approve wizard that writes nothing until confirmed.
- Create exact keywords in a chosen manual ad group + negative-exact in the source; report per-term outcomes.

**Non-Goals:**

- Rule-based / automated promotion (review-and-approve only).
- Phrase/broad match; creating the target campaign inline; naming-convention auto-pairing.
- Sponsored Brands/Display; bid optimization beyond a suggested starting bid; bulk undo.

## Decisions

### D1: Reuse the report pipeline for `spSearchTerm`

A new `SearchTermReportRow` + a `spSearchTerm` report config; everything else (create → poll → download → gunzip → decode, caching) is the pipeline we built. Search-term data is per-day-ish and worth a short cache.

### D2: Scoring is pure and local

The report is fetched once; bucketing is a pure function over the rows + a `HarvestCriteria` value. Changing a threshold re-buckets in memory (no refetch). Defaults: graduate `orders ≥ 2 && clicks ≥ 10 && acos ≤ target(0.25)`; negate `clicks ≥ 10 && orders == 0`. A term that's neither is ignored.

### D3: Writes via a `KeywordWriteRepository`

`createExactKeywords(adGroupId, campaignId, terms, bid)` → `POST /sp/keywords`; `createNegativeExact(campaignId, adGroupId, terms)` → `POST /sp/negativeKeywords` (ad-group-level negatives on the auto campaign's ad group; campaign-level is the alternative to confirm on device). Both are batch endpoints returning **per-item success/error**; we map indices back to terms.

### D4: First-write safety

- **Confirm step** with an explicit summary before any mutation.
- **Idempotency:** an `INVALID_ARGUMENT`/duplicate response for an existing keyword is mapped to "already added," not a failure. (Optionally pre-list existing keywords to gray out already-present terms — nice-to-have.)
- **Partial success is normal:** apply what succeeded; report each term's outcome; never roll back silently.
- A **suggested starting bid** (e.g. derived from the term's auto CPC or a target-ACOS heuristic), editable; no per-keyword bid tuning in v1.

### D5: Manual target selection (no naming dependency)

The wizard picks an existing manual campaign + ad group (reusing the campaigns/ad-groups lists). Naming-based auto-pairing is deferred; manual selection is robust for messy/unnamed accounts (the common case).

### D6: Entry point + concurrency

Enter the wizard from a campaign's detail (offered for auto campaigns). `HarvestViewModel` (`@MainActor @Observable`) owns the report + criteria + selection; the write step calls the repository (actor) and collects results. Models `Sendable`.

## Risks / Trade-offs

- **Exact write request/response shapes** (`/sp/keywords`, `/sp/negativeKeywords` bodies, matchType casing `EXACT` / `NEGATIVE_EXACT`, the per-item success/error envelope) → Mitigation: model defensively; verify on a live account; the confirm step means nothing fires until the user okays it.
- **`spSearchTerm` columns / report type id** → Mitigation: confirm columns on device (as with the other report types).
- **Accidental over-negation** (negating a term that was actually fine) → Mitigation: review-and-approve, clear per-term context (spend/sales/orders), and exact-match negatives only (narrow blast radius).
- **No bulk undo in v1** → Mitigation: state it; negatives/keywords can be removed in the console; consider an in-app "recently harvested" list later.
- **Duplicate writes on re-run** → Mitigation: idempotent handling (D4); optional pre-list to pre-check existing.

## Open Questions

- Negate at **ad-group** or **campaign** level on the auto side? (Leaning: ad-group level — auto usually has one ad group; campaign-level if multiple.)
- Suggested starting bid heuristic — auto CPC, or target-ACOS-derived? (Leaning: start from the term's auto CPC, editable.)
- Pre-list existing keywords to pre-mark "already added" before writing, or just handle the duplicate response? (Leaning: handle the response in v1; pre-list later.)
