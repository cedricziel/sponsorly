import Foundation
import Observation

/// Builds the spend overview for the active profile: a 30-day spend/sales/ACOS
/// headline + top campaigns (summary report), a daily spend trend (daily report),
/// and a live "today so far" tile (budget usage). Renders cached report data
/// immediately and refreshes in the background; a source failing degrades only
/// its own tile.
@MainActor
@Observable
final class SpendOverviewViewModel {
    private(set) var headline = SpendMetrics()
    private(set) var topCampaigns: [CampaignSpend] = []
    private(set) var trend: [DailySpend] = []
    private(set) var todaySpend: Double?
    /// When the rendered report data was last refreshed (from the store entry), so
    /// the UI can show its age rather than imply live freshness.
    private(set) var lastUpdated: Date?
    private(set) var isLoading = false
    var errorMessage: String?

    private let store = ReportStore.shared
    private static let topCampaignLimit = 5
    private static let reportTypeId = "spCampaigns"

    var isEmpty: Bool {
        headline == SpendMetrics() && trend.isEmpty && topCampaigns.isEmpty && todaySpend == nil
    }

    func load(using accounts: AccountsViewModel) async {
        guard accounts.activeSelection != nil else {
            reset()
            return
        }
        let scoped: ScopedClient
        do {
            scoped = try accounts.scopedClient()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let (start, end) = Self.reportRange()
        let summaryKey = key(scoped, start: start, end: end, timeUnit: "SUMMARY")
        let dailyKey = key(scoped, start: start, end: end, timeUnit: "DAILY")

        // Render stored report data immediately, dated by when it was last written.
        if let cached = await store.load(summaryKey, as: CampaignReportRow.self) { applySummary(cached) }
        if let cached = await store.load(dailyKey, as: CampaignReportRow.self) { applyDaily(cached) }
        if let meta = await store.metadata(summaryKey) { lastUpdated = meta.refreshedAt }

        // Refresh all three sources in parallel.
        async let todayTask = Self.fetchTodaySpend(scoped)
        async let summaryTask = Self.fetchReport(
            scoped, start: start, end: end, timeUnit: "SUMMARY",
            columns: CampaignReportRow.summaryColumns
        )
        async let dailyTask = Self.fetchReport(
            scoped, start: start, end: end, timeUnit: "DAILY",
            columns: CampaignReportRow.dailyColumns
        )
        let today = await todayTask
        let summary = await summaryTask
        let daily = await dailyTask

        if let today { todaySpend = today }
        let now = Date()
        if let summary {
            applySummary(summary)
            await store.save(summary, for: summaryKey, now: now)
            lastUpdated = now
        }
        if let daily {
            applyDaily(daily)
            await store.save(daily, for: dailyKey, now: now)
        }

        if today == nil, summary == nil, daily == nil, headline == SpendMetrics(), trend.isEmpty {
            errorMessage = "Couldn't load your spend overview."
        }
    }

    private func key(_ scoped: ScopedClient, start: String, end: String, timeUnit: String) -> ReportCacheKey {
        ReportCacheKey(
            profileId: scoped.profileId, reportTypeId: Self.reportTypeId,
            startDate: start, endDate: end, timeUnit: timeUnit
        )
    }

    private func applySummary(_ rows: [CampaignReportRow]) {
        headline = Self.aggregateHeadline(rows)
        topCampaigns = Self.topCampaigns(rows, limit: Self.topCampaignLimit)
    }

    private func applyDaily(_ rows: [CampaignReportRow]) {
        trend = Self.trend(rows)
    }

    private func reset() {
        headline = SpendMetrics()
        topCampaigns = []
        trend = []
        todaySpend = nil
        lastUpdated = nil
        errorMessage = nil
    }

    // MARK: - Fetching (off the main actor; failures become nil)

    private static func fetchTodaySpend(_ scoped: ScopedClient) async -> Double? {
        guard let campaigns = try? await CampaignsRepository(scopedClient: scoped).listCampaigns() else {
            return nil
        }
        let ids = campaigns.campaigns.map(\.campaignId)
        return try? await BudgetUsageRepository(scopedClient: scoped).todaySpend(campaignIds: ids)
    }

    private static func fetchReport(
        _ scoped: ScopedClient, start: String, end: String, timeUnit: String, columns: [String]
    ) async -> [CampaignReportRow]? {
        let request = ReportRequest.spCampaigns(
            name: "spend-overview-\(timeUnit.lowercased())",
            startDate: start, endDate: end, timeUnit: timeUnit, columns: columns
        )
        return try? await ReportingRepository(scopedClient: scoped).fetchCampaignRows(request)
    }

    // MARK: - Aggregation (pure, testable, isolation-free)

    nonisolated static func aggregateHeadline(_ rows: [CampaignReportRow]) -> SpendMetrics {
        var metrics = SpendMetrics()
        for row in rows {
            metrics.spend += row.cost ?? 0
            metrics.sales += row.sales30d ?? 0
        }
        return metrics
    }

    nonisolated static func topCampaigns(_ rows: [CampaignReportRow], limit: Int) -> [CampaignSpend] {
        var byID: [String: CampaignSpend] = [:]
        for row in rows {
            guard let id = row.campaignId else { continue }
            let existing = byID[id]
            byID[id] = CampaignSpend(
                campaignId: id,
                name: row.campaignName ?? existing?.name ?? id,
                spend: (existing?.spend ?? 0) + (row.cost ?? 0),
                sales: (existing?.sales ?? 0) + (row.sales30d ?? 0)
            )
        }
        return byID.values
            .sorted { $0.spend > $1.spend }
            .prefix(limit)
            .map { $0 }
    }

    nonisolated static func trend(_ rows: [CampaignReportRow]) -> [DailySpend] {
        let formatter = makeDateFormatter()
        var byDate: [Date: Double] = [:]
        for row in rows {
            guard let dateString = row.date, let date = formatter.date(from: dateString) else { continue }
            byDate[date, default: 0] += row.cost ?? 0
        }
        return byDate
            .map { DailySpend(date: $0.key, spend: $0.value) }
            .sorted { $0.date < $1.date }
    }

    /// Report range: the last 30 days ending **yesterday** (immutable → cacheable).
    nonisolated static func reportRange(now: Date = Date()) -> (start: String, end: String) {
        let formatter = makeDateFormatter()
        let calendar = Calendar(identifier: .gregorian)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let start = calendar.date(byAdding: .day, value: -29, to: yesterday) ?? yesterday
        return (formatter.string(from: start), formatter.string(from: yesterday))
    }

    /// Parses a `yyyy-MM-dd` report date (UTC).
    nonisolated static func date(from string: String) -> Date? {
        makeDateFormatter().date(from: string)
    }

    private nonisolated static func makeDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

#if DEBUG
    extension SpendOverviewViewModel {
        /// A populated model for previews; `updatedAgo` ages `lastUpdated` so the
        /// freshness indicator can be previewed in a stale state.
        static func preview(updatedAgo: TimeInterval = 3600) -> SpendOverviewViewModel {
            let model = SpendOverviewViewModel()
            model.headline = SpendMetrics(spend: 1240.50, sales: 5310.00)
            model.topCampaigns = [
                CampaignSpend(campaignId: "1", name: "SP | Brand | Exact", spend: 420, sales: 1900),
                CampaignSpend(campaignId: "2", name: "SP | Auto | Discovery", spend: 360, sales: 980),
            ]
            model.todaySpend = 48.20
            model.lastUpdated = Date(timeIntervalSinceNow: -updatedAgo)
            return model
        }
    }
#endif
