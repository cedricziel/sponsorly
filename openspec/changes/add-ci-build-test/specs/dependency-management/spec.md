## ADDED Requirements

### Requirement: External dependencies are pinned to exact versions

The `swift-amazon-ads` package SHALL be referenced in `project.yml` by an exact
released tag, not by a floating branch, so that any checkout builds against a
known, immutable revision. Transitive Apple packages SHALL remain resolved to
their tagged versions.

#### Scenario: Project declares an exact version

- **WHEN** the `AmazonAds` package is read from `project.yml`
- **THEN** it specifies an exact version/tag (e.g. `1.0.0`)
- **AND** it does not specify `branch: main`

#### Scenario: Two clean checkouts resolve identically

- **WHEN** the project is generated and resolved on two separate clean machines at the same commit
- **THEN** both resolve `swift-amazon-ads` to the same revision

### Requirement: Renovate proposes updates to the pinned Swift dependency

The repository SHALL configure Renovate with a custom manager that watches the
pinned `swift-amazon-ads` version in `project.yml` and opens a pull request when
a newer GitHub tag is published, so the manual pin can be bumped through review
rather than drifting silently or going stale.

#### Scenario: Newer upstream tag exists

- **WHEN** a `swift-amazon-ads` tag newer than the pinned version is published and Renovate runs
- **THEN** Renovate opens a pull request that updates the version string in `project.yml`

#### Scenario: Already on the latest tag

- **WHEN** the pinned version already matches the newest published tag
- **THEN** Renovate opens no update pull request for that dependency

### Requirement: Renovate keeps GitHub Actions current

The repository SHALL configure Renovate's github-actions manager so that action
versions used by the CI workflow are kept up to date via automated pull
requests.

#### Scenario: An action has a newer release

- **WHEN** an action referenced in `.github/workflows/` has a newer release and Renovate runs
- **THEN** Renovate opens a pull request bumping that action's version

### Requirement: Update pull requests are validated by CI

Dependency-update pull requests SHALL be subject to the same CI workflow as any
other pull request, so a proposed bump that breaks the build, tests, or lint is
caught before merge.

#### Scenario: A bump breaks the build

- **WHEN** a Renovate pull request raises a dependency to a version that fails to compile or fails tests
- **THEN** the CI workflow on that pull request fails and the bump is not green to merge
