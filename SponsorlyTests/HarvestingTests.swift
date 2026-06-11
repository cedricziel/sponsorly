import AmazonAdsCore
@testable import Sponsorly
import XCTest

final class HarvestScorerTests: XCTestCase {
    private func term(_ name: String, clicks: Int, orders: Int, spend: Double, sales: Double) -> SearchTerm {
        SearchTerm(
            term: name, campaignId: "c", adGroupId: "ag",
            clicks: clicks, spend: spend, sales: sales, orders: orders
        )
    }

    func testGraduateMatchesWinners() {
        let terms = [
            term("win", clicks: 20, orders: 3, spend: 10, sales: 50), // ACOS 20% ✓
            term("toofewOrders", clicks: 20, orders: 1, spend: 5, sales: 30),
            term("toofewClicks", clicks: 3, orders: 3, spend: 5, sales: 40),
            term("inefficient", clicks: 20, orders: 3, spend: 40, sales: 50), // ACOS 80% ✗
        ]
        let graduates = HarvestScorer.graduate(terms, HarvestCriteria())
        XCTAssertEqual(graduates.map(\.term), ["win"])
    }

    func testNegateMatchesWasteful() {
        let terms = [
            term("waste", clicks: 14, orders: 0, spend: 8, sales: 0), // ✓
            term("converted", clicks: 14, orders: 1, spend: 8, sales: 20),
            term("fewClicks", clicks: 3, orders: 0, spend: 1, sales: 0),
        ]
        let negates = HarvestScorer.negate(terms, HarvestCriteria())
        XCTAssertEqual(negates.map(\.term), ["waste"])
    }

    func testCriteriaTuningRebuckets() {
        let terms = [term("edge", clicks: 5, orders: 2, spend: 5, sales: 30)]
        XCTAssertTrue(HarvestScorer.graduate(terms, HarvestCriteria()).isEmpty) // min clicks 10
        var loose = HarvestCriteria()
        loose.minClicks = 5
        XCTAssertEqual(HarvestScorer.graduate(terms, loose).map(\.term), ["edge"])
    }

    func testDecodesNumericIds() throws {
        // The reporting API returns campaign/ad-group ids as numbers, not strings.
        let json = Data("""
        [{"searchTerm":"b00x","campaignId":60720048974149,"adGroupId":232987426622069,\
        "clicks":4,"cost":2.61,"sales30d":0,"purchases30d":0}]
        """.utf8)
        let rows = try JSONDecoder().decode([SearchTermReportRow].self, from: json)
        XCTAssertEqual(rows.first?.campaignId, "60720048974149")
        XCTAssertEqual(rows.first?.adGroupId, "232987426622069")
        XCTAssertEqual(rows.first?.cost, 2.61)
    }

    func testSearchTermsDropIncompleteRows() {
        let rows = [
            SearchTermReportRow(
                searchTerm: "ok", campaignId: "c", adGroupId: "a",
                clicks: 1, cost: 1, sales30d: 0, purchases30d: 0
            ),
            SearchTermReportRow(
                searchTerm: nil, campaignId: "c", adGroupId: "a",
                clicks: 1, cost: 1, sales30d: 0, purchases30d: 0
            ),
        ]
        XCTAssertEqual(HarvestScorer.searchTerms(from: rows).map(\.term), ["ok"])
    }
}

final class HarvestViewModelLogicTests: XCTestCase {
    private func term(_ name: String) -> SearchTerm {
        SearchTerm(term: name, campaignId: "c", adGroupId: "ag", clicks: 1, spend: 1, sales: 1, orders: 1)
    }

    func testGraduatedTermsAreAlsoNegated() {
        let result = HarvestViewModel.negateTargets(
            graduating: [term("a"), term("b")], negateSelected: [term("c")]
        )
        XCTAssertEqual(Set(result.map(\.term)), ["a", "b", "c"])
    }

    func testOutcomesMapAndSort() {
        let outcomes = HarvestViewModel.outcomes(["y": .succeeded, "x": .alreadyExists], kind: .keyword)
        XCTAssertEqual(outcomes.map(\.term), ["x", "y"]) // sorted
        XCTAssertTrue(outcomes.allSatisfy { $0.kind == .keyword })
    }
}

final class KeywordWriteRepositoryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeRepository() -> KeywordWriteRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let scoped = ScopedClient(
            transport: AuthenticatedTransport(tokenProvider: { "tok" }, clientId: "cid", profileId: "111"),
            baseURL: AmazonRegion.europe.advertisingAPIBaseURL,
            region: .europe, profileId: "111", clientID: "cid", tokenProvider: { "tok" }
        )
        return KeywordWriteRepository(scopedClient: scoped, urlSession: session)
    }

    func testMixedOutcomes() async throws {
        let body = """
        {"keywords":{"success":[{"index":0}],
        "error":[{"index":1,"errors":[{"errorType":"DUPLICATE_VALUE"}]},
        {"index":2,"errors":[{"errorType":"INVALID_ARGUMENT"}]}]}}
        """
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }
        let statuses = try await makeRepository().createExactKeywords(
            campaignId: "c", adGroupId: "a", terms: ["new", "dup", "bad"], bid: 0.5
        )
        XCTAssertEqual(statuses["new"], .succeeded)
        XCTAssertEqual(statuses["dup"], .alreadyExists)
        if case .failed = statuses["bad"] {} else { XCTFail("expected failed for bad") }
    }

    func testNegativeWriteParsesNegativeKey() async throws {
        let body = #"{"negativeKeywords":{"success":[{"index":0}]}}"#
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }
        let statuses = try await makeRepository().createNegativeExact(
            campaignId: "c", adGroupId: "a", terms: ["term"]
        )
        XCTAssertEqual(statuses["term"], .succeeded)
    }
}
