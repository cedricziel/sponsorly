## 1. Pin the Swift dependency

- [x] 1.1 In `project.yml`, change the `AmazonAds` package from `branch: main` to an exact tag. (Note: `v1.0.0` predates the `AmazonAdsProfilesAPIv2`/`AmazonAdsReportingAPIv3` modules the app uses, so a `v1.1.0` release was cut on `swift-amazon-ads` at `main` HEAD `309e34a` and the app is pinned to `exactVersion: 1.1.0`.)
- [x] 1.2 Run `xcodegen generate` and confirm the pin resolves `swift-amazon-ads` to `1.1.0`; build locally to verify the pin compiles (`build-for-testing` succeeded).

## 2. Workflow scaffold & triggers

- [x] 2.1 Create `.github/workflows/ci.yml` with `name: CI` and triggers: `pull_request` to `main` and `push` to `main`.
- [x] 2.2 Add `concurrency` (group by ref, cancel-in-progress) so superseded PR runs are cancelled.
- [x] 2.3 Set the job to `runs-on: macos-26` (or the newest image shipping Xcode 26) with sensible `timeout-minutes`.

## 3. Toolchain & environment

- [x] 3.1 Add a checkout step (`actions/checkout`).
- [x] 3.2 Select the Xcode 26 toolchain explicitly (`xcode-select` the newest `/Applications/Xcode_26*`) and print `xcodebuild -version` to log the resolved toolchain.
- [x] 3.3 Install XcodeGen, SwiftFormat, and SwiftLint on the runner via Homebrew. (Versions left to Homebrew latest; pin later if reproducibility requires it.)

## 4. Project generation & secrets

- [x] 4.1 Synthesize a placeholder `Secrets.xcconfig` by copying `Secrets.example.xcconfig` (no real LWA credentials; nothing printed to the log).
- [x] 4.2 Run `xcodegen generate` (via `make generate`) to produce `Sponsorly.xcodeproj` from `project.yml`.

## 5. Dependency caching

- [x] 5.1 Cache resolved SwiftPM packages (`build/SourcePackages`) keyed on `hashFiles('project.yml')` (stable now that the dependency is exact-pinned), with a `restore-keys` fallback.
- [x] 5.2 Add an explicit `make resolve` step so resolution failures surface clearly before the build.

## 6. Lint & format enforcement

- [x] 6.1 Run SwiftFormat in `--lint` mode (no writes) over the Swift sources; fail on any drift. (Also formatted the existing tree to a clean baseline so the gate starts green; added `excluded:` build dirs to `.swiftlint.yml` and `--exclude` to the Makefile.)
- [x] 6.2 Run SwiftLint against `.swiftlint.yml`; fail on violations.

## 7. Build & test

- [x] 7.1 Resolve the simulator destination robustly: prefer `iPhone 17 Pro`, else fall back to the newest available iPhone (`Select simulator destination` step).
- [x] 7.2 Build the `Sponsorly` scheme for the simulator with `CODE_SIGNING_ALLOWED=NO` via `build-for-testing` so the test step reuses products.
- [x] 7.3 Run the test action (`test-without-building`) for the `Sponsorly` scheme against the resolved simulator destination.
- [x] 7.4 Ensure any compile error or test failure fails the job with a non-zero exit (`set -euo pipefail` in shell steps; `make` propagates `xcodebuild` exit codes).

## 8. Renovate configuration

- [x] 8.1 Add `renovate.json` extending `config:recommended` (which enables the `github-actions` manager).
- [x] 8.2 Add a custom (regex) manager matching the `swift-amazon-ads` `exactVersion` string in `project.yml`, with `depName` `cedricziel/swift-amazon-ads`, `datasource` `github-releases`, and `extractVersion` stripping the leading `v`. Regex verified to extract `1.1.0`.
- [ ] 8.3 Enable Renovate on the repo (install the Mend GitHub App, or add a self-hosted `renovatebot/github-action` workflow) and confirm its first run opens a sensible onboarding/dependency PR. **Requires a GitHub-side action by the maintainer — config is committed and ready.**

## 9. Shared Makefile

- [x] 9.1 Add a `Makefile` exposing `generate`, `secrets`, `resolve`, `format`, `lint`, `build`, `test`, `build-for-testing`, `test-without-building` targets that wrap the exact commands CI runs.
- [x] 9.2 Workflow steps call the `make` targets (`generate`, `resolve`, `lint`, `build-for-testing`, `test-without-building`) for parity.

## 10. Validate & document

- [ ] 10.1 Open a pull request and confirm the workflow runs against itself and goes green (build + tests + lint), iterating on runner image / destination / cache keys as needed. **Requires pushing the branch + opening the PR (maintainer action); locally `make lint` and `build-for-testing` are green.**
- [x] 10.2 Add a CI status badge to `README.md`.
- [x] 10.3 Note the follow-up (not part of this change): mark the `CI` check as a required status check in `main` branch protection (documented in design.md migration plan).
