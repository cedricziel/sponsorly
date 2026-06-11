@testable import Sponsorly
import XCTest

final class SpendOverviewAggregationTests: XCTestCase {
    private func row(
        _ id: String, name: String? = nil, date: String? = nil,
        cost: Double? = nil, sales: Double? = nil
    ) -> CampaignReportRow {
        CampaignReportRow(
            campaignId: id, campaignName: name, date: date, impressions: nil,
            clicks: nil, cost: cost, sales30d: sales, purchases30d: nil
        )
    }

    func testHeadlineSums() {
        let metrics = SpendOverviewViewModel.aggregateHeadline([
            row("1", cost: 10, sales: 40),
            row("2", cost: 5, sales: 10),
        ])
        XCTAssertEqual(metrics.spend, 15)
        XCTAssertEqual(metrics.sales, 50)
        XCTAssertEqual(metrics.acos ?? 0, 0.3, accuracy: 0.0001) // 15/50
    }

    func testAcosNilWhenNoSales() {
        var metrics = SpendMetrics()
        metrics.spend = 10
        XCTAssertNil(metrics.acos)
    }

    func testTopCampaignsSortedAndLimited() {
        let top = SpendOverviewViewModel.topCampaigns([
            row("1", name: "Low", cost: 5),
            row("2", name: "High", cost: 50),
            row("3", name: "Mid", cost: 20),
        ], limit: 2)
        XCTAssertEqual(top.map(\.name), ["High", "Mid"])
    }

    func testTopCampaignsAggregatesDuplicateIds() {
        let top = SpendOverviewViewModel.topCampaigns([
            row("1", name: "A", cost: 5, sales: 10),
            row("1", name: "A", cost: 7, sales: 5),
        ], limit: 5)
        XCTAssertEqual(top.count, 1)
        XCTAssertEqual(top.first?.spend, 12)
        XCTAssertEqual(top.first?.sales, 15)
    }

    func testTrendGroupsByDateSorted() {
        let trend = SpendOverviewViewModel.trend([
            row("1", date: "2026-06-02", cost: 3),
            row("2", date: "2026-06-01", cost: 4),
            row("1", date: "2026-06-01", cost: 1),
        ])
        XCTAssertEqual(trend.count, 2)
        XCTAssertEqual(trend.first?.spend, 5) // 2026-06-01: 4 + 1
        XCTAssertLessThan(trend[0].date, trend[1].date)
    }

    func testReportRangeIs30DaysEndingYesterday() throws {
        let now = try XCTUnwrap(SpendOverviewViewModel.date(from: "2026-06-11"))
        let (start, end) = SpendOverviewViewModel.reportRange(now: now)
        XCTAssertEqual(end, "2026-06-10")
        XCTAssertEqual(start, "2026-05-12")
    }
}
