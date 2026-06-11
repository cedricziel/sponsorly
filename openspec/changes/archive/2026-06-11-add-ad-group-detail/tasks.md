## 1. Models

- [x] 1.1 Add `Decodable` `ProductAd` (id, asin?, sku?, state), `Keyword` (id, keywordText, matchType, state, bid?), `TargetingClause` (id, expression display, state, bid?)
- [x] 1.2 Add the SP v3 list-response envelopes (`productAds` / `keywords` / `targetingClauses` + `nextToken`)
- [x] 1.3 Map the targeting-clause expression array into a concise display string
- [x] 1.4 Unit tests decoding each envelope (including the expression mapping)

## 2. Repository

- [x] 2.1 Add `actor AdGroupContentsRepository` built from a `ScopedClient`, reusing the direct-POST + `nextToken` paging pattern
- [x] 2.2 `listProductAds(adGroupId:)` → `POST /sp/productAds/list` (`application/vnd.spProductAd.v3+json`)
- [x] 2.3 `listKeywords(adGroupId:)` → `POST /sp/keywords/list` (`application/vnd.spKeyword.v3+json`)
- [x] 2.4 `listTargetingClauses(adGroupId:)` → `POST /sp/targets/list` (`application/vnd.spTargetingClause.v3+json`)
- [x] 2.5 Unit tests with a mocked URL protocol (success, empty, paging, error)

## 3. View model

- [x] 3.1 Add `@MainActor @Observable AdGroupDetailViewModel` loading the three lists in parallel from `accounts.scopedClient()`
- [x] 3.2 Per-kind partial-failure tolerance (one section degrades; top-level error only if all three fail)
- [x] 3.3 Unit test the partial-failure / all-fail behavior

## 4. Detail screen

- [x] 4.1 Add `AdGroupDetailView` with non-empty sections for Products / Keywords / Targets (section counts; match-type badge on keywords)
- [x] 4.2 Loading indicator (initial + refresh-keeps-content), empty / error (retry) states, pull-to-refresh
- [x] 4.3 Make `CampaignDetailView`'s ad-group rows `NavigationLink`s into the detail
- [x] 4.4 `#Preview`s for populated / empty states

## 5. Wire-up & verification

- [x] 5.1 Run `xcodegen generate` after adding the new files
- [x] 5.2 Build for the simulator
- [x] 5.3 Run tests
- [x] 5.4 Run `swiftformat` + `swiftlint` (lint clean)
- [x] 5.5 On device: open a campaign → an ad group, confirm real product ads + keywords/targets load
- [x] 5.6 Commit as semantic commits (models, repository, view model, detail UI), one logical change per commit
