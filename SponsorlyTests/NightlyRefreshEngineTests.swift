import AmazonAdsCore
@testable import Sponsorly
import SwiftData
import XCTest

final class NightlyRefreshEngineTests: XCTestCase {
    private let profile = RefreshProfileRef(region: .europe, profileId: "111")
    private let range = (start: "2026-05-01", end: "2026-05-30")
    /// After the range's endDate, so a saved entry is immutable (won't age out).
    private let now = Date(timeIntervalSince1970: 1_790_000_000) // 2026-09-21 UTC

    /// Records which tasks were refreshed and marks each one fresh in the store, so
    /// a second run would skip it (mirrors a real successful fetch).
    private actor FakeRefresher: ReportRefreshing {
        private(set) var refreshed: [RefreshTask] = []

        func refresh(
            _ task: RefreshTask, key: ReportCacheKey, request _: ReportRequest,
            scoped _: ScopedClient, store: ReportStore
        ) async {
            refreshed.append(task)
            await store.save([CampaignReportRow(
                campaignId: "1", campaignName: "A", date: nil, impressions: nil,
                clicks: nil, cost: 1, sales30d: nil, purchases30d: nil
            )], for: key, now: Date(timeIntervalSince1970: 1_790_000_000))
        }
    }

    private func makeStore() throws -> ReportStore {
        let container = try ModelContainer(
            for: CachedReport.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ReportStore(modelContainer: container)
    }

    private func dummyClient() -> ScopedClient {
        ScopedClient(
            transport: AuthenticatedTransport(tokenProvider: { "t" }, clientId: "c", profileId: "111"),
            baseURL: AmazonRegion.europe.advertisingAPIBaseURL,
            region: .europe, profileId: "111", clientID: "c", tokenProvider: { "t" }
        )
    }

    func testDrainsEveryTaskWhenContinuing() async throws {
        let store = try makeStore()
        let fake = FakeRefresher()
        let engine = NightlyRefreshEngine(store: store, refresher: fake)
        let tasks = RefreshQueueBuilder.build(profiles: [profile], active: profile)

        let completed = await engine.run(
            tasks: tasks, range: range, scopedClient: { [self] _ in dummyClient() }, now: now
        )

        XCTAssertTrue(completed)
        let count = await fake.refreshed.count
        XCTAssertEqual(count, 3) // summary + daily + searchTerms
    }

    func testSkipsAlreadyFreshEntries() async throws {
        let store = try makeStore()
        // Pre-warm the summary report; the engine should skip it.
        let summaryKey = RefreshTask(profile: profile, kind: .overviewSummary).cacheKey(range: range)
        await store.save([CampaignReportRow(
            campaignId: "1", campaignName: "A", date: nil, impressions: nil,
            clicks: nil, cost: 1, sales30d: nil, purchases30d: nil
        )], for: summaryKey, now: now)

        let fake = FakeRefresher()
        let engine = NightlyRefreshEngine(store: store, refresher: fake)
        let tasks = RefreshQueueBuilder.build(profiles: [profile], active: profile)

        _ = await engine.run(
            tasks: tasks, range: range, scopedClient: { [self] _ in dummyClient() }, now: now
        )

        let refreshed = await fake.refreshed.map(\.kind)
        XCTAssertFalse(refreshed.contains(.overviewSummary), "fresh entry must be skipped")
        XCTAssertTrue(refreshed.contains(.overviewDaily))
        XCTAssertTrue(refreshed.contains(.searchTerms))
    }

    func testCutShortStopsAndReportsIncomplete() async throws {
        let store = try makeStore()
        let fake = FakeRefresher()
        let engine = NightlyRefreshEngine(store: store, refresher: fake)
        let tasks = RefreshQueueBuilder.build(profiles: [profile], active: profile)

        let completed = await engine.run(
            tasks: tasks, range: range, scopedClient: { [self] _ in dummyClient() },
            now: now, shouldContinue: { false }
        )

        XCTAssertFalse(completed, "a cut-short window reports incomplete")
        let count = await fake.refreshed.count
        XCTAssertEqual(count, 0)
    }

    func testMissingClientMarksEntryFailed() async throws {
        let store = try makeStore()
        // An existing (stale) entry whose profile can't produce a client.
        let key = RefreshTask(profile: profile, kind: .overviewSummary).cacheKey(range: range)
        await store.save([CampaignReportRow(
            campaignId: "1", campaignName: "A", date: nil, impressions: nil,
            clicks: nil, cost: 1, sales30d: nil, purchases30d: nil
        )], for: key, now: now)
        await store.markFailed(key) // make it stale so the engine attempts it

        let fake = FakeRefresher()
        let engine = NightlyRefreshEngine(store: store, refresher: fake)

        _ = await engine.run(
            tasks: [RefreshTask(profile: profile, kind: .overviewSummary)],
            range: range, scopedClient: { _ in nil }, now: now
        )

        let meta = await store.metadata(key)
        XCTAssertEqual(meta?.status, .failed)
        let count = await fake.refreshed.count
        XCTAssertEqual(count, 0, "no client → refresher never called")
    }
}
