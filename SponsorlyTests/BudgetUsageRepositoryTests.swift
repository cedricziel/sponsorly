import AmazonAdsCore
@testable import Sponsorly
import XCTest

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
