import AmazonAdsCore
import BackgroundTasks
import Foundation

/// Registers and runs the single nightly `BGProcessingTask` that warms report data
/// overnight while charging. One task identifier, one prioritized resumable queue —
/// `earliestBeginDate` is a floor the OS may run later (or skip), so the UI shows
/// data age rather than implying freshness.
enum BackgroundRefreshScheduler {
    static let taskIdentifier = "com.cedricziel.sponsorly.nightly-refresh"
    /// Default floor before the OS may run the task (≈ overnight from an evening use).
    private static let earliestInterval: TimeInterval = 8 * 3600

    /// Registers the task handler. Must be called before the app finishes launching.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let processing = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { await handle(processing) }
        }
    }

    /// Submits a request for the next run. Safe to call repeatedly (on launch and
    /// after each run); a no-op failure (e.g. simulator without entitlement) is
    /// ignored so it never blocks the app.
    static func schedule(earliestAfter: TimeInterval = earliestInterval) {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = true
        request.earliestBeginDate = Date(timeIntervalSinceNow: earliestAfter)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func handle(_ task: BGProcessingTask) async {
        // Line up the next night first, so a skipped or cut-short run still recurs.
        schedule()
        let flag = CancellationFlag()
        task.expirationHandler = { flag.cancel() }
        let completed = await runRefresh(shouldContinue: { !flag.isCancelled })
        task.setTaskCompleted(success: completed)
    }

    /// Bootstraps auth + accounts headlessly, builds the prioritized queue, and
    /// drains it into the store. Injectable for testing the bootstrap path.
    /// - Returns: `true` if the queue fully drained (or there was nothing to do).
    @discardableResult
    static func runRefresh(
        store: ReportStore = .shared,
        refresher: ReportRefreshing = ReportingReportRefresher(),
        now: Date = Date(),
        shouldContinue: @Sendable () -> Bool = { true }
    ) async -> Bool {
        guard let clientID = try? LWAConfig.fromBundle(region: LWAConfig.defaultRegion).clientID else {
            return true // no credentials configured — nothing to warm
        }
        let providers = await connectedProviders()
        guard !providers.isEmpty else { return true }

        let accounts = await AccountsRepository(clientID: clientID).discover(providers)
        let profiles = accounts.profiles.map {
            RefreshProfileRef(region: $0.region, profileId: $0.profileId)
        }
        guard !profiles.isEmpty else { return true }

        let active = ActiveProfileStore.load().map {
            RefreshProfileRef(region: $0.region, profileId: $0.profileId)
        }
        let tasks = RefreshQueueBuilder.build(profiles: profiles, active: active)
        let range = SpendOverviewViewModel.reportRange(now: now)

        let engine = NightlyRefreshEngine(store: store, refresher: refresher)
        return await engine.run(
            tasks: tasks,
            range: range,
            scopedClient: { profile in
                guard let provider = providers[profile.region] else { return nil }
                return try? ActiveProfileClientFactory.make(
                    selection: ActiveProfileSelection(
                        region: profile.region, profileId: profile.profileId
                    ),
                    clientID: clientID,
                    tokenProvider: { _ in provider }
                )
            },
            now: now,
            shouldContinue: shouldContinue
        )
    }

    /// Token providers for every region with a stored refresh token. The Keychain
    /// item is `AfterFirstUnlock`, so these resolve while the device is locked.
    static func connectedProviders() async -> [AmazonRegion: @Sendable () async throws -> String] {
        var providers: [AmazonRegion: @Sendable () async throws -> String] = [:]
        let storage = KeychainTokenStorage()
        for region in AmazonRegion.allCases {
            guard let config = try? LWAConfig.fromBundle(region: region) else { continue }
            let service = LWAAuthService(config: config, storage: storage)
            if await service.isAuthenticated() {
                providers[region] = service.tokenProvider()
            }
        }
        return providers
    }
}

/// A thread-safe one-way cancellation flag: set from the BGTask expiration handler
/// (synchronous) and polled by the async drain between items.
final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
    }
}
