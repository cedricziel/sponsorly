import AmazonAdsCore
@testable import Sponsorly
import XCTest

final class AdvertisingAccountAggregatorTests: XCTestCase {
    private func profile(_ id: String, name: String) -> AmazonProfile {
        AmazonProfile(
            profileId: id, countryCode: "DE", currencyCode: "EUR", timezone: "Europe/Berlin",
            accountInfo: AmazonAccountInfo(id: "a\(id)", type: "seller", name: name)
        )
    }

    private func manager(_ name: String, linked: [(String, String)]) -> AmazonManagerAccount {
        AmazonManagerAccount(
            managerAccountId: "m", managerAccountName: name,
            linkedAccounts: linked.map {
                AmazonLinkedAccount(profileId: $0.0, accountId: "acc", accountName: $0.1, marketplaceId: "MP")
            }
        )
    }

    func testFlattensStandaloneAndLinkedProfiles() {
        let result = AdvertisingAccountAggregator.profiles(
            profiles: [profile("1", name: "Alpha")],
            managerAccounts: [manager("Agency", linked: [("2", "Beta")])],
            region: .europe
        )
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(Set(result.map(\.profileId)), ["1", "2"])
        let beta = result.first { $0.profileId == "2" }
        XCTAssertEqual(beta?.managerAccountName, "Agency")
    }

    func testDedupesByIdPreferringManagerInfo() {
        // Same profileId appears standalone and under a manager account.
        let result = AdvertisingAccountAggregator.profiles(
            profiles: [profile("1", name: "Alpha")],
            managerAccounts: [manager("Agency", linked: [("1", "Alpha")])],
            region: .europe
        )
        XCTAssertEqual(result.count, 1)
        let merged = result[0]
        XCTAssertEqual(merged.managerAccountName, "Agency") // from manager
        XCTAssertEqual(merged.countryCode, "DE") // retained from standalone
    }

    func testSortedByName() {
        let result = AdvertisingAccountAggregator.profiles(
            profiles: [profile("1", name: "Zed"), profile("2", name: "Apple")],
            managerAccounts: [], region: .europe
        )
        XCTAssertEqual(result.map(\.accountName), ["Apple", "Zed"])
    }
}

final class ActiveProfileStoreTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "AccountsTests-\(UUID().uuidString)")
    }

    func testRoundTrip() {
        let selection = ActiveProfileSelection(region: .europe, profileId: "12345")
        ActiveProfileStore.save(selection, into: defaults)
        XCTAssertEqual(ActiveProfileStore.load(defaults), selection)
    }

    func testSaveNilClears() {
        ActiveProfileStore.save(.init(region: .farEast, profileId: "9"), into: defaults)
        ActiveProfileStore.save(nil, into: defaults)
        XCTAssertNil(ActiveProfileStore.load(defaults))
    }
}

final class ScopedClientFactoryTests: XCTestCase {
    func testThrowsWhenNoActiveProfile() {
        XCTAssertThrowsError(
            try ActiveProfileClientFactory.make(
                selection: nil, clientID: "cid", tokenProvider: { _ in { "tok" } }
            )
        ) { error in
            XCTAssertTrue(error is ScopedClientError)
        }
    }

    func testBuildsScopedClientForSelection() throws {
        let selection = ActiveProfileSelection(region: .europe, profileId: "777")
        let client = try ActiveProfileClientFactory.make(
            selection: selection, clientID: "cid", tokenProvider: { _ in { "tok" } }
        )
        XCTAssertEqual(client.profileId, "777")
        XCTAssertEqual(client.region, .europe)
        XCTAssertEqual(client.baseURL, AmazonRegion.europe.advertisingAPIBaseURL)
    }
}

final class AccountsRepositoryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeRepository() -> AccountsRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return AccountsRepository(clientID: "cid", urlSession: URLSession(configuration: configuration))
    }

    private func response(_ url: URL, _ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    private let profilesJSON = Data("""
    [{"profileId":"111","countryCode":"DE","currencyCode":"EUR","timezone":"Europe/Berlin",\
    "accountInfo":{"id":"a1","type":"seller","name":"My Store"}}]
    """.utf8)

    func testDiscoverSuccess() async {
        MockURLProtocol.handler = { [profilesJSON, response] request in
            let url = request.url!
            if url.path.hasSuffix("/v2/profiles") { return (response(url, 200), profilesJSON) }
            return (response(url, 404), Data()) // no manager accounts
        }
        let accounts = await makeRepository().discover([.europe: { "tok" }])
        XCTAssertEqual(accounts.profiles.count, 1)
        XCTAssertEqual(accounts.profiles.first?.accountName, "My Store")
        XCTAssertTrue(accounts.failures.isEmpty)
    }

    func testPartialFailureIsolatesRegions() async {
        MockURLProtocol.handler = { [profilesJSON, response] request in
            let url = request.url!
            // EU advertising host fails; NA succeeds.
            if url.host?.contains("-eu") == true {
                return (response(url, 500), Data())
            }
            if url.path.hasSuffix("/v2/profiles") { return (response(url, 200), profilesJSON) }
            return (response(url, 404), Data())
        }
        let accounts = await makeRepository().discover([
            .northAmerica: { "tok" },
            .europe: { "tok" }
        ])
        XCTAssertEqual(accounts.profiles.count, 1) // only NA
        XCTAssertNotNil(accounts.failures[.europe])
    }

    func testEmptyRegionYieldsNoProfilesNoFailure() async {
        MockURLProtocol.handler = { [response] request in
            let url = request.url!
            if url.path.hasSuffix("/v2/profiles") { return (response(url, 200), Data("[]".utf8)) }
            return (response(url, 404), Data())
        }
        let accounts = await makeRepository().discover([.europe: { "tok" }])
        XCTAssertTrue(accounts.profiles.isEmpty)
        XCTAssertTrue(accounts.failures.isEmpty)
    }
}
