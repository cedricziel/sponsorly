## Why

You can browse campaigns → ad groups, but an ad group is a dead end — tapping it shows nothing. The next step down the Sponsored Products tree is an ad group's actual contents: the **product ads** (the ASINs/SKUs being advertised) and its **targeting** (keywords or product/auto targets). This makes an ad group inspectable end to end and completes the read-only browse of the SP hierarchy.

## What Changes

- Make ad-group rows navigable to a new **ad-group detail** screen.
- On that screen, list the ad group's **product ads** (`POST /sp/productAds/list`), **keywords** (`POST /sp/keywords/list`), and **targeting clauses** (`POST /sp/targets/list`) for the active profile, filtered by `adGroupId`.
- Show non-empty sections only — an ad group has keywords _or_ targets depending on its campaign's targeting type, so fetch both and render whichever are present (plus product ads).
- Loading indicator, empty/error (with retry) states, pull-to-refresh, and `nextToken` paging — consistent with the campaigns/ad-groups screens.

## Capabilities

### New Capabilities

<!-- None — this extends the existing browse capability. -->

### Modified Capabilities

- `sponsored-products-campaigns`: ADD ad-group detail — listing a selected ad group's product ads and targeting (keywords + targeting clauses). Additive only (no existing requirement changes); the change is archived after the current spec, which already exists in `openspec/specs/`.

## Impact

- **New code:** an `AdGroupDetailView` (+ `AdGroupDetailViewModel`), small `ProductAd` / `Keyword` / `TargetingClause` `Decodable` models, and three list methods on the existing repository (or a peer `AdGroupContentsRepository`) following the established direct-POST + paging pattern.
- **Modified code:** `CampaignDetailView`'s ad-group rows become `NavigationLink`s into the detail.
- **Dependencies:** reuses the active-profile `ScopedClient` (region base URL, clientID, profileId, tokenProvider). SP v3 list endpoints are `POST .../list` with vendored content types (`application/vnd.spProductAd.v3+json`, `…spKeyword.v3+json`, `…spTargetingClause.v3+json`) and `nextToken` paging.
- **Domain facts:** keywords belong to manual keyword-targeted ad groups; targeting clauses cover auto targeting and product/category targets; an ad group may legitimately have one, the other, or (for product ads) always some. Every call is scoped by `Amazon-Advertising-API-Scope: <active profileId>`.
- **Out of scope:** negative keywords / negative targets (ad group + campaign level); any create / update / archive; bid editing; Sponsored Brands & Display; performance metrics / reports.
