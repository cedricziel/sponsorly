# advertising-accounts Specification

## Purpose
TBD - created by archiving change add-multi-account-support. Update Purpose after archive.
## Requirements
### Requirement: Discover advertising accounts across connected regions

The app SHALL, for each connected region, fetch the advertising profiles (`GET /v2/profiles`) and manager accounts (`GET /managerAccounts`) using that region's access token, and aggregate the results into a single account model that preserves the manager-account → linked-account → profile hierarchy and tags every entry with its region. Flat profiles not under a manager account SHALL also be included.

#### Scenario: Profiles and manager accounts fetched per region

- **WHEN** the user is connected to one or more regions and the Accounts view loads
- **THEN** the app fetches profiles and manager accounts for each connected region and presents a single aggregated list of selectable advertising profiles, each annotated with its region and (when applicable) its manager account

#### Scenario: One region fails, others still shown

- **WHEN** the account fetch for one connected region fails (network or API error)
- **THEN** the app SHALL still present the accounts from the regions that succeeded and surface a non-blocking notice for the region that failed, rather than failing the whole view

#### Scenario: No profiles available

- **WHEN** a connected region returns no profiles
- **THEN** the app SHALL show an empty state for that region rather than an error

### Requirement: Select an active advertising profile

The app SHALL let the user select exactly one active advertising profile from the aggregated list, and SHALL persist the selection (its region and `profileId`) across launches. The active profile SHALL be restorable on launch.

#### Scenario: User selects a profile

- **WHEN** the user taps a profile in the Accounts list
- **THEN** that profile becomes the active profile, the selection (region + `profileId`) is persisted, and the active profile is indicated in the UI

#### Scenario: Active profile restored on launch

- **WHEN** the app relaunches and the previously active profile's region is still connected
- **THEN** the active profile is restored from persistence without requiring re-selection

#### Scenario: Active profile's region disconnected

- **WHEN** the region of the active profile is disconnected (signed out)
- **THEN** the active profile selection SHALL be cleared, and the app SHALL prompt the user to choose a new active profile

### Requirement: Provide an active-profile-scoped API client

The app SHALL expose a way to obtain an `AuthenticatedTransport` configured with the active profile's `profileId`, the `client_id`, and the token provider for the active profile's region — so that data features make requests scoped to the selected profile without re-implementing auth.

#### Scenario: Scoped client built for the active profile

- **WHEN** a data feature requests a client and an active profile is selected
- **THEN** it receives an `AuthenticatedTransport` that stamps `Authorization: Bearer`, `Amazon-Advertising-API-ClientId`, and `Amazon-Advertising-API-Scope: <active profileId>` against the active profile's region base URL

#### Scenario: No active profile selected

- **WHEN** a data feature requests a client and no active profile is selected
- **THEN** the request SHALL fail fast with a clear error indicating that an advertising profile must be selected first

