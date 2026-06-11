import AmazonAdsCore
@testable import Sponsorly
import XCTest

final class CampaignDecodingTests: XCTestCase {
    func testDecodesCampaignsEnvelope() throws {
        let json = Data("""
        {"campaigns":[
          {"campaignId":"111","name":"Brand — Auto","state":"ENABLED",
           "targetingType":"AUTO","budget":{"budget":25.5,"budgetType":"DAILY"}}
        ],"nextToken":"abc"}
        """.utf8)
        let response = try JSONDecoder().decode(CampaignListResponse.self, from: json)
        XCTAssertEqual(response.nextToken, "abc")
        let campaign = try XCTUnwrap(response.campaigns?.first)
        XCTAssertEqual(campaign.campaignId, "111")
        XCTAssertEqual(campaign.name, "Brand — Auto")
        XCTAssertEqual(campaign.state, "ENABLED")
        XCTAssertEqual(campaign.budget?.budget, 25.5)
    }

    func testDecodesAdGroupsEnvelope() throws {
        let json = Data("""
        {"adGroups":[{"adGroupId":"9","name":"Exact","state":"PAUSED","defaultBid":0.75}]}
        """.utf8)
        let response = try JSONDecoder().decode(AdGroupListResponse.self, from: json)
        XCTAssertNil(response.nextToken)
        XCTAssertEqual(response.adGroups?.first?.defaultBid, 0.75)
    }
}

final class CampaignsRepositoryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeRepository() -> CampaignsRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let scoped = ScopedClient(
            transport: AuthenticatedTransport(tokenProvider: { "tok" }, clientId: "cid", profileId: "111"),
            baseURL: AmazonRegion.europe.advertisingAPIBaseURL,
            region: .europe, profileId: "111", clientID: "cid", tokenProvider: { "tok" }
        )
        return CampaignsRepository(scopedClient: scoped, urlSession: session)
    }

    private func response(_ url: URL, _ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    func testListCampaignsSinglePage() async throws {
        MockURLProtocol.handler = { [response] request in
            let body = Data(#"{"campaigns":[{"campaignId":"1","name":"A","state":"ENABLED"}]}"#.utf8)
            return (response(request.url!, 200), body)
        }
        let result = try await makeRepository().listCampaigns()
        XCTAssertEqual(result.campaigns.map(\.campaignId), ["1"])
        XCTAssertFalse(result.truncated)
    }

    func testListCampaignsFollowsNextToken() async throws {
        MockURLProtocol.handler = { [response] request in
            let page1 = #"{"campaigns":[{"campaignId":"1","name":"A","state":"ENABLED"}],"nextToken":"t"}"#
            let page2 = #"{"campaigns":[{"campaignId":"2","name":"B","state":"PAUSED"}]}"#
            let body = MockURLProtocol.requestCount == 1 ? page1 : page2
            return (response(request.url!, 200), Data(body.utf8))
        }
        let result = try await makeRepository().listCampaigns()
        XCTAssertEqual(result.campaigns.map(\.campaignId), ["1", "2"])
        XCTAssertEqual(MockURLProtocol.requestCount, 2)
    }

    func testListCampaignsEmpty() async throws {
        MockURLProtocol.handler = { [response] request in
            (response(request.url!, 200), Data(#"{"campaigns":[]}"#.utf8))
        }
        let result = try await makeRepository().listCampaigns()
        XCTAssertTrue(result.campaigns.isEmpty)
    }

    func testListCampaignsHTTPErrorThrows() async {
        MockURLProtocol.handler = { [response] request in
            (response(request.url!, 500), Data())
        }
        do {
            _ = try await makeRepository().listCampaigns()
            XCTFail("Expected error")
        } catch let CampaignsError.http(status) {
            XCTAssertEqual(status, 500)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testListAdGroupsForCampaign() async throws {
        let body = #"{"adGroups":[{"adGroupId":"9","name":"AG","state":"ENABLED","defaultBid":0.5}]}"#
        MockURLProtocol.handler = { [response] request in
            (response(request.url!, 200), Data(body.utf8))
        }
        let result = try await makeRepository().listAdGroups(campaignId: "1")
        XCTAssertEqual(result.adGroups.map(\.adGroupId), ["9"])
    }
}
