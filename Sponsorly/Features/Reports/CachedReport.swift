import Foundation
import SwiftData

/// Lifecycle state of a stored report, used by the background refresh queue to
/// decide what to (re)fetch and by the UI to communicate staleness.
enum RefreshStatus: String, Codable {
    /// Up to date; renderable without a network fetch.
    case fresh
    /// Known out of date — should be refreshed.
    case stale
    /// A refresh is currently in flight (skipped by the queue until it finishes
    /// or is reclaimed as stuck).
    case refreshing
    /// The last refresh attempt failed; the previously stored payload is retained.
    case failed
}

/// A `Sendable` snapshot of a stored report's metadata, safe to return across the
/// `ReportStore` actor boundary (the `@Model` itself must not escape it).
struct ReportMetadata: Equatable {
    let refreshedAt: Date
    let status: RefreshStatus
}

/// Thresholds governing when a stored report counts as stale.
struct StalenessPolicy: Equatable {
    /// How long a today-inclusive (volatile) range stays fresh before re-fetch.
    var volatileTTL: TimeInterval
    /// How long an entry may sit `refreshing` before it's treated as stuck and
    /// reclaimed as stale.
    var reclaimAfter: TimeInterval

    /// 5-minute volatile TTL (matches the previous cache), 2-hour reclaim window
    /// (longer than any single background-refresh window).
    static let `default` = StalenessPolicy(volatileTTL: 300, reclaimAfter: 2 * 3600)
}

/// One durable entry per report cache key. The decoded rows live in `payload` as
/// an encoded blob — report rows number in the thousands, so storing them as a
/// single blob (rather than relational per-row records) keeps writes cheap while
/// the identity + metadata columns stay queryable for the refresh queue.
@Model
final class CachedReport {
    @Attribute(.unique) var storageKey: String
    var profileId: String
    var reportTypeId: String
    var startDate: String
    var endDate: String
    var timeUnit: String
    var payload: Data
    var refreshedAt: Date
    /// Stored as a raw string so SwiftData fetches stay enum-agnostic.
    var statusRaw: String

    var status: RefreshStatus {
        get { RefreshStatus(rawValue: statusRaw) ?? .stale }
        set { statusRaw = newValue.rawValue }
    }

    /// Reconstructs the value-type key for returning across the actor boundary.
    var key: ReportCacheKey {
        ReportCacheKey(
            profileId: profileId, reportTypeId: reportTypeId,
            startDate: startDate, endDate: endDate, timeUnit: timeUnit
        )
    }

    init(key: ReportCacheKey, payload: Data, refreshedAt: Date, status: RefreshStatus) {
        storageKey = key.storageKey
        profileId = key.profileId
        reportTypeId = key.reportTypeId
        startDate = key.startDate
        endDate = key.endDate
        timeUnit = key.timeUnit
        self.payload = payload
        self.refreshedAt = refreshedAt
        statusRaw = status.rawValue
    }
}

/// Identifies a cached report by everything that determines its contents.
struct ReportCacheKey: Hashable {
    let profileId: String
    let reportTypeId: String
    let startDate: String
    let endDate: String
    let timeUnit: String

    /// Stable unique identity for the `CachedReport` row.
    var storageKey: String {
        "\(profileId)_\(reportTypeId)_\(startDate)_\(endDate)_\(timeUnit)"
            .replacingOccurrences(of: "/", with: "-")
    }
}
