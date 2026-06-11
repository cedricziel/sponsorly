## Context

`add-lwa-authentication` delivered sign-in with a single active region, per-region Keychain token storage, and a `tokenProvider` closure that feeds `AuthenticatedTransport`. What's missing before any data feature: the **account/profile layer**. Amazon Ads scopes nearly every endpoint with `Amazon-Advertising-API-Scope: <profileId>`, and `GET /v2/profiles` returns profiles only for the region queried — so a login spanning NA/EU/FE (often via manager accounts) must be queried per region and merged.

The package provides what we need: `AmazonAdsProfilesAPIv2` (`listProfiles`), the models `AmazonProfile` / `AmazonAccountInfo` / `AmazonManagerAccountsResponse` / `AmazonManagerAccount` / `AmazonLinkedAccount`, and `AuthenticatedTransport(tokenProvider:clientId:profileId:)`. There is **no generated client for `/managerAccounts`**, so that's a direct request (the legacy `AmazonAdvertisingClient.fetchManagerAccounts` shows the shape: `GET <region base>/managerAccounts`).

Constraints unchanged: SwiftUI, iOS 26, Swift 5.10, `SWIFT_STRICT_CONCURRENCY=complete`, XcodeGen, Apple HIG.

## Goals / Non-Goals

**Goals:**
- Per-region connection state: connect/disconnect NA/EU/FE independently and concurrently.
- Discover profiles + manager accounts for every connected region and aggregate into one model.
- Select and persist an active profile (region + `profileId`); restore on launch.
- A factory that yields an active-profile-scoped `AuthenticatedTransport` for data features.
- An Accounts UI to browse the hierarchy, see/switch the active profile, and connect/disconnect regions.

**Non-Goals:**
- Any campaign/report/data calls (this change ends at "scoped client ready").
- Editing profiles (`updateProfiles`) or any write operations.
- A backend token proxy (still deferred; resurfaces with distribution — `add-lwa-authentication` D4).

## Decisions

### D1: Per-region connection state (replaces single active region)

Replace `AuthViewModel`'s single `selectedRegion` with per-region connection state — connected regions derived from "has a stored refresh token for this region." Sign in/out operate on a specific region. The connected set is implied by storage (already keyed per region), so little new persistence is needed. **Trade-off:** this refactors just-shipped auth code; mitigated by the existing token-provider tests and keeping `LWAAuthService` per-region as-is (we just build one per region as needed).

### D2: Account discovery — parallel per-region fetch

For each connected region, in parallel: (a) `listProfiles` via `AmazonAdsProfilesAPIv2` on an `AuthenticatedTransport` with **`profileId: nil`** (discovery isn't profile-scoped); (b) a direct `GET <region base>/managerAccounts`. Merge per region, then across regions. Failures are isolated per region (see D6). **Alternative:** legacy `AmazonAdvertisingClient.fetchProfiles/fetchManagerAccounts` — rejected: it's the desktop/loopback client; we use the generated ProfilesAPIv2 + a direct managerAccounts request to stay on the modern stack.

### D3: Aggregated account model

Introduce Sendable Sponsorly models that flatten the package types into a UI-friendly tree: a `ConnectedAccounts` value = per region, a list of manager accounts (each with linked profiles) plus standalone profiles, every leaf carrying `{ profileId, region, displayName, countryCode, managerAccountName? }`. A profile that appears both standalone and under a manager account is **deduped by `profileId`**. The selectable unit is the leaf profile.

### D4: Active-profile persistence

Persist the active selection as `{ region, profileId }` in `UserDefaults` (a `profileId` is not a secret; this is a cross-region pointer, so a single defaults entry is cleaner than the per-region `TokenStorageKey.profileId`). On launch, restore only if that region is still connected; otherwise clear and prompt (spec scenario).

### D5: Scoped client factory

A small factory: given the active profile, build `AuthenticatedTransport(tokenProvider: <active region's provider>, clientId:, profileId: <active profileId>)` plus the region's `advertisingAPIBaseURL`. This is the single seam every future data feature consumes — they never touch auth directly. Throws fast if no active profile is selected.

### D6: Partial-failure aggregation

Each region's fetch is independent; the repository returns successes plus a list of per-region errors. The UI shows what loaded and a non-blocking notice for any region that failed — never an all-or-nothing failure across regions.

### D7: Concurrency

An `actor AccountsRepository` owns fetching/merging (Sendable models cross back to the `@MainActor` view model). The Accounts view model is `@MainActor @Observable`. `LWAAuthService` stays per-region; we construct one per region for token provision.

## Risks / Trade-offs

- **`/managerAccounts` shape/availability** (no generated client, modeled on the legacy code) → Mitigation: decode into the package's `AmazonManagerAccountsResponse`; treat a 404/empty as "no manager accounts" rather than an error; verify against a live account during apply.
- **Refactoring just-shipped auth** (per-region model) → Mitigation: keep `LWAAuthService`/`KeychainTokenStorage` unchanged; the change is concentrated in `AuthViewModel`/UI. Rerun the auth tests.
- **Rate limits with many regions/accounts** → Mitigation: parallel-but-bounded fetches; cache results in the repository for the session.
- **Profile/manager overlap & dedupe** → Mitigation: dedupe by `profileId` (D3).
- **Spec ordering** — the `lwa-authentication` delta needs `add-lwa-authentication` archived first → Mitigation: archive that change before archiving this one (noted in the proposal).

## Open Questions

- Where does the Accounts UI live — a new top-level tab, or pushed from Settings? (Leaning: pushed from Settings for now, promotable to a tab later.)
- Should connecting regions live in the Accounts screen or stay in Settings? (Leaning: regions in Settings, account/profile selection in Accounts.)
- Session cache invalidation: manual pull-to-refresh only, or also refetch on becoming-active? (Leaning: manual refresh for v1.)
