## Context

Sponsorly is a SwiftUI iOS 26+ app whose Xcode project is **generated** from
`project.yml` by XcodeGen — `Sponsorly.xcodeproj` is git-ignored. The build
also references a git-ignored `Secrets.xcconfig` (LWA client id/secret, only
meaningful at runtime). Quality is currently enforced only by an optional local
pre-commit hook (`.githooks/pre-commit`) running SwiftFormat → prettier →
SwiftLint; nothing checks compilation or tests automatically. The app depends
on the remote `swift-amazon-ads` SwiftPM package (tracked to `main`).

This change adds a GitHub Actions CI workflow. The work is pure
infrastructure — no app source, MVVM layers, or runtime behavior change — so
the usual View/ViewModel/Repository and TDD seams do not apply; the workflow is
validated by running on its own pull request.

## Goals / Non-Goals

**Goals:**

- One workflow that, on PRs to `main` and pushes to `main`, regenerates the
  project, builds the app + test bundle for an iOS 26 simulator, runs the unit
  tests, and enforces SwiftFormat/SwiftLint.
- Reproducible from a clean checkout with no checked-in `.xcodeproj` and no real
  secrets on the runner.
- Reasonable wall-clock time via dependency/derived-data caching.

**Non-Goals:**

- Code signing, archiving, TestFlight/App Store distribution, or any
  device (non-simulator) build.
- UI tests or snapshot tests (none exist yet).
- Marking the check "required" in branch protection — that is a repo setting,
  noted as a follow-up, not part of this change's files.
- Injecting real LWA credentials; the app does not need them to build or test.

## Decisions

### Decision: GitHub Actions on a macOS runner pinned to an Xcode 26 toolchain

Use GitHub-hosted macOS runners (the project already lives on GitHub). Pin the
Xcode version explicitly with `xcode-select`/`DEVELOPER_DIR` rather than relying
on the runner default, because iOS 26 SDK requires Xcode 26 and an unpinned
default can drift. Use the `macos-26` runner image (or the newest image that
ships Xcode 26) and select that Xcode in an early step.

- _Alternative considered:_ self-hosted runner — rejected; unnecessary
  operational burden for a solo project.
- _Alternative considered:_ fastlane — rejected; adds a Ruby toolchain and
  abstraction over `xcodebuild` we do not need for two commands.

### Decision: Regenerate the project with XcodeGen in CI

Install XcodeGen (Homebrew or Mint) and run `xcodegen generate` after checkout,
before any `xcodebuild` invocation. This is mandatory since the `.xcodeproj` is
git-ignored. Pin the XcodeGen version where practical for reproducibility.

### Decision: Synthesize a placeholder `Secrets.xcconfig`

`project.yml` wires `Secrets.xcconfig` as the Debug/Release `configFiles`
entry, so generation/build fails without it. CI copies
`Secrets.example.xcconfig` → `Secrets.xcconfig` (placeholder values). The LWA
id/secret are read at runtime via `Bundle.main`; nothing in build or test
exercises them, so placeholders are sufficient and no GitHub secret is needed.

- _Alternative considered:_ store real credentials as GitHub Actions secrets and
  write them into the xcconfig — rejected; unnecessary exposure for zero build
  benefit, and violates the "no real secrets needed to build" principle.

### Decision: Single job, ordered steps — lint then build+test

One job keeps it simple and lets all steps share the generated project and
caches. Run lint first (fast fail on style) then `xcodebuild build-for-testing`
followed by `test-without-building` (or a single `xcodebuild test`) for the
`Sponsorly` scheme against `platform=iOS Simulator,name=iPhone 17 Pro` (with a
fallback to whatever iPhone simulator the runner exposes), passing
`CODE_SIGNING_ALLOWED=NO` since simulator builds need no signing.

- _Alternative considered:_ parallel lint and build jobs — rejected for now;
  matrix/parallelism adds cache duplication and YAML complexity disproportionate
  to a build measured in a few minutes. Easy to split later.

### Decision: Mirror the pre-commit hook's tools, in verify mode

CI runs SwiftFormat in `--lint` mode and SwiftLint (matching `.swiftlint.yml`)
over the Swift sources, so CI fails on exactly the drift the local hook would
auto-fix. Prettier (json/md/yml) is left to the local hook for now; it is
format-only and low-risk, and can be added to CI later if churn appears.

### Decision (optional): Add a thin `Makefile`

CLAUDE.md already instructs `make lint` / `make format`, but no `Makefile`
exists. Optionally add one exposing `format`, `lint`, `build`, `test`,
`generate` targets that wrap the same commands CI runs, so contributors and CI
share one source of truth. Kept optional/low-priority — the workflow can invoke
tools directly if the Makefile is deferred.

### Decision: Pin `swift-amazon-ads` to an exact tag in `project.yml`

