import AmazonAdsCore
@testable import Sponsorly
import XCTest

/// Stub `URLProtocol` so the token endpoint can be driven without real network.
class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var requestCount = 0

    static func reset() {
        handler = nil
        requestCount = 0
    }

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requestCount += 1
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class LWAAuthServiceTests: XCTestCase {
    private let region = AmazonRegion.europe

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeConfig() -> LWAConfig {
        LWAConfig(
            clientID: "client-id",
            clientSecret: "client-secret",
            region: region,
            redirectURI: "http://localhost:8765/callback",
            callbackPort: 8765,
            scopes: ["profile", "advertising::campaign_management"]
        )
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func tokenJSON(access: String, expiresIn: Int, refresh: String?) -> Data {
        var fields = [
            "\"access_token\":\"\(access)\"",
            "\"token_type\":\"bearer\"",
            "\"expires_in\":\(expiresIn)"
        ]
        if let refresh { fields.append("\"refresh_token\":\"\(refresh)\"") }
        return Data("{\(fields.joined(separator: ","))}".utf8)
    }

    private func httpResponse(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: region.tokenEndpoint, statusCode: status,
            httpVersion: nil, headerFields: nil
        )!
    }

    // MARK: - Authorization request

    func testAuthorizationRequestCarriesPKCEAndState() async throws {
        let service = LWAAuthService(
            config: makeConfig(), storage: InMemoryTokenStorage(), urlSession: makeSession()
        )
        let request = try await service.makeAuthorizationRequest()

        let items = try XCTUnwrap(URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        XCTAssertEqual(value("client_id"), "client-id")
        XCTAssertEqual(value("response_type"), "code")
        XCTAssertEqual(value("redirect_uri"), "http://localhost:8765/callback")
        XCTAssertEqual(value("scope"), "profile advertising::campaign_management")
        XCTAssertEqual(value("code_challenge_method"), "S256")
        XCTAssertEqual(value("state"), request.state)
        XCTAssertEqual(value("code_challenge"), PKCE.codeChallenge(for: request.codeVerifier))
        // Region-correct authorize host (EU here), not the package's NA default.
        XCTAssertEqual(request.url.host, "eu.account.amazon.com")
    }

    func testRegionAuthorizeEndpoints() {
        XCTAssertEqual(AmazonRegion.northAmerica.lwaAuthorizeURL.host, "www.amazon.com")
        XCTAssertEqual(AmazonRegion.europe.lwaAuthorizeURL.host, "eu.account.amazon.com")
        XCTAssertEqual(AmazonRegion.farEast.lwaAuthorizeURL.host, "apac.account.amazon.com")
    }

    // MARK: - Token provider state machine

    func testValidStoredTokenIsReusedWithoutNetwork() async throws {
        let storage = InMemoryTokenStorage()
        try await storage.save("stored-access", for: TokenStorageKey.accessToken, region: region)
        let future = Date().addingTimeInterval(3600).timeIntervalSince1970
        try await storage.save(String(future), for: TokenStorageKey.tokenExpiry, region: region)

        let service = LWAAuthService(
            config: makeConfig(), storage: storage, urlSession: makeSession()
        )
        let token = try await service.validAccessToken()

        XCTAssertEqual(token, "stored-access")
        XCTAssertEqual(MockURLProtocol.requestCount, 0)
    }

    func testExpiredTokenTriggersRefresh() async throws {
        let storage = InMemoryTokenStorage()
        try await storage.save("old-access", for: TokenStorageKey.accessToken, region: region)
        let past = Date().addingTimeInterval(-10).timeIntervalSince1970
        try await storage.save(String(past), for: TokenStorageKey.tokenExpiry, region: region)
        try await storage.save("refresh-1", for: TokenStorageKey.refreshToken, region: region)

        MockURLProtocol.handler = { [tokenJSON, httpResponse] _ in
            (httpResponse(200), tokenJSON("new-access", 3600, "refresh-2"))
        }

        let service = LWAAuthService(
            config: makeConfig(), storage: storage, urlSession: makeSession()
        )
        let token = try await service.validAccessToken()

        XCTAssertEqual(token, "new-access")
        let stored = try await storage.retrieve(for: TokenStorageKey.accessToken, region: region)
        XCTAssertEqual(stored, "new-access")
        let storedRefresh = try await storage.retrieve(
            for: TokenStorageKey.refreshToken, region: region
        )
        XCTAssertEqual(storedRefresh, "refresh-2")
    }

    func testInvalidGrantClearsCredentialsAndSignsOut() async throws {
        let storage = InMemoryTokenStorage()
        let past = Date().addingTimeInterval(-10).timeIntervalSince1970
        try await storage.save("old-access", for: TokenStorageKey.accessToken, region: region)
        try await storage.save(String(past), for: TokenStorageKey.tokenExpiry, region: region)
        try await storage.save("refresh-bad", for: TokenStorageKey.refreshToken, region: region)

        MockURLProtocol.handler = { [httpResponse] _ in
            let body = Data(#"{"error":"invalid_grant","error_description":"expired"}"#.utf8)
            return (httpResponse(400), body)
        }

        let service = LWAAuthService(
            config: makeConfig(), storage: storage, urlSession: makeSession()
        )

        do {
            _ = try await service.validAccessToken()
            XCTFail("Expected notAuthenticated")
        } catch LWAError.notAuthenticated {
            // expected
        }
        let stillThere = await storage.exists(for: TokenStorageKey.refreshToken, region: region)
        XCTAssertFalse(stillThere)
        let authed = await service.isAuthenticated()
        XCTAssertFalse(authed)
    }

    func testFormURLEncodeEscapesReservedCharacters() {
        let encoded = LWAAuthService.formURLEncode(["a": "x+y/z=w"])
        XCTAssertEqual(encoded, "a=x%2By%2Fz%3Dw")
    }
}
