# lwa-authentication Specification

## Purpose
TBD - created by archiving change add-lwa-authentication. Update Purpose after archive.
## Requirements
### Requirement: Sign in with Login with Amazon

The app SHALL let the user authenticate with Amazon via the Login with Amazon (LWA) OAuth 2.0 Authorization Code grant with PKCE. The Amazon authorize page is presented in `SFSafariViewController` and the redirect is captured by an in-app loopback HTTP server bound to `127.0.0.1`. The authorization request SHALL target the region-specific authorize host and include `response_type=code`, the configured `client_id`, the scopes `profile` and `advertising::campaign_management`, the `http://localhost:<port>/callback` redirect URI, a cryptographically random `state`, and a PKCE `code_challenge` with `code_challenge_method=S256`.

#### Scenario: User completes consent

- **WHEN** the user taps "Sign in with Amazon" and approves access on the presented Amazon page
- **THEN** Amazon redirects to `http://localhost:<port>/callback`, the in-app loopback server captures the authorization code, and the app exchanges it (with the matching PKCE `code_verifier`) at the region token endpoint for an access token and refresh token, persists them, and transitions to a signed-in state

#### Scenario: User cancels the sheet

- **WHEN** the user dismisses the `SFSafariViewController` without completing sign-in
- **THEN** the app remains in the signed-out state and surfaces no error other than an optional non-blocking notice, leaving no partial credentials stored

#### Scenario: Returned state does not match

- **WHEN** the redirect callback carries a `state` value that does not match the value sent in the authorization request
- **THEN** the app SHALL reject the callback, abort the token exchange, and remain signed out

#### Scenario: Authorization is denied

- **WHEN** the redirect callback carries an OAuth `error` (e.g. the user denied consent) instead of a `code`
- **THEN** the app SHALL remain signed out and present the error description to the user

### Requirement: Secure token storage

The app SHALL persist the LWA refresh token, the current access token, and the access-token expiry in the iOS Keychain via a `TokenStorageProtocol` conformance, keyed per `AmazonRegion`. Tokens MUST NOT be written to `UserDefaults`, plist files, logs, or any non-Keychain store.

#### Scenario: Tokens survive app relaunch

- **WHEN** the user signed in during a previous launch and reopens the app
- **THEN** the stored refresh token is read from the Keychain and the app restores the signed-in state without prompting the user to sign in again

#### Scenario: Sign out clears credentials

- **WHEN** the user taps "Sign out"
- **THEN** the app SHALL delete the refresh token, access token, and expiry from the Keychain for the active region and return to the signed-out state

### Requirement: Transparent access-token refresh

The app SHALL expose a `tokenProvider` closure (consumed by `AuthenticatedTransport`) that returns a currently valid access token. When the stored access token is missing or expired, the provider SHALL obtain a new one using the `refresh_token` grant at the region token endpoint before returning, and SHALL persist the refreshed token and expiry.

#### Scenario: Valid token is reused

- **WHEN** the `tokenProvider` is invoked and the stored access token has not expired
- **THEN** it returns the stored access token without making a network request

#### Scenario: Expired token is refreshed

- **WHEN** the `tokenProvider` is invoked and the stored access token is missing or expired
- **THEN** it performs a `refresh_token` grant, persists the new access token and expiry, and returns the new access token

#### Scenario: Refresh token is rejected

- **WHEN** a refresh attempt fails with an OAuth `invalid_grant` (the refresh token is revoked or expired)
- **THEN** the `tokenProvider` SHALL throw, the app SHALL clear stored credentials, and the user SHALL be returned to the signed-out state

### Requirement: Sign-in state surfaced in Settings

The Settings screen SHALL reflect the current authentication state, showing a "Sign in with Amazon" action when signed out and a signed-in indication with a "Sign out" action when signed in.

#### Scenario: Signed-out presentation

- **WHEN** no valid credentials are stored
- **THEN** the Amazon Ads Account section shows a "Sign in with Amazon" button and no signed-in identity

#### Scenario: Signed-in presentation

- **WHEN** valid credentials are stored
- **THEN** the Amazon Ads Account section indicates the connected state and offers a "Sign out" action

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

### Requirement: Credentials supplied via build configuration

The LWA `client_id` and `client_secret` SHALL be supplied at build time through a git-ignored configuration and read at runtime from the app's Info dictionary; they MUST NOT be committed to source control. A committed template SHALL document the required keys.

#### Scenario: Credentials are absent

- **WHEN** the app is built without the LWA client id or client secret configured
- **THEN** the sign-in flow SHALL fail fast with a clear developer-facing error rather than sending an empty `client_id` to Amazon

#### Scenario: Secrets are not tracked

- **WHEN** the repository is inspected
- **THEN** the file holding the real client id and secret is git-ignored, and only a placeholder template is tracked

