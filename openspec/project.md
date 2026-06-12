# Project Context

> Read by OpenSpec's propose/apply skills. Keep it short, true, and enforceable —
> every line here is a constraint a change is expected to honor.

## Purpose

Sponsorly is an iOS app for managing Amazon Ads campaigns (Sponsored Products,
Sponsored Brands, Sponsored Display) — moving from a read-only entity browser
toward an optimization tool (spend overview, search-term harvesting, and future
bid/budget writes).

## Tech Stack

- **Language:** Swift 5.10, `SWIFT_STRICT_CONCURRENCY=complete`.
- **UI:** SwiftUI, iOS 26+. State via the `Observation` framework (`@Observable`), not `ObservableObject`/Combine.
- **Charts:** Swift Charts.
- **Networking:** `URLSession` (no third-party HTTP client).
- **Project file:** generated from `project.yml` by XcodeGen — `.xcodeproj` is git-ignored; never hand-edit it.
- **Tests:** XCTest.

## Conventions

### Architecture — MVVM + Repository (required)

Every feature lives in `Sponsorly/Features/<Name>/` and is built from three layers.
A change MUST place new code in the right layer; no business logic in views, no
networking in view models.

- **View** — `*View.swift`. SwiftUI only: layout, bindings, and `#Preview`. No
  networking, no decoding, no scoring/aggregation logic. Reads state off a view
  model; sends user intent back via `async` methods or bindings.
- **ViewModel** — `*ViewModel.swift`. `@MainActor @Observable final class`.
  Owns presentation state as `private(set) var` plus a mutable `var errorMessage:
String?`. Exposes `async` intent methods (e.g. `load(using:)`). Orchestrates
  repositories; never touches `URLSession` directly. Concurrent fetches use
  `async let`; a single failing source degrades only its own tile, not the screen.
- **Repository** — `*Repository.swift`. An `actor` that owns one capability's data
  access (create/poll/download/decode, reads, or writes). Dependencies are
  **injected** — a `ScopedClient` and `urlSession: URLSession = .shared` — so tests
  can drive it offline. No SwiftUI imports.
- **Models** — plain `Sendable` value types (`*Models.swift`, or one type per file
  for domain entities). `Codable` where they cross the API boundary.
- **Errors** — per-domain `enum ... : LocalizedError` with user-facing
  `errorDescription` (see `ReportError`). View models surface
  `errorDescription` into `errorMessage`; views render it.

After adding/moving/deleting a `.swift` file, run `xcodegen generate` before building.

### Testing — TDD (required)

Write the test first; let it fail; make it pass. Every change's `tasks.md` MUST
interleave test tasks with implementation tasks, not bolt them on at the end.

- **Framework:** XCTest, `@testable import Sponsorly`. One `SponsorlyTests/<Feature>Tests.swift` per feature.
- **Pure logic is the unit:** extract scoring, aggregation, and bucketing as
  `static` functions on the view model (e.g. `aggregateHeadline`, `topCampaigns`)
  and test them directly with plain inputs — no async, no network. This is the
  primary test seam; prefer it over testing through the UI.
- **Network is mocked, never live:** inject a `URLSession` backed by
  `MockURLProtocol` (see `SponsorlyTests/`) to drive repository request/response/
  status paths, including error and retry branches (e.g. the 425-duplicate reuse).
- **Coverage expectation:** new scoring/aggregation logic and every new error
  branch ship with tests in the same change. A capability isn't "done" in
  `tasks.md` until its tests are green.

### Git / commits

- Semantic commits (`feat:`, `fix:`, `chore:`, `refactor:`, `docs:`, `test:`), one logical change per commit.
- Run `make lint` and `make format` before committing.

## Domain Context

Target is the **Amazon Ads API** (not Seller/SP-API). Auth is OAuth 2.0 via Login
with Amazon (LWA); the refresh token is exchanged for Ads access tokens scoped per
advertising profile. Most calls need both `Authorization: Bearer <token>` and
`Amazon-Advertising-API-Scope: <profileId>` — this is what `ScopedClient` carries,
and why repositories take it by injection. Reporting uses the **async Reporting API
v3** (create → poll → download → gunzip → decode); past-day reports are immutable
and are cached. Verify endpoint specifics against current docs via context7 — the
v2→v3 migration is ongoing.

## Constraints

- **Secrets never in the repo.** LWA/Ads credentials live in Keychain at runtime; `*.env` and `secrets.plist` are git-ignored.
- **Strict concurrency.** Types crossing isolation boundaries are `Sendable`; UI is `@MainActor`.
- **Writes are real money.** Campaign/keyword writes (harvesting and beyond) must report per-item outcomes (added / skipped-duplicate / failed) and be covered by mocked-write tests before shipping.
