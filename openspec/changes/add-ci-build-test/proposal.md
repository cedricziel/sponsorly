## Why

The project has no automated checks: lint, formatting, build, and tests run
only locally via the optional pre-commit hook, so a push or PR can land code
that fails to compile under strict concurrency or breaks tests. As the app
grows toward real-money write operations, an enforced green-on-merge signal is
the cheapest guardrail we can add. Now is the right time because the build is
still fast and the toolchain (XcodeGen + xcconfig secrets) is settled.

## What Changes

- Add a GitHub Actions workflow that runs on pull requests to `main` and on
  pushes to `main`.
- The workflow regenerates the Xcode project with **XcodeGen** (the
  `.xcodeproj` is git-ignored), since CI cannot rely on a checked-in project.
- It synthesizes a placeholder `Secrets.xcconfig` from
  `Secrets.example.xcconfig` so the build resolves — real LWA credentials are
  only needed at runtime, never to compile or test.
- It resolves and caches the `swift-amazon-ads` Swift Package dependency.
- It **builds** the `Sponsorly` scheme and runs the **test** action for an
  iOS 26 simulator, with code signing disabled (simulator builds need none).
- It runs **SwiftFormat** (lint mode, no writes) and **SwiftLint** to enforce
  the style the pre-commit hook applies locally, so formatting drift fails CI.
- The job pins an Xcode version that ships the iOS 26 SDK on a macOS runner.
- **Pin the `swift-amazon-ads` dependency** in `project.yml` from the floating
  `branch: main` to an exact tagged version (`v1.0.0`), so builds are
  reproducible instead of silently moving with upstream `main`.
- **Add Renovate** (`renovate.json`) to automate dependency updates:
  - a **custom (regex) manager** that tracks the pinned `swift-amazon-ads`
    version in `project.yml` against the repo's GitHub tags and opens a PR when
    a newer tag ships, and
  - the native **github-actions** manager to keep the CI workflow's action
    versions current.
    Renovate is chosen over Dependabot because Dependabot's `swift` ecosystem
    requires a `Package.swift` manifest this XcodeGen app does not have, so it
    could not update the Amazon Ads pin; Renovate's custom manager can. See
    design.md.

This is infrastructure only — no app source, View/ViewModel/Repository layers,
models, or runtime behavior change. The "test seam" for this change is the
workflow itself: it is validated by running on its own pull request and
observing a green build + test run.

## Capabilities

### New Capabilities

- `ci-pipeline`: Automated continuous-integration that, on every PR and push to
  `main`, generates the project, builds the app and test bundle for an iOS
  simulator, runs the unit tests, and enforces formatting/lint — producing a
  required pass/fail signal before merge.
- `dependency-management`: Reproducible dependency versions (the
  `swift-amazon-ads` package pinned to an exact tag in `project.yml`) plus
  automated update proposals via Renovate for both that pin and the CI
  workflow's GitHub Actions.

### Modified Capabilities

<!-- None — no existing spec's requirements change. -->

## Impact

- **New files:** `.github/workflows/ci.yml` (the workflow) and `renovate.json`
  (Renovate config: custom manager for the `project.yml` Swift pin +
  github-actions manager). Optionally a thin `Makefile` exposing
  `lint`/`format`/`build`/`test` targets so CI and the CLAUDE.md instructions
  share one source of truth.
- **Changed files:** `project.yml` — `AmazonAds` package pin moves from
  `branch: main` to an exact `version`/tag (`v1.0.0`). This is the only app-repo
  config change; no Swift source changes.
- **Dependencies / tooling on the runner:** XcodeGen, SwiftFormat, SwiftLint
  (installed via Homebrew or Mint), Xcode 26 toolchain, the
  `swift-amazon-ads` SwiftPM package (network-resolved, cached).
- **No app code, no secrets in the repo:** CI generates a throwaway
  `Secrets.xcconfig` with placeholder values; the real one stays git-ignored.
- **Repo settings (follow-up, not code):** the `ci` check can later be marked a
  required status check on the `main` branch protection rule.
