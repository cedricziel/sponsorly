import Foundation
import Observation

/// Loads the active profile's Sponsored Products campaigns.
@MainActor
@Observable
final class CampaignsViewModel {
    private(set) var campaigns: [Campaign] = []
    private(set) var isLoading = false
    private(set) var truncated = false
    var errorMessage: String?

    func load(using accounts: AccountsViewModel) async {
        guard accounts.activeSelection != nil else {
            campaigns = []
            errorMessage = nil
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let scoped = try accounts.scopedClient()
            let result = try await CampaignsRepository(scopedClient: scoped).listCampaigns()
            campaigns = result.campaigns
            truncated = result.truncated
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// Loads a campaign's ad groups.
@MainActor
@Observable
final class AdGroupsViewModel {
    private(set) var adGroups: [AdGroup] = []
    private(set) var isLoading = false
    private(set) var truncated = false
    var errorMessage: String?

    func load(campaignId: String, using accounts: AccountsViewModel) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let scoped = try accounts.scopedClient()
            let result = try await CampaignsRepository(scopedClient: scoped)
                .listAdGroups(campaignId: campaignId)
            adGroups = result.adGroups
            truncated = result.truncated
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#if DEBUG
    extension CampaignsViewModel {
        static func loaded(_ campaigns: [Campaign]) -> CampaignsViewModel {
            let model = CampaignsViewModel()
            model.campaigns = campaigns
            return model
        }
    }
#endif