Change the `AmazonAds` package reference from `branch: main` to an exact
released tag (`v1.0.0`, the current latest) using XcodeGen's `version`/
`exactVersion`. This makes every checkout build against an immutable revision
instead of silently moving whenever upstream `main` advances — the precondition
for a meaningful green-CI signal and for the cache key below being stable.

- _Alternative considered:_ `from: 1.0.0` (float within the 1.x major) — rejected
  for now; exact pinning is the stricter, more reproducible default and Renovate
  (below) supplies the controlled path to bump it. Switching to `from:` later is
  trivial if minor auto-updates become desirable.
- _Alternative considered:_ keep `branch: main` — rejected; non-reproducible
  builds and upstream-driven CI breakage with no local change.

### Decision: Renovate over Dependabot for automated updates

Use Renovate (`renovate.json`), not Dependabot, because Dependabot's `swift`
ecosystem requires a `Package.swift` manifest — which this XcodeGen app does not
have (packages are declared in `project.yml`; the only `Package.resolved` lives
inside the git-ignored `.xcodeproj`). Dependabot could therefore update the CI
Actions but **not** the `swift-amazon-ads` pin. Renovate closes that gap with a
**custom (regex) manager** that matches the version string next to the
`swift-amazon-ads` URL in `project.yml` and resolves new versions from the
`github-tags` datasource, opening a PR per new tag. Renovate's native
`github-actions` manager covers the workflow's actions in the same config. Every
such PR is gated by the CI workflow, so a bad bump fails before merge.

- _Alternative considered:_ Dependabot (`github-actions` only) + manual Swift
  pin bumps — rejected; leaves the most important dependency un-automated.
- _Alternative considered:_ run both tools — rejected; redundant on
  github-actions and more moving parts for no gain.
- _Setup note:_ Renovate runs as the Mend GitHub App or a self-hosted
  `renovatebot/github-action` workflow; the app install is a one-time repo
  setting (out of band, like branch protection), and `renovate.json` is the only
  file this change commits.

### Decision: Cache SwiftPM dependencies and DerivedData

Cache `~/Library/Developer/Xcode/DerivedData/**/SourcePackages` (or
`-clonedSourcePackagesDirPath`) and the resolved-package state, keyed on a hash
of the package pins. With `swift-amazon-ads` now pinned to an exact tag, the
cache key derived from the package references is stable run-to-run and only
changes when a Renovate PR bumps the pin — no time-bounded fallback needed.

## Risks / Trade-offs

- **Runner Xcode 26 / macos-26 image availability or naming drift** → Pin the
  image and select Xcode explicitly; if the image label changes, update one
  `runs-on`/`DEVELOPER_DIR` line. Fail loudly (print `xcodebuild -version`).
- **Pinning `swift-amazon-ads` freezes us until someone bumps it** → That is the
  point (reproducibility); Renovate's custom manager opens the bump PR
  automatically when a new tag ships, and CI gates it — so staleness is visible
  and updating is a reviewed one-click, not a silent drift.
- **The Renovate custom-manager regex is brittle to `project.yml` formatting**
  → Keep the regex anchored on the stable `swift-amazon-ads` URL line; validate
  it opens a correct PR once after enabling, and treat the regex as testable
  config (a malformed match simply yields no PR, never a bad edit to the build).
- **Simulator device name (`iPhone 17 Pro`) may be absent on the runner** →
  Resolve the destination dynamically (query `xcrun simctl list devices
available`) or fall back to a generic `platform=iOS Simulator,OS=latest`
  destination.
- **Placeholder secrets could mask a real config-reading bug** → Acceptable;
  build/test never exercise the credential path, and runtime auth is covered by
  app behavior, not CI.
- **First run is slow (cold cache, package resolution, simulator boot)** →
  One-time cost; caching amortizes subsequent runs.

## Migration Plan

1. Pin `swift-amazon-ads` in `project.yml` (`branch: main` → `version: 1.0.0`),
   then add `.github/workflows/ci.yml`, `renovate.json` (and optional
   `Makefile`) on a feature branch.
2. Open a PR — the workflow runs against itself; iterate until green.
3. Merge. Subsequent PRs are gated automatically.
4. Enable Renovate on the repo (install the Mend GitHub App, or add the
   self-hosted action workflow). Confirm its first run opens a sensible
   onboarding/dependency PR.
5. **Rollback:** delete or disable `ci.yml` / `renovate.json`; revert the
   `project.yml` pin to `branch: main` if needed. No app code is touched, so
   rollback is a config revert with zero runtime impact.
6. **Follow-up (repo setting, out of scope here):** mark the `ci` check required
   in `main` branch protection once it is reliably green.

## Open Questions

- Add prettier (json/md/yml) verification to CI now, or keep it local-only?
- Land the `Makefile` as part of this change, or as a separate follow-up?
- Renovate hosting: Mend GitHub App (simplest) vs self-hosted
  `renovatebot/github-action` (keeps everything in-repo, no third-party app)?
