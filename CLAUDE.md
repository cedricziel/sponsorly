# Sponsorly

iOS app for managing Amazon Ads campaigns (Sponsored Products, Sponsored Brands, Sponsored Display). SwiftUI, iOS 26+, Swift 5.10 with strict concurrency.

## Project generation

The `Sponsorly.xcodeproj` is **generated** from `project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen) and is git-ignored. **Never edit `.xcodeproj` by hand** — your changes will be wiped on the next generate.

```sh
xcodegen generate          # regenerate after adding/removing/moving source files
open Sponsorly.xcodeproj
```

After creating, moving, or deleting a `.swift` file under `Sponsorly/` or `SponsorlyTests/`, run `xcodegen generate` before building — sources are picked up by folder, but the project file needs to be rewritten.

## Build & test

```sh
xcodebuild -scheme Sponsorly -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -scheme Sponsorly -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

If `iPhone 17 Pro` is unavailable, list simulators with `xcrun simctl list devices available | grep iPhone`.

## Layout

```
project.yml                       # single source of truth for the Xcode project
Sponsorly/
  SponsorlyApp.swift              # @main entry point
  RootView.swift                  # TabView shell
  Features/
    Campaigns/                    # campaign list & detail
    Reports/                      # performance reports
    Settings/                     # account, sign-in (Login with Amazon)
  Assets.xcassets/
  Preview Content/                # SwiftUI #Preview-only assets (dev-only)
SponsorlyTests/                   # XCTest unit tests
```

Add new feature folders under `Sponsorly/Features/<Name>/`. Keep view files small and one-per-file; favor `#Preview` blocks colocated with the view.

## Conventions

- **Concurrency:** `SWIFT_STRICT_CONCURRENCY=complete` is on. New types crossing isolation boundaries must be `Sendable`; UI types are `@MainActor` by default through SwiftUI.
- **Bundle id:** `com.cedricziel.sponsorly` (tests: `.tests`). Version comes from `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml`.
- **Secrets:** never commit API credentials. `*.env`, `secrets.plist` are git-ignored. Amazon Ads / Login-with-Amazon credentials belong in Keychain at runtime, not in the repo.
- **Commits:** semantic commits (`feat:`, `fix:`, `chore:`, `refactor:`, `docs:`, `test:`). One logical change per commit.

## Domain notes

Target API is the [Amazon Ads API](https://advertising.amazon.com/API/docs/en-us/) (NOT the seller/MWS/SP-API). Auth flow is OAuth 2.0 via **Login with Amazon (LWA)**, then the LWA refresh token is exchanged for Amazon Ads access tokens scoped to one or more advertising profiles. Most endpoints require both `Authorization: Bearer <access_token>` and `Amazon-Advertising-API-Scope: <profileId>`.

When implementing API clients, check current docs via context7 — Amazon's API surface changes (v2 → v3 migrations are ongoing for several report types).

## Things to double-check before declaring a UI task done

- Build for the simulator and launch the feature you changed — `xcodebuild build` alone proves nothing about the screen.
- Run the relevant `#Preview` in Xcode's canvas; SwiftUI errors that escape the type-checker often show up there.
