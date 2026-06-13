import AmazonAdsCore
import Foundation

/// A connected advertising profile the nightly refresh can warm.
struct RefreshProfileRef: Hashable {
    let region: AmazonRegion
    let profileId: String
}

/// The reports the nightly refresh warms per profile, in priority tiers: the two
/// spend-overview reports first, the heavy search-term (harvesting) report last.
enum RefreshReportKind: CaseIterable {
    case overviewSummary
    case overviewDaily
    case searchTerms

    /// Overview reports are morning-critical; harvesting is the heavy tail.
    var isOverview: Bool {
        self == .overviewSummary || self == .overviewDaily
    }

    var reportTypeId: String {
        switch self {
        case .overviewSummary, .overviewDaily: "spCampaigns"
        case .searchTerms: "spSearchTerm"
        }
    }

    var timeUnit: String {
        switch self {
        case .overviewDaily: "DAILY"
        case .overviewSummary, .searchTerms: "SUMMARY"
        }
    }
}

/// One unit of background work: warm a specific report for a specific profile.
struct RefreshTask: Hashable {
    let profile: RefreshProfileRef
    let kind: RefreshReportKind

    /// The cache key this task writes — identical to what the on-screen view models
    /// load, so a warmed entry is rendered without a refetch.
    func cacheKey(range: (start: String, end: String)) -> ReportCacheKey {
        ReportCacheKey(
            profileId: profile.profileId,
            reportTypeId: kind.reportTypeId,
            startDate: range.start,
            endDate: range.end,
            timeUnit: kind.timeUnit
        )
    }

    /// The Reporting v3 request body for this task.
    func request(range: (start: String, end: String)) -> ReportRequest {
        switch kind {
        case .overviewSummary:
            .spCampaigns(
                name: "nightly-summary", startDate: range.start, endDate: range.end,
                timeUnit: "SUMMARY", columns: CampaignReportRow.summaryColumns
            )
        case .overviewDaily:
            .spCampaigns(
                name: "nightly-daily", startDate: range.start, endDate: range.end,
                timeUnit: "DAILY", columns: CampaignReportRow.dailyColumns
            )
        case .searchTerms:
            .spSearchTerm(name: "nightly-harvest", startDate: range.start, endDate: range.end)
        }
    }
}

/// Builds the prioritized work queue. Order: the active profile's overview reports,
/// then every other profile's overview reports, then every profile's harvesting
/// report (active profile first within the tail). "Grab everything" across all
/// connected profiles × all report kinds, made tractable by the resumable drain.
enum RefreshQueueBuilder {
    static func build(profiles: [RefreshProfileRef], active: RefreshProfileRef?) -> [RefreshTask] {
        // Active profile first, then the rest in their given order; de-duplicated.
        var ordered: [RefreshProfileRef] = []
        if let active, profiles.contains(active) { ordered.append(active) }
        for profile in profiles where !ordered.contains(profile) {
            ordered.append(profile)
        }

        let overviewKinds: [RefreshReportKind] = [.overviewSummary, .overviewDaily]
        var tasks: [RefreshTask] = []
        // Tier 1+2: every profile's overview reports (active profile already first).
        for profile in ordered {
            tasks.append(contentsOf: overviewKinds.map { RefreshTask(profile: profile, kind: $0) })
        }
        // Tier 3: the heavy harvesting tail, same profile order.
        tasks.append(contentsOf: ordered.map { RefreshTask(profile: $0, kind: .searchTerms) })
        return tasks
    }
}
