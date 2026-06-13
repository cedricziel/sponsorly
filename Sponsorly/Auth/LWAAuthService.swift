import AmazonAdsCore
import Foundation

/// A pending authorization request: the URL to present plus the `state` and PKCE
/// verifier that must be carried through to the token exchange.
struct LWAAuthorizationRequest {
    let url: URL
    let state: String
    let codeVerifier: String
}

/// Owns the Login with Amazon token lifecycle: building the authorization request,
/// exchanging the authorization code, refreshing access tokens, and signing out.
///
/// All token state mutations are serialized on this actor; concurrent refreshes are
/// coalesced into a single network call.
actor LWAAuthService {
    private let config: LWAConfig
    private let storage: any TokenStorageProtocol
    private let urlSession: URLSession

    /// Refresh slightly ahead of expiry to avoid races with in-flight requests.
    private static let expirySkew: TimeInterval = 60
    private var refreshTask: Task<String, Error>?

    init(
        config: LWAConfig,
        storage: any TokenStorageProtocol,
        urlSession: URLSession = .shared
    ) {
        self.config = config
        self.storage = storage
        self.urlSession = urlSession
    }

    // MARK: - Authorization

    /// Builds the authorize URL with PKCE + CSRF `state`.
    func makeAuthorizationRequest() throws -> LWAAuthorizationRequest {
        let verifier = PKCE.makeCodeVerifier()
        let challenge = PKCE.codeChallenge(for: verifier)
        let state = UUID().uuidString

        guard var components = URLComponents(
            url: config.region.lwaAuthorizeURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw LWAError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        guard let url = components.url else { throw LWAError.invalidResponse }
        return LWAAuthorizationRequest(url: url, state: state, codeVerifier: verifier)
    }

    /// Validates the redirect callback and exchanges the code for tokens.
    func handleCallback(url: URL, request: LWAAuthorizationRequest) async throws {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        if let error = value("error") {
            throw LWAError.authorizationDenied(value("error_description") ?? error)
        }
        guard let returnedState = value("state"), returnedState == request.state else {
            throw LWAError.stateMismatch
        }
        guard let code = value("code") else {
            throw LWAError.missingAuthorizationCode
        }

        let response = try await postToken([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": config.redirectURI,
            "client_id": config.clientID,
            "client_secret": config.clientSecret,
            "code_verifier": request.codeVerifier,
        ])
        try await persist(response)
    }

    // MARK: - Token access

    /// Whether a refresh token is currently stored.
    func isAuthenticated() async -> Bool {
        await storage.exists(for: TokenStorageKey.refreshToken, region: config.region)
    }

    /// Returns a currently valid access token, refreshing transparently when needed.
    func validAccessToken() async throws -> String {
        if let token = await storedAccessTokenIfValid() {
            return token
        }
        return try await refreshAccessToken()
    }

    /// A `Sendable` closure suitable for `AuthenticatedTransport(tokenProvider:)`.
    nonisolated func tokenProvider() -> @Sendable () async throws -> String {
        { [self] in try await validAccessToken() }
    }

    /// Clears all stored credentials for the active region.
    func signOut() async throws {
        refreshTask?.cancel()
        refreshTask = nil
        try await storage.deleteAll(for: config.region)
    }

    // MARK: - Private

    private func storedAccessTokenIfValid() async -> String? {
        guard
            let token = try? await storage.retrieve(
                for: TokenStorageKey.accessToken, region: config.region
            ),
            let expiryString = try? await storage.retrieve(
                for: TokenStorageKey.tokenExpiry, region: config.region
            ),
            let epoch = Double(expiryString)
        else {
            return nil
        }
        let expiry = Date(timeIntervalSince1970: epoch)
        guard expiry.timeIntervalSinceNow > Self.expirySkew else { return nil }
        return token
    }

    private func refreshAccessToken() async throws -> String {
        if let inFlight = refreshTask {
            return try await inFlight.value
        }
        let task = Task { try await self.performRefresh() }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func performRefresh() async throws -> String {
        guard let refreshToken = try? await storage.retrieve(
            for: TokenStorageKey.refreshToken, region: config.region
        ) else {
            throw LWAError.notAuthenticated
        }
        do {
            let response = try await postToken([
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": config.clientID,
                "client_secret": config.clientSecret,
            ])
            try await persist(response)
            return response.accessToken
        } catch let LWAError.oauth(oauthError) where oauthError.error == "invalid_grant" {
            // Refresh token revoked/expired — drop credentials and report signed-out.
            try? await storage.deleteAll(for: config.region)
            throw LWAError.notAuthenticated
        }
    }

    private func persist(_ response: AmazonTokenResponse) async throws {
        try await storage.save(
            response.accessToken, for: TokenStorageKey.accessToken, region: config.region
        )
        let expiry = response.expiryDate().timeIntervalSince1970
        try await storage.save(
            String(expiry), for: TokenStorageKey.tokenExpiry, region: config.region
        )
        // The refresh grant may omit a new refresh token; keep the existing one then.
        if let refresh = response.refreshToken {
            try await storage.save(
                refresh, for: TokenStorageKey.refreshToken, region: config.region
            )
        }
    }

    private func postToken(_ parameters: [String: String]) async throws -> AmazonTokenResponse {
        var request = URLRequest(url: config.region.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = Self.formURLEncode(parameters).data(using: .utf8)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LWAError.invalidResponse
        }
        if (200 ..< 300).contains(http.statusCode) {
            do {
                return try JSONDecoder().decode(AmazonTokenResponse.self, from: data)
            } catch {
                throw LWAError.invalidResponse
            }
        }
        if let oauthError = try? JSONDecoder().decode(AmazonOAuthError.self, from: data) {
            throw LWAError.oauth(oauthError)
        }
        throw LWAError.invalidResponse
    }

    /// RFC 3986 unreserved-only percent-encoding, safe for form bodies (tokens can
    /// contain `+`, `/`, `=` which must be escaped).
    static func formURLEncode(_ parameters: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return parameters.map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }
        .joined(separator: "&")
    }
}
