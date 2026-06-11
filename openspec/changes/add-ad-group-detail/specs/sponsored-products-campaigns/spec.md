## ADDED Requirements

### Requirement: Inspect an ad group's product ads and targeting

The app SHALL provide an ad-group detail screen, reachable from an ad-group row, that lists the ad group's product ads (`POST /sp/productAds/list`), keywords (`POST /sp/keywords/list`), and targeting clauses (`POST /sp/targets/list`) for the active profile, each filtered by the ad group's id and scoped by `Amazon-Advertising-API-Scope: <active profileId>`. Results SHALL follow `nextToken` pagination up to the defined cap.

#### Scenario: Open an ad group

- **WHEN** the user taps an ad group in a campaign's detail
- **THEN** the app opens the ad-group detail screen and fetches that ad group's product ads, keywords, and targeting clauses

#### Scenario: Sections reflect what the ad group has

- **WHEN** the ad-group detail loads and the ad group has keywords but no product targets (or vice versa)
- **THEN** the app SHALL show only the non-empty sections (product ads, and whichever of keywords / targeting clauses are present) rather than empty placeholders for the absent kind

#### Scenario: Ad group with no contents

- **WHEN** an ad group returns no product ads, keywords, or targeting clauses
- **THEN** the app SHALL show an empty state rather than an error

#### Scenario: Fetch fails

- **WHEN** loading the ad-group detail fails
- **THEN** the app SHALL surface a non-blocking error with a way to retry, and SHALL NOT crash

#### Scenario: Refresh and loading feedback

- **WHEN** the ad-group detail is loading or the user pull-to-refreshes it
- **THEN** the app SHALL show a loading indicator (keeping any already-shown content visible during a refresh) and update the lists when the fetch completes
