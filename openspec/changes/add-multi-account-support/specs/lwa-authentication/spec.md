## MODIFIED Requirements

### Requirement: Select the Amazon advertising region

The app SHALL let the user connect to one or more Amazon regions (North America, Europe, Far East) **independently and concurrently**. Each region maintains its own sign-in state and stored tokens; signing in or out of one region SHALL NOT affect the others. The set of connected regions SHALL persist across launches, and on launch each region's signed-in state SHALL be evaluated against the credentials stored for that region.

#### Scenario: Connect a region

- **WHEN** the user starts sign-in for a given region
- **THEN** the authorization uses that region's authorize host and token endpoint, the resulting tokens are stored under that region, and the region becomes connected without changing the state of any other region

#### Scenario: Multiple regions connected at once

- **WHEN** the user has completed sign-in for more than one region
- **THEN** all of those regions are simultaneously connected, and account discovery (see `advertising-accounts`) spans every connected region

#### Scenario: Disconnect one region

- **WHEN** the user signs out of one connected region
- **THEN** only that region's stored credentials are cleared and it becomes disconnected, while other connected regions remain signed in

#### Scenario: Connection set restored on launch

- **WHEN** the app relaunches
- **THEN** each region that has stored credentials is restored as connected, and regions without stored credentials are shown as disconnected
