import Foundation
import SwiftData

/// Durable, queryable store for decoded report rows, backed by SwiftData in
/// Application Support (which iOS does not evict under storage pressure, unlike
/// the previous `.cachesDirectory` cache).
///
/// A `@ModelActor` so the off-main-actor background refresh task and the
/// `@MainActor` view models can share one serialized `ModelContext` without
/// violating strict concurrency: every access is funneled through this single
/// owner, and only `Sendable` value types (decoded rows, `ReportMetadata`,
/// `ReportCacheKey`) cross the actor boundary — never a `ModelContext` or
/// `@Model` instance.
@ModelActor
actor ReportStore {
    /// App-wide store backed by the shared on-disk container. Both the view models
    /// and the background refresh task talk to this single instance.
    static let shared = ReportStore(modelContainer: sharedContainer)

    /// One durable `ModelContainer` in Application Support (which the OS does not
    /// evict). The directory is created explicitly — unlike Caches, iOS does not
    /// create Application Support for us, and SwiftData's default store path assumes
    /// it exists. Falls back to in-memory if the store can't be opened, so the app
    /// degrades to a session cache rather than crashing on launch.
    static let sharedContainer: ModelContainer = {
        do {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
            let storeURL = appSupport.appendingPathComponent("Reports.store")
            return try ModelContainer(
                for: CachedReport.self,
                configurations: ModelConfiguration(url: storeURL)
            )
        } catch {
            // swiftlint:disable:next force_try
            return try! ModelContainer(
                for: CachedReport.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }
    }()

    // MARK: - Read

    /// Decodes and returns the stored rows for a key, or `nil` if absent/unreadable.
    func load<Row: Codable & Sendable>(_ key: ReportCacheKey, as _: Row.Type = Row.self) -> [Row]? {
        guard let report = fetch(key),
              let rows = try? JSONDecoder().decode([Row].self, from: report.payload)
        else {
            return nil
        }
        return rows
    }

    /// Freshness metadata for a key, or `nil` if there is no stored entry.
    func metadata(_ key: ReportCacheKey) -> ReportMetadata? {
        guard let report = fetch(key) else { return nil }
        return ReportMetadata(refreshedAt: report.refreshedAt, status: report.status)
    }

    /// Whether a key should be fetched: `true` when there is no entry, or the
    /// existing entry is stale. Drives the background queue's resumable skip —
    /// an already-fresh report (warmed earlier the same night, or an immutable
    /// past range) is left alone.
    func needsRefresh(_ key: ReportCacheKey, now: Date = Date(), policy: StalenessPolicy = .default) -> Bool {
        guard let report = fetch(key) else { return true }
        return Self.isStale(
            report.status, endDate: report.endDate, refreshedAt: report.refreshedAt,
            now: now, policy: policy
        )
    }

    /// Keys whose entries should be refreshed, given the current time and the
    /// staleness policy. In-flight (`refreshing`) entries are excluded unless they
    /// have been stuck longer than the policy's reclaim window.
    func staleKeys(now: Date, policy: StalenessPolicy = .default) -> [ReportCacheKey] {
        let all = (try? modelContext.fetch(FetchDescriptor<CachedReport>())) ?? []
        return all
            .filter {
                Self.isStale(
                    $0.status, endDate: $0.endDate, refreshedAt: $0.refreshedAt,
                    now: now, policy: policy
                )
            }
            .map(\.key)
    }

    // MARK: - Write

    /// Stores rows for a key, stamping `refreshedAt` and marking the entry `fresh`.
    func save(_ rows: [some Codable & Sendable], for key: ReportCacheKey, now: Date = Date()) {
        guard let data = try? JSONEncoder().encode(rows) else { return }
        if let existing = fetch(key) {
            existing.payload = data
            existing.refreshedAt = now
            existing.status = .fresh
        } else {
            modelContext.insert(
                CachedReport(key: key, payload: data, refreshedAt: now, status: .fresh)
            )
        }
        try? modelContext.save()
    }

    /// Marks an entry as in-flight, stamping `refreshedAt` as the start time so a
    /// stuck refresh can later be reclaimed. No-op if the entry is absent.
    func markRefreshing(_ key: ReportCacheKey, now: Date = Date()) {
        guard let report = fetch(key) else { return }
        report.status = .refreshing
        report.refreshedAt = now
        try? modelContext.save()
    }

    /// Marks an entry as failed while retaining its last-good payload. No-op if the
    /// entry is absent.
    func markFailed(_ key: ReportCacheKey, now _: Date = Date()) {
        guard let report = fetch(key) else { return }
        report.status = .failed
        try? modelContext.save()
    }

    // MARK: - Private

    private func fetch(_ key: ReportCacheKey) -> CachedReport? {
        // Filter in-memory rather than via #Predicate: the store holds one entry
        // per report (a tiny set), and #Predicate generates a non-Sendable KeyPath
        // that trips strict concurrency.
        let storageKey = key.storageKey
        let all = (try? modelContext.fetch(FetchDescriptor<CachedReport>())) ?? []
        return all.first { $0.storageKey == storageKey }
    }

    // MARK: - Staleness rule (pure, testable)

    /// Whether an entry should be refreshed.
    ///
    /// - `failed` / `stale`: always refresh.
    /// - `refreshing`: skip (in flight) unless stuck longer than the reclaim window.
    /// - `fresh`: immutable past-day ranges (endDate before today, UTC) are never
    ///   stale by age; today-inclusive ranges go stale after the volatile TTL.
    static func isStale(
        _ status: RefreshStatus,
        endDate: String,
        refreshedAt: Date,
        now: Date,
        policy: StalenessPolicy
    ) -> Bool {
        switch status {
        case .failed, .stale:
            return true
        case .refreshing:
            return now.timeIntervalSince(refreshedAt) > policy.reclaimAfter
        case .fresh:
            guard isVolatile(endDate: endDate, now: now) else { return false }
            return now.timeIntervalSince(refreshedAt) > policy.volatileTTL
        }
    }

    /// A range is volatile (its data can still change) when its end date is today
    /// or later in UTC; past-day ranges are immutable.
    static func isVolatile(endDate: String, now: Date) -> Bool {
        guard let end = ymdFormatter.date(from: endDate) else { return true }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return end >= utc.startOfDay(for: now)
    }

    private static let ymdFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
