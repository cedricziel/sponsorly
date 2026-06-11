import AmazonAdsCore
@testable import Sponsorly
import XCTest

/// gzip of: [{"campaignId":"1","campaignName":"Brand","cost":5.5,"sales30d":20.0,"impressions":100,"clicks":4}]
private enum ReportFixture {
    static let campaignGzip = Data(base64Encoded:
        "H4sIAHkMK2oAA4uuVkpOzC1IzEzP80xRslIyVNKBC/gl5qYChZyKEvNSQML5xSVKVqZ6pjpKxYk5qcXGBkA"
            + "NRgZ6BjpKmbkFRanFxZn5ecVKVoYGQJHknMzkbCDHpDYWAOglS9xjAAAA")!
}

final class ReportGunzipTests: XCTestCase {
    func testDecompressesGzip() throws {
        let json = try XCTUnwrap(ReportGunzip.decompress(ReportFixture.campaignGzip))
        let rows = try JSONDecoder().decode([CampaignReportRow].self, from: json)
        XCTAssertEqual(rows.first?.campaignId, "1")
        XCTAssertEqual(rows.first?.cost, 5.5)
        XCTAssertEqual(rows.first?.sales30d, 20.0)
    }

    func testPlainJSONPassesThrough() throws {
        let plain = Data(#"[{"campaignId":"9","cost":1.0}]"#.utf8)
        let result = try XCTUnwrap(ReportGunzip.decompress(plain))
        XCTAssertEqual(result, plain)
    }

    func testPollBackoffIsCapped() {
        XCTAssertEqual(ReportingRepository.pollDelayNanos(0), 2_000_000_000)
        XCTAssertEqual(ReportingRepository.pollDelayNanos(10), 15_000_000_000) // capped
    }
}

final class ReportingRepositoryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeRepository() -> ReportingRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let scoped = ScopedClient(
            transport: AuthenticatedTransport(tokenProvider: { "tok" }, clientId: "cid", profileId: "111"),
            baseURL: AmazonRegion.europe.advertisingAPIBaseURL,
            region: .europe, profileId: "111", clientID: "cid", tokenProvider: { "tok" }
        )
        return ReportingRepository(scopedClient: scoped, urlSession: session)
    }

    private func response(_ url: URL, _ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    func testFullLifecycleHappyPath() async throws {
        let gzip = ReportFixture.campaignGzip
        MockURLProtocol.handler = { [response] request in
            let url = request.url!
            if request.httpMethod == "POST", url.path.hasSuffix("/reporting/reports") {
                return (response(url, 200), Data(#"{"reportId":"r1","status":"PENDING"}"#.utf8))
            }
            if url.path.hasSuffix("/reporting/reports/r1") {
                let body = #"{"reportId":"r1","status":"COMPLETED","url":"https://s3.example.com/r.gz"}"#
                return (response(url, 200), Data(body.utf8))
            }
            // download
            return (response(url, 200), gzip)
        }

        let request = ReportRequest.spCampaigns(
            name: "t", startDate: "2026-05-12", endDate: "2026-06-10",
            timeUnit: "SUMMARY", columns: CampaignReportRow.summaryColumns
        )
        let rows = try await makeRepository().fetchCampaignRows(request)
        XCTAssertEqual(rows.first?.campaignId, "1")
        XCTAssertEqual(rows.first?.cost, 5.5)
    }

    func testFailedReportThrows() async {
        MockURLProtocol.handler = { [response] request in
            let url = request.url!
            if request.httpMethod == "POST" {
                return (response(url, 200), Data(#"{"reportId":"r1","status":"PENDING"}"#.utf8))
            }
            let body = #"{"reportId":"r1","status":"FAILED","failureReason":"bad columns"}"#
            return (response(url, 200), Data(body.utf8))
        }
        do {
            _ = try await makeRepository().pollUntilReady("r1")
            XCTFail("Expected failure")
        } catch let ReportError.generationFailed(reason) {
            XCTAssertEqual(reason, "bad columns")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
