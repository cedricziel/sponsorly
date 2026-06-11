import AmazonAdsCore
import Foundation
import Observation

/// Loads advertising accounts across the connected regions and owns the active
/// profile selection.
@MainActor
@Observable
final class AccountsViewModel {
    private(set) var accounts = ConnectedAccounts()
    private(set) var isLoading = false
    private(set) var activeSelection: ActiveProfileSelection?
    var errorMessage: String?

    private let auth: AuthViewModel
    private let repository: AccountsRepository
    private let clientID: String?

    #if DEBUG
        /// When set (preview seeding), `load()` keeps the injected sample data.
        fileprivate var isPreviewSeeded = false
    #endif

    init(auth: AuthViewModel) {
        self.auth = auth
        let id = try? LWAConfig.fromBundle(region: LWAConfig.defaultRegion).clientID
        clientID = id
        repository = AccountsRepository(clientID: id ?? "")
        activeSelection = ActiveProfileStore.load()
    }

    /// Connected regions in a stable display order.
    var connectedRegions: [AmazonRegion] {
        AmazonRegion.allCases.filter { auth.connectedRegions.contains($0) }
    }

    var hasConnectedRegions: Bool { !auth.connectedRegions.isEmpty }

    var activeProfile: AdvertisingProfile? {
        guard let selection = activeSelection else { return nil }
        return accounts.profiles.first {
            $0.region == selection.region && $0.profileId == selection.profileId
        }
    }

    /// Fetches accounts for every connected region and reconciles the selection.
    func load() async {
        #if DEBUG
            if isPreviewSeeded { return }
        #endif
        reconcileActive()
        guard hasConnectedRegions else {
            accounts = ConnectedAccounts()
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        var providers: [AmazonRegion: @Sendable () async throws -> String] = [:]
        for region in auth.connectedRegions {
            if let provider = try? auth.tokenProvider(for: region) {
                providers[region] = provider
            }
        }
        accounts = await repository.discover(providers)
        reconcileActive()
    }

    func select(_ profile: AdvertisingProfile) {
        let selection = ActiveProfileSelection(region: profile.region, profileId: profile.profileId)
        activeSelection = selection
        ActiveProfileStore.save(selection)
    }

    func isActive(_ profile: AdvertisingProfile) -> Bool {
        guard let selection = activeSelection else { return false }
        return selection.region == profile.region && selection.profileId == profile.profileId
    }

    func profiles(in region: AmazonRegion) -> [AdvertisingProfile] {
        accounts.profiles.filter { $0.region == region }
    }

    func failure(in region: AmazonRegion) -> String? {
        accounts.failures[region]
    }

    /// Clears the active selection when its region is no longer connected.
    private func reconcileActive() {
        if let selection = activeSelection, !auth.connectedRegions.contains(selection.region) {
            activeSelection = nil
            ActiveProfileStore.save(nil)
        }
    }
}

#if DEBUG
extension AccountsViewModel {
    static func previewModel(auth: AuthViewModel = .previewModel(connected: [])) -> AccountsViewModel {
        AccountsViewModel(auth: auth)
    }

    /// A model seeded with sample accounts for previews; `load()` won't overwrite it.
    static func loaded(
        _ accounts: ConnectedAccounts,
        active: ActiveProfileSelection? = nil
    ) -> AccountsViewModel {
        let regions = Set(accounts.profiles.map(\.region)).union(accounts.failures.keys)
        let model = AccountsViewModel(auth: .previewModel(connected: regions))
        model.accounts = accounts
        model.activeSelection = active
        model.isPreviewSeeded = true
        return model
    }
}
#endif
