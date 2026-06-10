# Sponsorly

iOS app for managing Amazon Ads campaigns (Sponsored Products, Sponsored Brands, Sponsored Display).

## Requirements

- Xcode 16+
- iOS 17.0+ deployment target
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Setup

```sh
xcodegen generate
open Sponsorly.xcodeproj
```

The `Sponsorly.xcodeproj` is generated from `project.yml` and is git-ignored. Re-run `xcodegen generate` after adding or removing source files.

## Project layout

```
project.yml                 # XcodeGen spec
Sponsorly/
  SponsorlyApp.swift        # @main entry point
  RootView.swift            # Tab shell
  Features/
    Campaigns/              # Campaign list & detail
    Reports/                # Performance reports
    Settings/               # Account, sign-in (LWA)
  Assets.xcassets/
  Preview Content/
SponsorlyTests/
```

## Build & test from the CLI

```sh
xcodebuild -scheme Sponsorly -destination 'platform=iOS Simulator,name=iPhone 16' build
xcodebuild -scheme Sponsorly -destination 'platform=iOS Simulator,name=iPhone 16' test
```
