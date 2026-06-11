## Why

Every meaningful feature in Sponsorly — campaigns, reports, profile scoping — is gated on a valid Amazon Ads access token, and today the "Sign in with Amazon" button in Settings is an empty `// TODO`. Without Login with Amazon (LWA) authentication the app cannot make a single authenticated API call. This is the keystone that unblocks all downstream work.

## What Changes

- Add a real LWA OAuth 2.0 sign-in flow using the **Authorization Code grant with PKCE**, driven by `ASWebAuthenticationSession` (no loopback server, no embedded web view).
- Add a `KeychainTokenStorage` implementing the package's `TokenStorageProtocol`, persisting the refresh token, access token, and expiry in the iOS Keychain.
- Add an `LWAAuthService` that builds the authorize URL, captures the redirect, exchanges the code for tokens, transparently refreshes expired access tokens, and exposes a `tokenProvider` closure for `AuthenticatedTransport`.
- Replace the stub button in `SettingsView` with real **Sign in / Sign out** controls and a signed-in/signed-out state surface.
- Add gitignored credential plumbing: a `Secrets.xcconfig` (with a committed `Secrets.example.xcconfig` template) supplying `LWA_CLIENT_ID` / `LWA_CLIENT_SECRET`, wired through `project.yml` into the generated Info.plist, plus the `amzn-com.cedricziel.sponsorly` URL scheme for the OAuth redirect.

## Capabilities

### New Capabilities
- `lwa-authentication`: Acquiring, storing, refreshing, and revoking Amazon Ads access tokens via Login with Amazon — the sign-in flow, token lifecycle, secure storage, and the authenticated-token provider consumed by the API transport.

### Modified Capabilities
<!-- None — there are no existing specs to modify; this is the first capability. -->

## Impact

- **New code:** `Sponsorly/Features/Settings/` (or a new `Sponsorly/Auth/` folder) gains `KeychainTokenStorage`, `LWAAuthService`, and supporting auth-state types; `SettingsView.swift` is rewired.
- **Build config:** `project.yml` gains `configFiles`, an `info: properties:` block (LWA keys + `CFBundleURLTypes`); new `Secrets.xcconfig` + `Secrets.example.xcconfig`; `.gitignore` updated. Requires `xcodegen generate` after the change.
- **Dependencies:** consumes existing `swift-amazon-ads` primitives — `AmazonRegion`, `AmazonTokenResponse`, `AmazonOAuthError`, `TokenStorageProtocol`, `AuthenticatedTransport`. Adds `AuthenticationServices` (system framework).
- **External setup (operational, not code):** the LWA Security Profile must register `amzn-com.cedricziel.sponsorly://oauth` as an Allowed Return URL.
- **Security note:** the Amazon Ads token exchange requires `client_secret`; in a client-only app it ships inside the `.app` and is extractable. Accepted for now (single-user); a backend proxy is the only true mitigation and is out of scope.
- **Out of scope:** profile selection / `profileId` picker, real Campaigns/Reports API calls, multi-region selection UI, backend token proxy.
