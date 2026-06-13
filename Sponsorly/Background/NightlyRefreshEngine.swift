import Foundation

/// Performs one report refresh: marks the entry in flight, fetches, and writes the
/// result (or records a failure) into the store. A protocol so the engine's drain
/// logic can be tested without the network — the live implementation is
/// `ReportingReportRefresher`.
protocol ReportRefreshing: Sendable {
    func refresh(
        _ task: RefreshTask,
        key: ReportCacheKey,
        request: ReportRequest,
        scoped: ScopedClient,
        store: ReportStore
    ) async
}

/// Drains a prioritized `RefreshTask` queue, warming each report into the store.
///
/// Resumable: an already-fresh entry (warmed earlier the same night, or an
/// immutable past range) is skipped, so a follow-up run after a cut-short window
/// resumes with only the still-stale items. Cooperative: `shouldContinue` is
/// checked before each item so the OS expiration handler can stop the drain
/// cleanly, leaving the remainder for the next window.
struct NightlyRefreshEngine {
    let store: ReportStore
    let refresher: ReportRefreshing

    /// - Returns: `true` if the whole queue drained, `false` if it was cut short.
    func run(
        tasks: [RefreshTask],
        range: (start: String, end: String),
        scopedClient: @Sendable (RefreshProfileRef) async -> ScopedClient?,
        now: Date = Date(),
        shouldContinue: @Sendable () -> Bool = { true }
    ) async -> Bool {
        for task in tasks {
            guard shouldContinue() else { return false }
            let key = task.cacheKey(range: range)
            // Resumable skip: leave already-fresh reports alone.
            guard await store.needsRefresh(key, now: now) else { continue }
            guard let client = await scopedClient(task.profile) else {
                // A profile we can't build a client for (e.g. token refresh failed)
                // is recorded as failed and skipped — the queue keeps going.
                await store.markFailed(key)
                continue
            }
            await refresher.refresh(
                task, key: key, request: task.request(range: range), scoped: client, store: store
            )
        }
        return true
    }
}

/// Live refresher: drives the Reporting v3 lifecycle via `ReportingRepository`
/// (no hand-rolled Amazon requests) and writes decoded rows into the store.
struct ReportingReportRefresher: ReportRefreshing {
    func refresh(
        _ task: RefreshTask,
        key: ReportCacheKey,
        request: ReportRequest,
        scoped: ScopedClient,
        store: ReportStore
    ) async {
        await store.markRefreshing(key)
        let repository = ReportingRepository(scopedClient: scoped)
        do {
            switch task.kind {
            case .overviewSummary, .overviewDaily:
                let rows: [CampaignReportRow] = try await repository.fetchRows(request)
                await store.save(rows, for: key)
            case .searchTerms:
                let rows: [SearchTermReportRow] = try await repository.fetchRows(request)
                await store.save(rows, for: key)
            }
        } catch {
            await store.markFailed(key)
        }
    }
}
