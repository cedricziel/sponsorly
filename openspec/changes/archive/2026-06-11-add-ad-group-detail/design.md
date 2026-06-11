## Context

The campaigns change established the pattern: a `ScopedClient` (region base URL + clientID + profileId + tokenProvider) and a repository that POSTs to SP v3 `.../list` endpoints with the vendored content type, follows `nextToken`, and decodes small models. Ad-group rows in `CampaignDetailView` are currently non-navigable dead ends. This change adds the next level down — an ad group's product ads and targeting.

Verified SP v3 surface: `POST /sp/productAds/list` (`application/vnd.spProductAd.v3+json`, key `productAds`), `POST /sp/keywords/list` (`application/vnd.spKeyword.v3+json`, key `keywords`), `POST /sp/targets/list` (`application/vnd.spTargetingClause.v3+json`, key `targetingClauses`). All filter by `adGroupIdFilter`.

Constraints unchanged: SwiftUI, iOS 26, Swift 5.10, strict concurrency, XcodeGen, Apple HIG.

## Goals / Non-Goals

**Goals:**

- Navigate from an ad-group row to an ad-group detail screen.
- List the ad group's product ads + keywords + targeting clauses (non-empty sections), paginated.
- Loading / empty / error (retry) states + pull-to-refresh, consistent with existing screens.

**Non-Goals:**

- Negatives (negative keywords / targets, campaign-level negatives); any write ops; bid editing.
- Sponsored Brands & Display; performance metrics / reports.

## Decisions

### D1: Fetch all three kinds, render the non-empty ones

Rather than branch on the campaign's `targetingType` to decide keywords-vs-targets, fetch product ads, keywords, and targeting clauses for the ad group (in parallel) and show only the sections that come back non-empty. This is robust to mixed ad groups and avoids threading targeting type down; the cost is one extra (usually-empty) list call per ad group, which is cheap.

### D2: Extend the established direct-POST pattern

Add `listProductAds(adGroupId:)`, `listKeywords(adGroupId:)`, `listTargetingClauses(adGroupId:)` following the campaigns repository's `POST .../list` + paging helper. Keep them on a focused `AdGroupContentsRepository` (peer to `CampaignsRepository`) built from the same `ScopedClient`, so the campaigns repo stays about campaigns/ad-groups.

### D3: Small Decodable models

`ProductAd` (id, asin?, sku?, state), `Keyword` (id, keywordText, matchType, state, bid?), `TargetingClause` (id, a human-readable expression, state, bid?). Decode straight from the SP v3 JSON; map the targeting-clause `expression` array into a short display string.

### D4: One view model, parallel loads, partial-failure tolerance

`AdGroupDetailViewModel.load(adGroupId:using:accounts)` builds the repository from `accounts.scopedClient()` and fetches the three lists with a task group; a failure in one kind degrades that section (empty + note) without failing the whole screen — the screen only shows a top-level error if _all three_ fail. View model `@MainActor @Observable`; models `Sendable` (inferred).

### D5: Navigation

`CampaignDetailView`'s `AdGroupRow` becomes a `NavigationLink` to `AdGroupDetailView(adGroup:)`. The detail reads the shared `AccountsViewModel` from the environment (same as the other data screens).

## Risks / Trade-offs

- **Exact response field names** (productAd `adId` vs `productAdId`; targeting-clause `expression` shape) → Mitigation: model defensively with optionals; verify against a live ad group during apply (same approach that worked for campaigns).
- **Targeting-clause expression rendering** (nested type/value arrays) → Mitigation: map to a concise string with a sensible fallback to the raw type.
- **Extra empty call per ad group** (D1) → Mitigation: accepted; three small POSTs in parallel, paged with the same cap.

## Open Questions

- Show product ads by ASIN, SKU, or both? (Leaning: ASIN, with SKU as secondary when present.)
- Surface each section's count in its header? (Leaning: yes — cheap and useful.)
- Group keywords by match type? (Leaning: no for v1 — flat list with a match-type badge.)
