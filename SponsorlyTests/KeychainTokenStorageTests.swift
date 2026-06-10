import AmazonAdsCore
@testable import Sponsorly
import XCTest

final class KeychainTokenStorageTests: XCTestCase {
    private let region = AmazonRegion.europe
    private var storage: KeychainTokenStorage!

    override func setUp() async throws {
        try await super.setUp()
        // Unique service per run so tests don't collide with app data or each other.
        storage = KeychainTokenStorage(service: "com.cedricziel.sponsorly.tests.\(UUID().uuidString)")
        try await skipIfKeychainUnavailable()
    }

    override func tearDown() async throws {
        try? await storage.deleteAll(for: region)
        storage = nil
        try await super.tearDown()
    }

    /// Simulator unit-test hosts occasionally lack keychain entitlements; skip cleanly.
    private func skipIfKeychainUnavailable() async throws {
        do {
            try await storage.save("probe", for: TokenStorageKey.accessToken, region: region)
            try await storage.delete(for: TokenStorageKey.accessToken, region: region)
        } catch {
            throw XCTSkip("Keychain not available in this test host: \(error)")
        }
    }

    func testSaveAndRetrieveRoundTrip() async throws {
        try await storage.save("token-abc", for: TokenStorageKey.refreshToken, region: region)
        let value = try await storage.retrieve(for: TokenStorageKey.refreshToken, region: region)
        XCTAssertEqual(value, "token-abc")
    }

    func testOverwriteUpdatesValue() async throws {
        try await storage.save("first", for: TokenStorageKey.accessToken, region: region)
        try await storage.save("second", for: TokenStorageKey.accessToken, region: region)
        let value = try await storage.retrieve(for: TokenStorageKey.accessToken, region: region)
        XCTAssertEqual(value, "second")
    }

    func testExistsReflectsPresence() async throws {
        let before = await storage.exists(for: TokenStorageKey.accessToken, region: region)
        XCTAssertFalse(before)
        try await storage.save("x", for: TokenStorageKey.accessToken, region: region)
        let after = await storage.exists(for: TokenStorageKey.accessToken, region: region)
        XCTAssertTrue(after)
    }

    func testRetrieveMissingThrowsNotFound() async {
        do {
            _ = try await storage.retrieve(for: TokenStorageKey.profileId, region: region)
            XCTFail("Expected notFound")
        } catch TokenStorageError.notFound {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDeleteAllRemovesEverythingForRegion() async throws {
        try await storage.save("a", for: TokenStorageKey.accessToken, region: region)
        try await storage.save("r", for: TokenStorageKey.refreshToken, region: region)
        try await storage.deleteAll(for: region)
        let access = await storage.exists(for: TokenStorageKey.accessToken, region: region)
        let refresh = await storage.exists(for: TokenStorageKey.refreshToken, region: region)
        XCTAssertFalse(access)
        XCTAssertFalse(refresh)
    }

    func testDeleteMissingKeyDoesNotThrow() async throws {
        try await storage.delete(for: TokenStorageKey.accessToken, region: region)
    }
}
