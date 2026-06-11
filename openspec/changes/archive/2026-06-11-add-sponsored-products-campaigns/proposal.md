## Why

The whole stack is now in place — sign-in, regions, an active profile, and a scoped `AuthenticatedTransport` — but the Campaigns tab is still an empty placeholder. This change makes Sponsorly finally *show advertising data*: the active profile's **Sponsored Products campaigns and their ad groups**. It's the first real payoff of everything built so far and the foundation every later feature (metrics, editing, other ad products) builds on.

## What Changes

- Replace the Campaigns placeholder with a real **list of Sponsored Products campaigns** for the active profile (name, state, budget, targeting type).
- Add a **campaign detail** screen listing that campaign's **ad groups** (name, state, default bid).
- Fetch via the generated `AmazonAdsSponsoredProductsAPIv3` client (`ListSponsoredProductsCampaigns`, `ListSponsoredProductsAdGroups`) over the active profile's **scoped transport**, following `nextToken` pagination.
- Gate the tab on an active profile: prompt to select an account (the existing switcher) when none is set; reload when the active profile changes.
- Loading / empty / error states and pull-to-refresh.

## Capabilities

### New Capabilities

- `sponsored-products-campaigns`: Listing Sponsored Products campaigns and their ad groups for the active advertising profile (read-only), including paging and the active-profile-scoped client wiring.

### Modified Capabilities

<!-- None — this is additive. It consumes `advertising-accounts` (the scoped client) without changing its spec. -->

## Impact

- **New code:** the `Campaigns` feature gains a `CampaignsRepository` (wraps the generated SP v3 client over the scoped transport), lightweight `Campaign` / `AdGroup` UI models, a `CampaignsViewModel`, a campaigns list, and a campaign-detail (ad groups) screen.
- **Modified code:** `CampaignsView` replaces its `ContentUnavailableView` placeholder; reads the active profile / scoped client from the shared `AccountsViewModel`. `AccountsViewModel` exposes a `scopedClient()` seam (built on `ActiveProfileClientFactory`).
- **Dependencies:** the wired `AmazonAdsSponsoredProductsAPIv3` generated client + `AmazonAdsCore` (`AuthenticatedTransport`). SP v3 list endpoints are `POST .../list` with vendored content types (`application/vnd.spCampaign.v3+json`, etc.) and `nextToken` paging — the generated client handles content-type negotiation.
- **Domain facts:** every call is scoped by `Amazon-Advertising-API-Scope: <active profileId>` (already stamped by the scoped transport). Listing defaults to non-archived entities. Ad groups belong to a campaign (filter by `campaignId`).
- **Out of scope:** create / update / archive (read-only); Sponsored Brands & Sponsored Display; keywords, targets, product ads, budget rules, recommendations; **performance metrics / reports** (the Reporting API is async report generation — a separate change for the Reports tab).
