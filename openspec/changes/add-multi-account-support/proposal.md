## Why

Authentication is done, but a Bearer token alone can't fetch advertising data — almost every Amazon Ads endpoint requires an `Amazon-Advertising-API-Scope: <profileId>` header, and profiles are region-specific (the same login can hold accounts in NA, EU, and FE, often under manager accounts). Before we build any campaign/report features, the app needs to connect across regions, discover the user's accounts/profiles, and let the user pick the **active profile** that scopes every subsequent call. This is the missing layer between "signed in" and "showing data."

## What Changes

- Allow the user to be **signed in to multiple regions at once** (NA / EU / FE), instead of one active region. Auth state and sign in/out become **per region**.
- After sign-in, fetch **advertising profiles** (`GET /v2/profiles`, ProfilesAPIv2) and **manager accounts** (`GET /managerAccounts`) for each connected region.
- **Aggregate** accounts across all connected regions into one model: manager account → linked accounts → profiles, each tagged with its region, with flat (non-manager) profiles included.
- Let the user **select an active profile**; persist the selection (region + `profileId`).
- Expose a **scoped client seam**: build an `AuthenticatedTransport(tokenProvider:clientId:profileId:)` for the active profile's region + id, ready for the data features to consume.
- Add an **Accounts** UI (browse the hierarchy across regions, see the active profile, switch it; connect/disconnect regions).

## Capabilities

### New Capabilities

- `advertising-accounts`: Discovering, aggregating, and selecting Amazon advertising accounts/profiles across connected regions (including manager-account hierarchies), and providing the active-profile-scoped client used by all data features.

### Modified Capabilities

- `lwa-authentication`: Sign-in becomes **multi-region concurrent** — the single active-region model (one region, fixed while signed in) is replaced by independent per-region connection state. (Delta spec included here. **Archive `add-lwa-authentication` before this change** so the modification resolves against a base spec.)

## Impact

- **New code:** a new `Sponsorly/Features/Accounts/` feature (account list/picker UI) and supporting types — an accounts repository that calls ProfilesAPIv2 `listProfiles` + the `/managerAccounts` endpoint per region, an aggregated account model, active-profile persistence, and a factory that builds the scoped `AuthenticatedTransport`.
- **Modified code:** the auth layer (`AuthViewModel`, region handling) shifts from a single `selectedRegion` to per-region connection state; `SettingsView` account section is reworked (or links to the new Accounts screen). `KeychainTokenStorage` already keys per region, which helps.
- **Dependencies:** consumes existing `swift-amazon-ads` — `AmazonAdsProfilesAPIv2` (`listProfiles`), `AmazonProfile` / `AmazonAccountInfo` / `AmazonManagerAccountsResponse` / `AmazonManagerAccount` / `AmazonLinkedAccount`, and `AuthenticatedTransport`. The `/managerAccounts` call has no generated client, so it's a direct request (the legacy client shows the shape).
- **Domain facts:** `/v2/profiles` returns only profiles for the region queried, so "all accounts" = query each connected region and merge. A single Security Profile works across all regions. `profileId` is the scope unit.
- **Out of scope:** any actual campaign/report/data calls (this change ends at "active profile selected, scoped client ready"); a backend token proxy (still deferred, resurfaces with distribution per add-lwa-authentication design D4).
- **Sequencing:** archive `add-lwa-authentication` first (it's implemented) so the `lwa-authentication` delta has a base.
