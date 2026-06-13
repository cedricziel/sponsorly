import AmazonAdsCore
@testable import Sponsorly
import XCTest

final class RefreshQueueTests: XCTestCase {
    private let profileA = RefreshProfileRef(region: .europe, profileId: "AAA")
    private let profileB = RefreshProfileRef(region: .northAmerica, profileId: "BBB")

    func testActiveProfileOverviewComesFirst() {
        let tasks = RefreshQueueBuilder.build(profiles: [profileA, profileB], active: profileB)
        // profileB's overview before profileA's overview.
        XCTAssertEqual(tasks.first, RefreshTask(profile: profileB, kind: .overviewSummary))
        XCTAssertEqual(tasks[1], RefreshTask(profile: profileB, kind: .overviewDaily))
        XCTAssertEqual(tasks[2], RefreshTask(profile: profileA, kind: .overviewSummary))
        XCTAssertEqual(tasks[3], RefreshTask(profile: profileA, kind: .overviewDaily))
    }

    func testHarvestingIsTheTail() throws {
        let tasks = RefreshQueueBuilder.build(profiles: [profileA, profileB], active: profileA)
        let firstHarvest = try XCTUnwrap(tasks.firstIndex { $0.kind == .searchTerms })
        let lastOverview = try XCTUnwrap(tasks.lastIndex { $0.kind.isOverview })
        XCTAssertGreaterThan(firstHarvest, lastOverview, "all overview reports precede any harvesting report")
        // Harvesting tail keeps the active-first profile order too.
        XCTAssertEqual(tasks[firstHarvest], RefreshTask(profile: profileA, kind: .searchTerms))
    }

    func testNoActiveKeepsGivenOrder() {
        let tasks = RefreshQueueBuilder.build(profiles: [profileA, profileB], active: nil)
        XCTAssertEqual(tasks.first, RefreshTask(profile: profileA, kind: .overviewSummary))
    }

    func testActiveNotInProfilesIsIgnored() {
        let other = RefreshProfileRef(region: .farEast, profileId: "ZZZ")
        let tasks = RefreshQueueBuilder.build(profiles: [profileA, profileB], active: other)
        XCTAssertEqual(tasks.first, RefreshTask(profile: profileA, kind: .overviewSummary))
        XCTAssertEqual(tasks.count, 6) // 2 profiles × 3 kinds
    }

    func testCacheKeyMatchesOnScreenShape() {
        let range = (start: "2026-05-01", end: "2026-05-30")
        let summary = RefreshTask(profile: profileA, kind: .overviewSummary).cacheKey(range: range)
        XCTAssertEqual(summary.reportTypeId, "spCampaigns")
        XCTAssertEqual(summary.timeUnit, "SUMMARY")
        XCTAssertEqual(summary.profileId, "AAA")

        let harvest = RefreshTask(profile: profileA, kind: .searchTerms).cacheKey(range: range)
        XCTAssertEqual(harvest.reportTypeId, "spSearchTerm")
        XCTAssertEqual(harvest.timeUnit, "SUMMARY")
    }
}
