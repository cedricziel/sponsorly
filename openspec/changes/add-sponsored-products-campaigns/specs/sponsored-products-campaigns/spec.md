## ADDED Requirements

### Requirement: List Sponsored Products campaigns for the active profile

The app SHALL list the active profile's Sponsored Products campaigns via the generated `AmazonAdsSponsoredProductsAPIv3` client over the active-profile-scoped transport, following `nextToken` pagination to retrieve the full result set (up to a defined cap). Each campaign SHALL display at least its name, state, budget, and targeting type.

#### Scenario: Campaigns shown for the active profile

- **WHEN** an active profile is selected and the Campaigns tab is opened
- **THEN** the app fetches and lists that profile's Sponsored Products campaigns, each scoped by `Amazon-Advertising-API-Scope: <active profileId>`

#### Scenario: No active profile

- **WHEN** no active profile is selected
- **THEN** the Campaigns tab SHALL prompt the user to select an account (via the account switcher) instead of attempting to load campaigns

#### Scenario: Active profile changes

- **WHEN** the user switches the active profile
- **THEN** the campaigns list reloads for the newly selected profile

#### Scenario: Paginated results

- **WHEN** the campaigns response includes a `nextToken`
- **THEN** the app SHALL request subsequent pages until the token is absent or the cap is reached, presenting the combined list

#### Scenario: No campaigns

- **WHEN** the active profile has no Sponsored Products campaigns
- **THEN** the app SHALL show an empty state rather than an error

#### Scenario: Fetch fails

- **WHEN** the campaigns request fails
- **THEN** the app SHALL surface a non-blocking error with a way to retry, and SHALL NOT crash or show partial-but-unlabeled data

### Requirement: List ad groups for a campaign

The app SHALL, on a campaign detail screen, list that campaign's ad groups via `ListSponsoredProductsAdGroups` filtered by the campaign id, displaying at least each ad group's name, state, and default bid.

#### Scenario: Ad groups shown for a campaign

- **WHEN** the user opens a campaign's detail screen
- **THEN** the app fetches and lists the ad groups belonging to that campaign

#### Scenario: Campaign has no ad groups

- **WHEN** a campaign has no ad groups
- **THEN** the detail screen SHALL show an empty state rather than an error

### Requirement: Refreshable campaign data with loading feedback

The app SHALL let the user pull-to-refresh both the campaigns list and the ad-groups list. While any fetch is in progress, the app SHALL show a visible loading indicator, and SHALL keep already-loaded content visible (and the rest of the UI responsive) during a refresh.

#### Scenario: Pull to refresh campaigns

- **WHEN** the user pull-to-refreshes the campaigns list
- **THEN** the app refetches the active profile's campaigns and updates the list

#### Scenario: Pull to refresh ad groups

- **WHEN** the user pull-to-refreshes a campaign's ad-groups list
- **THEN** the app refetches that campaign's ad groups and updates the list

#### Scenario: Loading indicator on initial load

- **WHEN** a campaigns or ad-groups fetch is in progress and no data is yet shown
- **THEN** the app SHALL display a loading indicator

#### Scenario: Loading indicator on refresh keeps content

- **WHEN** a refresh is in progress while data is already shown
- **THEN** the app SHALL indicate loading without clearing the visible list
