## 1. Per-region connection model (auth refactor)

- [x] 1.1 Introduce per-region connection state: derive "connected" from a stored refresh token per `AmazonRegion` (add `connectedRegions()` to the auth layer)
- [x] 1.2 Refactor `AuthViewModel` from a single `selectedRegion` to per-region sign in / sign out / status, building an `LWAAuthService` per region
- [x] 1.3 Persist the set of connected regions implicitly via storage; restore each region's state on launch
- [x] 1.4 Update `SettingsView` to show each region's connection state with per-region Sign in / Sign out
- [x] 1.5 Update auth tests / previews for the per-region model

## 2. Account discovery (per-region fetch + aggregate)

- [x] 2.1 Add a token-provider accessor per connected region (reuse `LWAAuthService.tokenProvider()`)
- [x] 2.2 Fetch profiles per region via `AmazonAdsProfilesAPIv2.listProfiles` on an `AuthenticatedTransport` with `profileId: nil`
- [x] 2.3 Fetch manager accounts per region via a direct `GET <region base>/managerAccounts`, decoding `AmazonManagerAccountsResponse`; treat 404/empty as "none"
- [x] 2.4 Add `actor AccountsRepository` that fetches both per region in parallel and returns successes + per-region errors
- [x] 2.5 Unit tests for the repository using a mocked URL protocol (success, partial failure, empty)

## 3. Aggregated account model

- [x] 3.1 Define Sendable Sponsorly models flattening profiles + manager/linked accounts into a region-tagged tree (leaf = selectable profile)
- [x] 3.2 Merge across regions and dedupe leaves by `profileId`
- [x] 3.3 Unit tests for merge + dedupe

## 4. Active profile selection & persistence

- [x] 4.1 Persist the active selection as `{ region, profileId }` in `UserDefaults`
- [x] 4.2 Restore the active profile on launch only if its region is still connected; otherwise clear
- [x] 4.3 Clear the active profile when its region is disconnected and prompt for a new selection
- [x] 4.4 Unit tests for selection persistence and the disconnected-region clearing rule

## 5. Scoped client factory

- [x] 5.1 Add a factory that builds an `AuthenticatedTransport(tokenProvider:clientId:profileId:)` + region base URL for the active profile
- [x] 5.2 Fail fast with a clear error when no active profile is selected
- [x] 5.3 Unit test the factory (correct profileId/region wiring; no-active-profile error)

## 6. Accounts UI

- [x] 6.1 Add `Sponsorly/Features/Accounts/` with an account list grouped by region → manager account → profile, per Apple HIG
- [x] 6.2 Indicate and allow switching the active profile; reflect the active profile elsewhere (Settings)
- [x] 6.3 Loading, empty, and per-region-error states (non-blocking notice); pull-to-refresh
- [ ] 6.4 `#Preview`s covering connected/empty/partial-failure states

## 7. Wire-up & verification

- [x] 7.1 Run `xcodegen generate` after adding the new files
- [x] 7.2 Build for the simulator
- [x] 7.3 Run tests
- [x] 7.4 Run `swiftformat` + `swiftlint` (lint clean)
- [ ] 7.5 On device: connect ≥1 region, load Accounts, confirm real profiles/manager accounts appear, select an active profile, relaunch and confirm it restores
- [ ] 7.6 Confirm a scoped `AuthenticatedTransport` for the active profile carries the correct `Amazon-Advertising-API-Scope` header (log/inspect one request)
- [ ] 7.7 Commit as semantic commits (auth refactor, accounts repository/model, UI), one logical change per commit
