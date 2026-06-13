## ADDED Requirements

### Requirement: CI runs on pull requests and pushes to main

The project SHALL provide a continuous-integration workflow that runs
automatically on every pull request targeting `main` and on every push to
`main`. The workflow SHALL report a single pass/fail status that gates merge.

#### Scenario: Pull request opened against main

- **WHEN** a pull request targeting `main` is opened or updated with new commits
- **THEN** the CI workflow is triggered automatically
- **AND** its pass/fail result is reported back to the pull request as a status check

#### Scenario: Push to main

- **WHEN** a commit is pushed directly to `main`
- **THEN** the CI workflow is triggered automatically

#### Scenario: No automated trigger on unrelated branches

- **WHEN** a commit is pushed to a branch with no open pull request to `main`
- **THEN** the workflow does not consume runner time for that push

### Requirement: CI generates the project before building

The workflow SHALL regenerate the project with XcodeGen before any build or
test step, and SHALL NOT depend on a checked-in `.xcodeproj` — because
`Sponsorly.xcodeproj` is git-ignored and generated from `project.yml`.

#### Scenario: Fresh checkout has no project file

- **WHEN** the workflow checks out the repository
- **THEN** it runs `xcodegen generate` to produce `Sponsorly.xcodeproj`
- **AND** all subsequent build/test steps use the generated project

### Requirement: CI satisfies the required xcconfig without real secrets

The build references a git-ignored `Secrets.xcconfig`. The workflow SHALL
synthesize a placeholder `Secrets.xcconfig` (e.g. copied from
`Secrets.example.xcconfig`) so the project resolves, and SHALL NOT require or
expose real Login-with-Amazon credentials, which are needed only at runtime.

#### Scenario: Secrets file is absent on the runner

- **WHEN** the workflow prepares to generate and build the project
- **THEN** it creates a `Secrets.xcconfig` containing placeholder values
- **AND** no real LWA client id or secret is committed, printed, or stored in the workflow

### Requirement: CI builds the app and test bundle for an iOS simulator

The workflow SHALL build the `Sponsorly` scheme for an iOS 26 simulator
destination using a toolchain that ships the iOS 26 SDK, with code signing
disabled. A compilation failure (including a strict-concurrency error) SHALL
fail the workflow.

#### Scenario: Build succeeds

- **WHEN** the sources compile cleanly under strict concurrency for the simulator
- **THEN** the build step exits successfully

#### Scenario: Build fails on a compile error

- **WHEN** a source file fails to compile (for example a strict-concurrency violation)
- **THEN** the build step exits non-zero and the workflow is marked failed

### Requirement: CI runs the unit tests

The workflow SHALL execute the `Sponsorly` scheme's test action against an iOS
26 simulator and fail when any test fails.

#### Scenario: All tests pass

- **WHEN** every XCTest in `SponsorlyTests` passes
- **THEN** the test step exits successfully

#### Scenario: A test fails

- **WHEN** any XCTest fails
- **THEN** the test step exits non-zero and the workflow is marked failed

### Requirement: CI enforces formatting and lint

The workflow SHALL run SwiftFormat in lint/verify mode (no writes) and
SwiftLint, mirroring the local pre-commit hook, and SHALL fail when code does
not match the enforced style or violates a lint rule.

#### Scenario: Code matches the enforced style

- **WHEN** all Swift sources already satisfy SwiftFormat and SwiftLint
- **THEN** the lint step exits successfully

#### Scenario: Formatting drift is present

- **WHEN** a Swift source would be rewritten by SwiftFormat, or violates a SwiftLint rule
- **THEN** the lint step exits non-zero and the workflow is marked failed

### Requirement: CI resolves and caches dependencies

The workflow SHALL resolve the `swift-amazon-ads` Swift Package dependency and
SHALL cache resolved packages and derived data between runs to keep build times
reasonable.

#### Scenario: Dependencies resolve on a clean runner

- **WHEN** the workflow runs on a runner with no prior cache
- **THEN** it resolves the `swift-amazon-ads` package successfully before building

#### Scenario: Cache reused on a subsequent run

- **WHEN** a later run finds a valid cache key
- **THEN** it restores cached packages/derived data instead of re-resolving from scratch
