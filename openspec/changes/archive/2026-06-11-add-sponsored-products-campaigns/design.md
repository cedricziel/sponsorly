## Context

Everything up to "scoped client ready" is done: `AccountsViewModel` holds the active profile, and `ActiveProfileClientFactory` yields a `ScopedClient` (`AuthenticatedTransport` stamping `Authorization`/`ClientId`/`Scope` + the region base URL). The Campaigns tab is still a placeholder. This change wires the first real data: Sponsored Products campaigns + ad groups for the active profile.

Sponsored Products v3 listing is `POST /sp/campaigns/list` and `POST /sp/adGroups/list` with **vendored content types** (`application/vnd.spCampaign.v3+json`, `application/vnd.spAdGroup.v3+json`), request bodies for filters/paging, and `nextToken` pagination. The generated `AmazonAdsSponsoredProductsAPIv3` client (`ListSponsoredProductsCampaigns`, `ListSponsoredProductsAdGroups`) handles the content-type negotiation — which is the main reason to use it here rather than hand-rolling requests (the opposite call from the simple profiles GET).

Constraints unchanged: SwiftUI, iOS 26, Swift 5.10, strict concurrency, XcodeGen, Apple HIG.

## Goals / Non-Goals

**Goals:**
- List the active profile's SP campaigns (name, state, budget, targeting type), paginated.
- Campaign detail listing its ad groups (name, state, default bid).
- Gate on active profile; reload on profile change; loading/empty/error states + pull-to-refresh.

**Non-Goals:**
- Create / update / archive (read-only this change).
- Sponsored Brands & Sponsored Display; keywords, targets, product ads, budget rules, recommendations.
- Performance metrics / reports (Reporting API is async report generation — a separate change).

## Decisions

### D1: Direct POST requests with the vendored content type (revised)

`CampaignsRepository` issues `POST <base>/sp/campaigns/list` and `/sp/adGroups/list` directly — setting `Content-Type`/`Accept` to the vendored media type (`application/vnd.spCampaign.v3+json`, `application/vnd.spAdGroup.v3+json`), the auth headers (Bearer + ClientId + `Scope: <profileId>`), and a JSON filter body — then decoding small `Decodable` models.

**Revised from the original plan** (generated `AmazonAdsSponsoredProductsAPIv3` client): the generated Input/Output is extremely verbose (vendored-named enum body cases, required typed header structs), and the "content-type negotiation" it provides is, in practice, just two header strings. Going direct is uniform with `advertising-accounts` D2, decodes straight into the UI models, and avoids wrestling generated types — the build came up green on the first try. The `ScopedClient` now also carries `clientID` + a `tokenProvider`, so the repository has everything it needs; the generated SP/SB/SD clients remain available via `ScopedClient.transport` for anything that genuinely needs them later.

### D2: Read-only entity data, not metrics

We show management-API fields (name, state, budget, targeting type; ad group name/state/bid). Performance numbers come from the Reporting API (async report polling) and are deliberately deferred to the Reports change, so this stays a focused, synchronous read.

### D3: Lightweight UI models

Map the verbose generated campaign/ad-group types into small `Sendable` `Campaign` / `AdGroup` structs (`id`, `name`, `state`, plus budget/targeting or bid) for the views — insulating the UI from generated-type churn and keeping previews simple.

### D4: Pagination with a cap

Follow `nextToken` until absent or a safety cap (e.g. 10 pages / ~1000 entities) is hit; if the cap is reached, surface that the list may be truncated (no silent truncation). Default the request filter to non-archived states.

### D5: UI flow and state ownership

`CampaignsView` reads the shared `AccountsViewModel` from the environment. A `@MainActor @Observable CampaignsViewModel` drives the list, fetching through a `CampaignsRepository` (actor) built from `accounts.scopedClient()`. The list reloads via `.task(id: activeSelection)` so switching the active profile refetches. Tapping a campaign pushes a detail view that lists ad groups (its own fetch by `campaignId`). `AccountsViewModel` gains a `scopedClient()` throwing accessor (wrapping `ActiveProfileClientFactory` + `tokenProvider(for:)`).

### D6: Concurrency

`CampaignsRepository` is an `actor` holding the `ScopedClient`; pagination loops inside it. View models are `@MainActor @Observable`; UI models are `Sendable`. Generated client calls suspend, so paging is naturally async.

## Risks / Trade-offs

- **Vendored content-type header wiring** in the generated client (Accept/Content-Type enums) → Mitigation: verify the exact `Input.Headers` shape during apply; the transport handles auth headers, the client handles content types.
- **`nextToken` paging cost / large accounts** → Mitigation: page cap + truncation notice (D4); manual refresh only (no auto-poll).
- **Generated-type verbosity / optionality** (fields are optional in the schema) → Mitigation: map into small UI models with sensible fallbacks (D3).
- **State filter semantics** (enabled/paused/archived) → Mitigation: default to non-archived; revisit a state filter UI later.
- **No active profile / token expiry mid-fetch** → Mitigation: `scopedClient()` throws `noActiveProfile` (already specified); the transport refreshes tokens transparently.

## Open Questions

- Show a campaign **state filter** (All / Enabled / Paused) in v1, or default to non-archived only? (Leaning: non-archived only for v1.)
- Campaign row detail density — budget + targeting type only, or also start date / bidding strategy? (Leaning: name + state + budget + targeting for v1.)
- Should ad groups also be reachable without opening a campaign (a flat "all ad groups" view)? (Leaning: no — ad groups live under their campaign.)
