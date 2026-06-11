import AmazonAdsCore
@testable import Sponsorly
import XCTest

final class AdGroupContentsDecodingTests: XCTestCase {
    func testDecodesProductAds() throws {
        let json = Data("""
        {"productAds":[{"adId":"1","asin":"B0ABCD1234","sku":"SKU-9","state":"ENABLED"}],"nextToken":"n"}
        """.utf8)
        let response = try JSONDecoder().decode(ProductAdListResponse.self, from: json)
        XCTAssertEqual(response.nextToken, "n")
        XCTAssertEqual(response.productAds?.first?.asin, "B0ABCD1234")
    }

    func testDecodesKeywords() throws {
        let json = Data("""
        {"keywords":[{"keywordId":"1","keywordText":"shoes","matchType":"EXACT","state":"ENABLED","bid":0.85}]}
        """.utf8)
        let response = try JSONDecoder().decode(KeywordListResponse.self, from: json)
        XCTAssertEqual(response.keywords?.first?.keywordText, "shoes")
        XCTAssertEqual(response.keywords?.first?.bid, 0.85)
    }

    func testTargetingClauseExpressionDisplay() throws {
        let json = Data("""
        {"targetingClauses":[{"targetId":"1","state":"ENABLED",
        "expression":[{"type":"ASIN_CATEGORY_SAME_AS","value":"Shoes"}]}]}
        """.utf8)
        let response = try JSONDecoder().decode(TargetingClauseListResponse.self, from: json)
        XCTAssertEqual(response.targetingClauses?.first?.displayExpression, "Shoes")
    }

    func testTargetingClauseExpressionFallsBackToType() {
        let clause = TargetingClause(
            targetId: "1", state: "ENABLED", bid: nil,
            expression: [.init(type: "QUERY_BROAD_REL_MATCHES", value: nil)]
        )
        XCTAssertEqual(clause.displayExpression, "Query Broad Rel Matches")
    }
}

final class AdGroupContentsRepositoryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeRepository() -> AdGroupContentsRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let scoped = ScopedClient(
            transport: AuthenticatedTransport(tokenProvider: { "tok" }, clientId: "cid", profileId: "111"),
            baseURL: AmazonRegion.europe.advertisingAPIBaseURL,
            region: .europe, profileId: "111", clientID: "cid", tokenProvider: { "tok" }
        )
        return AdGroupContentsRepository(scopedClient: scoped, urlSession: session)
    }

    private func response(_ url: URL, _ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    func testListProductAds() async throws {
        let body = #"{"productAds":[{"adId":"1","asin":"B0X","state":"ENABLED"}]}"#
        MockURLProtocol.handler = { [response] request in
            (response(request.url!, 200), Data(body.utf8))
        }
        let ads = try await makeRepository().listProductAds(adGroupId: "9")
        XCTAssertEqual(ads.map(\.adId), ["1"])
    }

    func testListKeywordsHTTPErrorThrows() async {
        MockURLProtocol.handler = { [response] request in
            (response(request.url!, 500), Data())
        }
        do {
            _ = try await makeRepository().listKeywords(adGroupId: "9")
            XCTFail("Expected error")
        } catch let CampaignsError.http(status) {
            XCTAssertEqual(status, 500)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testListTargetingClausesEmpty() async throws {
        MockURLProtocol.handler = { [response] request in
            (response(request.url!, 200), Data(#"{"targetingClauses":[]}"#.utf8))
        }
        let targets = try await makeRepository().listTargetingClauses(adGroupId: "9")
        XCTAssertTrue(targets.isEmpty)
    }
}

@MainActor
final class AdGroupDetailViewModelTests: XCTestCase {
    func testAllFailSetsError() {
        let model = AdGroupDetailViewModel()
        model.apply(productAds: nil, keywords: nil, targetingClauses: nil)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.isEmpty)
    }

    func testPartialFailureNoError() {
        let model = AdGroupDetailViewModel()
        model.apply(
            productAds: [ProductAd(adId: "1", asin: "B0X", sku: nil, state: "ENABLED")],
            keywords: nil,
            targetingClauses: nil
        )
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.productAds.count, 1)
        XCTAssertTrue(model.keywords.isEmpty)
    }
}
