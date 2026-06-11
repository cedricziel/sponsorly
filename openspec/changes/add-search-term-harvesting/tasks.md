## 1. Search-term report

- [x] 1.1 Add `SearchTermReportRow` (searchTerm, campaignId, adGroupId, clicks, cost, sales, orders) + the `spSearchTerm` report config
- [x] 1.2 Fetch via the existing `ReportingRepository` pipeline (reuse create/poll/download/gunzip); cache with a short TTL
- [x] 1.3 Unit tests decoding the search-term envelope

## 2. Scoring

- [x] 2.1 Add `HarvestCriteria` (minOrders, minClicks, targetACOS, negateMinClicks) with defaults (2 / 10 / 0.25 / 10)
- [x] 2.2 Pure scorer → `graduate` / `negate` buckets from rows + criteria (a term that's neither is ignored)
- [x] 2.3 Unit tests for bucketing (boundaries, ACOS nil-safe, re-bucketing on criteria change)

## 3. Keyword write repository

- [x] 3.1 Add `actor KeywordWriteRepository` over the scoped client
- [x] 3.2 `createExactKeywords(campaignId, adGroupId, terms, bid)` → `POST /sp/keywords` (matchType EXACT), parse per-item success/error
- [x] 3.3 `createNegativeExact(campaignId, adGroupId, terms)` → `POST /sp/negativeKeywords` (NEGATIVE_EXACT), parse per-item success/error
- [x] 3.4 Map duplicate/already-exists responses to an "already added" outcome (not a failure)
- [x] 3.5 Unit tests with a mocked URL protocol (success, partial failure, duplicate)

## 4. Wizard view model

- [x] 4.1 Add `@MainActor @Observable HarvestViewModel`: load report, hold criteria + selection + target
- [x] 4.2 Re-bucket in memory when criteria change; track per-term checked state and the chosen target campaign/ad group
- [x] 4.3 Build the confirmation summary; perform writes; collect per-term results
- [x] 4.4 Unit tests for the summary + result aggregation (with the repository mocked)

## 5. Wizard UI

- [x] 5.1 Step 1 — Criteria: tunable thresholds (defaults) + target campaign/ad-group picker (reuse existing lists)
- [x] 5.2 Step 2 — Review: graduate/negate buckets with per-term spend/sales/orders/ACOS and checkboxes
- [x] 5.3 Step 3 — Confirm: summary of what will be created/negated; disabled when nothing selected; explicit confirm
- [x] 5.4 Results screen: per-term outcomes (added / already-added / negated / failed) + counts
- [x] 5.5 Entry point from a campaign's detail (offered for auto campaigns); loading / empty / error states
- [x] 5.6 `#Preview`s for the criteria, review, and results steps

## 6. Wire-up & verification

- [x] 6.1 Run `xcodegen generate` after adding the new files
- [x] 6.2 Build for the simulator
- [x] 6.3 Run tests
- [x] 6.4 Run `swiftformat` + `swiftlint` (lint clean)
- [ ] 6.5 On device (CAREFUL — real writes): dry-run the wizard, confirm the search-term report loads and buckets correctly; then graduate/negate a single safe term and verify it appears in the manual campaign + as a negative in the auto
- [ ] 6.6 Commit as semantic commits (report, scoring, write repo, wizard), one logical change per commit
