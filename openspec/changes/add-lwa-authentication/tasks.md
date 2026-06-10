## 1. Credentials & build configuration

- [x] 1.1 Create `Secrets.example.xcconfig` (committed) documenting `LWA_CLIENT_ID` and `LWA_CLIENT_SECRET` with placeholder values
- [x] 1.2 Create `Secrets.xcconfig` (real values, never committed) and add `Secrets.xcconfig` to `.gitignore`
- [x] 1.3 In `project.yml`, add `configFiles` for the `Sponsorly` target mapping Debug and Release to `Secrets.xcconfig`
- [x] 1.4 In `project.yml`, add an `info: properties:` block exposing `LWAClientID = $(LWA_CLIENT_ID)` and `LWAClientSecret = $(LWA_CLIENT_SECRET)` (also switched to an XcodeGen-managed Info.plist with `GENERATE_INFOPLIST_FILE: NO`, since arbitrary keys can't be injected with the synthesized plist)
- [x] 1.5 In `project.yml`, add `CFBundleURLTypes` with `CFBundleURLSchemes: [amzn-com.cedricziel.sponsorly]`
- [x] 1.6 Run `xcodegen generate` and confirm the generated Info.plist contains the keys and URL scheme
- [ ] 1.7 Register `amzn-com.cedricziel.sponsorly://oauth` as an Allowed Return URL in the LWA Security Profile — **USER ACTION** (done on developer.amazon.com, not in code; documented in proposal/design)

## 2. Configuration accessor

- [x] 2.1 Add an `LWAConfig` (or similar) that reads `LWAClientID` / `LWAClientSecret` from `Bundle.main` and the default `AmazonRegion`
- [x] 2.2 Fail fast with a clear developer-facing error when either credential is missing or empty

## 3. Keychain token storage

- [x] 3.1 Add `KeychainTokenStorage` conforming to `TokenStorageProtocol`, backed by Keychain Services (`SecItem*`), `Sendable`
- [x] 3.2 Implement save/retrieve/exists/delete/deleteAll keyed per `AmazonRegion` using the package's storage key constants
- [x] 3.3 Choose a Keychain accessibility attribute (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) and treat read failures as "no token" rather than crashing
- [x] 3.4 Add unit tests for round-trip save/retrieve, overwrite, delete, and missing-key behavior

## 4. PKCE & authorize URL

- [x] 4.1 Add PKCE helpers: random `code_verifier` and S256 `code_challenge`
- [x] 4.2 Build the authorize URL from `region.authorizationURL` with `client_id`, `scope` (`profile advertising::campaign_management`), `response_type=code`, `redirect_uri`, random `state`, `code_challenge`, `code_challenge_method=S256`
- [x] 4.3 Add unit tests for PKCE generation and authorize-URL query construction

## 5. LWAAuthService (token lifecycle)

- [x] 5.1 Add `LWAAuthService` as an `actor` holding config + `KeychainTokenStorage`
- [x] 5.2 Implement the `authorization_code` exchange: POST `region.tokenEndpoint` with `code`, `code_verifier`, `redirect_uri`, `client_id`, `client_secret`; decode `AmazonTokenResponse`; persist tokens + expiry
- [x] 5.3 Implement the `refresh_token` grant and persist the refreshed access token + expiry
- [x] 5.4 Implement `tokenProvider` `@Sendable () async throws -> String`: return a valid token, refresh on expiry, coalesce concurrent refreshes inside the actor
- [x] 5.5 On `invalid_grant` during refresh, clear stored credentials and surface a signed-out result
- [x] 5.6 Implement `signOut()` clearing all stored credentials, and an `isAuthenticated` / auth-state read
- [x] 5.7 Decode `AmazonOAuthError` and map OAuth error responses to typed Swift errors
- [x] 5.8 Add unit tests for the token-provider state machine (valid / expired-refresh / invalid_grant) using `InMemoryTokenStorage` and a mocked URL protocol

## 6. ASWebAuthenticationSession sign-in

- [x] 6.1 Add a `@MainActor` presenter conforming to `ASWebAuthenticationPresentationContextProviding`
- [x] 6.2 Implement `signIn()`: present `ASWebAuthenticationSession` with `callbackURLScheme: "amzn-com.cedricziel.sponsorly"`, parse the redirect for `code`/`state`/`error`
- [x] 6.3 Verify returned `state` matches the sent value; reject mismatches and abort the exchange
- [x] 6.4 Handle user cancellation as a benign signed-out outcome (no stored partial credentials)
- [x] 6.5 Handle OAuth `error` callbacks by surfacing the error description

## 7. Settings UI

- [x] 7.1 Add an `@MainActor` `@Observable` auth view model exposing signed-in/out state and sign-in/out actions
- [x] 7.2 Replace the stub button in `SettingsView` with "Sign in with Amazon" (signed out) and a connected indication + "Sign out" (signed in), per Apple HIG
- [x] 7.3 Restore signed-in state on launch by reading the stored refresh token
- [x] 7.4 Surface sign-in errors non-blockingly (alert bound to `errorMessage`)
- [x] 7.5 Update/refresh `#Preview` to cover signed-in and signed-out states

## 8. Wire-up & verification

- [x] 8.1 Run `xcodegen generate` after adding the new Swift files
- [x] 8.2 Build for the simulator: `xcodebuild -scheme Sponsorly -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` → **BUILD SUCCEEDED**
- [x] 8.3 Run tests: `xcodebuild ... test` → **16/16 passed**
- [x] 8.4 Lint & format — no `Makefile`/lint config exists in the project; ran `swiftformat` (`--commas inline --swiftversion 5.10`) and `swiftlint` directly → **lint clean**. (Follow-up: add `.swiftformat` / `.swiftlint.yml` + a `Makefile` so `make lint`/`make format` work.)
- [ ] 8.5 Launch the app and complete a real LWA sign-in end to end — **USER ACTION** (needs the real `LWA_CLIENT_SECRET` in `Secrets.xcconfig`, the return URL registered per 1.7, and human consent in the browser sheet)
- [ ] 8.6 Confirm tokens persist across relaunch and that "Sign out" clears them — **USER ACTION** (follows 8.5)
- [ ] 8.7 Commit as semantic commits (e.g. `chore:` build config, `feat:` auth service + UI), one logical change per commit — pending your go-ahead
