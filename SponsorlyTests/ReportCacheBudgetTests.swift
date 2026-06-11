import AmazonAdsCore
@testable import Sponsorly
import XCTest

final class ReportCacheTests: XCTestCase {
    private let key = ReportCacheKey(
        profileId: "111", reportTypeId: "spCampaigns",
        startDate: "2026-05-12", endDate: "2026-06-10", timeUnit: "SUMMARY"
    )

    private func tempCache() -> ReportCache {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return ReportCache(directory: dir)
    }

    private func row(cost: Double) -> CampaignReportRow {
        CampaignReportRow(
            campaignId: "1", campaignName: "A", date: nil, impressions: nil,
            clicks: nil, cost: cost, sales30d: nil, purchases30d: nil
        )
    }

    func testRoundTrip() async {
        let cache = tempCache()
        await cache.save([row(cost: 5)], for: key, ttl: 60)
        let loaded = await cache.load(key)
        XCTAssertEqual(loaded?.first?.cost, 5)
    }

    func testExpiredReturnsNil() async {
        let cache = tempCache()
        await cache.save([row(cost: 5)], for: key, ttl: -1)
        let loaded = await cache.load(key)
        XCTAssertNil(loaded)
    }

    func testMissingReturnsNil() async {
        let loaded = await tempCache().load(key)
        XCTAssertNil(loaded)
    }

    func testKeyFilenameIsStable() {
        XCTAssertEqual(key.filename, "111_spCampaigns_2026-05-12_2026-06-10_SUMMARY.json")
    }
}

final class BudgetUsageRepositoryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeRepository() -> BudgetUsageRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let scoped = ScopedClient(
            transport: AuthenticatedTransport(tokenProvider: { "tok" }, clientId: "cid", profileId: "111"),
            baseURL: AmazonRegion.europe.advertisingAPIBaseURL,
            region: .europe, profileId: "111", clientID: "cid", tokenProvider: { "tok" }
        )
        return BudgetUsageRepository(scopedClient: scoped, urlSession: session)
    }

    func testSumsTodaySpend() async throws {
        let body = """
        {"success":[{"campaignId":"1","budget":100,"budgetUsagePercent":50},\
        {"campaignId":"2","budget":40,"budgetUsagePercent":25}]}
        """
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }
        // 100*0.5 + 40*0.25 = 60
        let spend = try await makeRepository().todaySpend(campaignIds: ["1", "2"])
        XCTAssertEqual(spend, 60, accuracy: 0.001)
    }

    func testEmptyCampaignsYieldsZero() async throws {
        let spend = try await makeRepository().todaySpend(campaignIds: [])
        XCTAssertEqual(spend, 0)
    }
}
