@testable import Sponsorly
import SwiftData
import XCTest

final class ReportStoreTests: XCTestCase {
    private let summaryKey = ReportCacheKey(
        profileId: "111", reportTypeId: "spCampaigns",
        startDate: "2026-05-12", endDate: "2026-06-10", timeUnit: "SUMMARY"
    )
    private let dailyKey = ReportCacheKey(
        profileId: "111", reportTypeId: "spCampaigns",
        startDate: "2026-05-12", endDate: "2026-06-10", timeUnit: "DAILY"
    )

    /// A fresh in-memory store per test — no on-disk state, nothing to clean up.
    private func makeStore() throws -> ReportStore {
        let container = try ModelContainer(
            for: CachedReport.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ReportStore(modelContainer: container)
    }

    private func row(cost: Double) -> CampaignReportRow {
        CampaignReportRow(
            campaignId: "1", campaignName: "A", date: nil, impressions: nil,
            clicks: nil, cost: cost, sales30d: nil, purchases30d: nil
        )
    }

    // MARK: - Persistence

    func testRoundTripByKey() async throws {
        let store = try makeStore()
        await store.save([row(cost: 5)], for: summaryKey)
        let loaded = await store.load(summaryKey, as: CampaignReportRow.self)
        XCTAssertEqual(loaded?.first?.cost, 5)
    }

    func testMissingReturnsNil() async throws {
        let store = try makeStore()
        let loaded = await store.load(summaryKey, as: CampaignReportRow.self)
        XCTAssertNil(loaded)
    }

    func testDistinctTimeUnitsDoNotCollide() async throws {
        let store = try makeStore()
        await store.save([row(cost: 5)], for: summaryKey)
        await store.save([row(cost: 9)], for: dailyKey)
        let summary = await store.load(summaryKey, as: CampaignReportRow.self)
        let daily = await store.load(dailyKey, as: CampaignReportRow.self)
        XCTAssertEqual(summary?.first?.cost, 5)
        XCTAssertEqual(daily?.first?.cost, 9)
    }

    func testSaveOverwritesSameKey() async throws {
        let store = try makeStore()
        await store.save([row(cost: 5)], for: summaryKey)
        await store.save([row(cost: 7)], for: summaryKey)
        let loaded = await store.load(summaryKey, as: CampaignReportRow.self)
        XCTAssertEqual(loaded?.count, 1)
        XCTAssertEqual(loaded?.first?.cost, 7)
    }

    // MARK: - Freshness metadata

    func testSaveRecordsRefreshedAtAndFreshStatus() async throws {
        let store = try makeStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        await store.save([row(cost: 5)], for: summaryKey, now: now)
        let meta = await store.metadata(summaryKey)
        XCTAssertEqual(meta?.refreshedAt, now)
        XCTAssertEqual(meta?.status, .fresh)
    }

    func testFailurePreservesLastGoodPayload() async throws {
        let store = try makeStore()
        await store.save([row(cost: 5)], for: summaryKey)
        await store.markFailed(summaryKey)
        let loaded = await store.load(summaryKey, as: CampaignReportRow.self)
        let meta = await store.metadata(summaryKey)
        XCTAssertEqual(loaded?.first?.cost, 5, "payload must survive a failed refresh")
        XCTAssertEqual(meta?.status, .failed)
    }

    func testMarkRefreshingSetsStatus() async throws {
        let store = try makeStore()
        await store.save([row(cost: 5)], for: summaryKey)
        await store.markRefreshing(summaryKey)
        let meta = await store.metadata(summaryKey)
        XCTAssertEqual(meta?.status, .refreshing)
    }

    // MARK: - Staleness query

    func testStaleKeysExcludesInFlightRefreshing() async throws {
        let store = try makeStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // A today-inclusive (volatile) range so it can go stale by age.
        let volatileKey = ReportCacheKey(
            profileId: "111", reportTypeId: "spCampaigns",
            startDate: "2026-06-01", endDate: "2099-01-01", timeUnit: "SUMMARY"
        )
        await store.save([row(cost: 5)], for: volatileKey, now: now)
        await store.markRefreshing(volatileKey, now: now)
        let policy = StalenessPolicy(volatileTTL: 300, reclaimAfter: 7200)
        // Even well past the volatile TTL, an in-flight entry is not selected...
        let later = now.addingTimeInterval(3600)
        let stale = await store.staleKeys(now: later, policy: policy)
        XCTAssertFalse(stale.contains(volatileKey))
        // ...until it has been refreshing longer than the reclaim window.
        let muchLater = now.addingTimeInterval(8000)
        let reclaimed = await store.staleKeys(now: muchLater, policy: policy)
        XCTAssertTrue(reclaimed.contains(volatileKey))
    }

    func testFreshImmutableRangeIsNotStale() async throws {
        let store = try makeStore()
        // `now` is after the key's endDate (2026-06-10), so the range is immutable.
        let now = Date(timeIntervalSince1970: 1_790_000_000) // 2026-09-21 UTC
        await store.save([row(cost: 5)], for: summaryKey, now: now)
        let stale = await store.staleKeys(now: now.addingTimeInterval(7 * 24 * 3600))
        XCTAssertFalse(stale.contains(summaryKey))
    }

    func testFailedEntryIsAlwaysStale() async throws {
        let store = try makeStore()
        await store.save([row(cost: 5)], for: summaryKey)
        await store.markFailed(summaryKey)
        let stale = await store.staleKeys(now: Date())
        XCTAssertTrue(stale.contains(summaryKey))
    }

    // MARK: - Staleness rule (pure)

    func testIsStaleRules() {
        let now = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 UTC
        let policy = StalenessPolicy(volatileTTL: 300, reclaimAfter: 7200)
        // Fresh, immutable past range → not stale regardless of age.
        XCTAssertFalse(ReportStore.isStale(
            .fresh, endDate: "2020-01-01", refreshedAt: now.addingTimeInterval(-1_000_000),
            now: now, policy: policy
        ))
        // Fresh, today-inclusive range, within TTL → not stale.
        XCTAssertFalse(ReportStore.isStale(
            .fresh, endDate: "2099-01-01", refreshedAt: now.addingTimeInterval(-100),
            now: now, policy: policy
        ))
        // Fresh, today-inclusive range, past TTL → stale.
        XCTAssertTrue(ReportStore.isStale(
            .fresh, endDate: "2099-01-01", refreshedAt: now.addingTimeInterval(-400),
            now: now, policy: policy
        ))
        // Failed → stale.
        XCTAssertTrue(ReportStore.isStale(
            .failed, endDate: "2020-01-01", refreshedAt: now, now: now, policy: policy
        ))
        // Refreshing within reclaim window → not stale; past it → stale.
        XCTAssertFalse(ReportStore.isStale(
            .refreshing, endDate: "2099-01-01", refreshedAt: now.addingTimeInterval(-100),
            now: now, policy: policy
        ))
        XCTAssertTrue(ReportStore.isStale(
            .refreshing, endDate: "2099-01-01", refreshedAt: now.addingTimeInterval(-8000),
            now: now, policy: policy
        ))
    }
}
