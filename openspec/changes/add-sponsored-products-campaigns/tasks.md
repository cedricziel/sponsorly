## 1. Scoped client seam

- [x] 1.1 Add `AccountsViewModel.scopedClient() throws -> ScopedClient` wrapping `ActiveProfileClientFactory` + `tokenProvider(for:)`
- [x] 1.2 Unit test the seam (returns a client for an active selection; throws `noActiveProfile` when none)

## 2. UI models

- [x] 2.1 Add `Sendable` `Campaign` (id, name, state, budget, targetingType) and `AdGroup` (id, name, state, defaultBid) structs
- [x] 2.2 Map the generated SP v3 campaign / ad-group types into these models (with fallbacks for optional fields)
- [x] 2.3 Unit tests for the mapping

## 3. Campaigns repository

- [x] 3.1 Add `actor CampaignsRepository` holding a `ScopedClient`, building `AmazonAdsSponsoredProductsAPIv3.Client(serverURL:transport:)`
- [x] 3.2 Implement `listCampaigns()` via `ListSponsoredProductsCampaigns` with vendored content-type headers, non-archived filter, and `nextToken` paging up to the cap
- [x] 3.3 Implement `listAdGroups(campaignId:)` via `ListSponsoredProductsAdGroups` filtered by campaign id, paged
- [x] 3.4 Surface a truncation indicator when the page cap is hit
- [x] 3.5 Unit tests with a mocked transport/URL protocol (success, empty, paging, error)

## 4. Campaigns view model + screen

- [x] 4.1 Add `@MainActor @Observable CampaignsViewModel` that builds the repository from `accounts.scopedClient()` and loads campaigns
- [x] 4.2 Replace `CampaignsView` placeholder: list campaigns; prompt to select an account when no active profile; reload on active-profile change (`.task(id:)`)
- [x] 4.3 Loading indicator (initial + refresh-keeps-content), empty / error (with retry) states, and pull-to-refresh
- [x] 4.4 `#Preview`s for populated / empty / no-active-profile states

## 5. Campaign detail (ad groups)

- [x] 5.1 Add a campaign detail screen that loads and lists the campaign's ad groups
- [x] 5.2 Loading indicator, empty / error states, and pull-to-refresh for ad groups
- [x] 5.3 Navigate from a campaign row to its detail
- [x] 5.4 `#Preview`s for the detail screen

## 6. Wire-up & verification

- [x] 6.1 Run `xcodegen generate` after adding the new files
- [x] 6.2 Build for the simulator
- [x] 6.3 Run tests
- [x] 6.4 Run `swiftformat` + `swiftlint` (lint clean)
- [ ] 6.5 On device: select an active profile, confirm real campaigns load, open one, confirm ad groups load; switch profile and confirm reload
- [ ] 6.6 Commit as semantic commits (scoped-client seam, repository/models, campaigns UI, detail), one logical change per commit
