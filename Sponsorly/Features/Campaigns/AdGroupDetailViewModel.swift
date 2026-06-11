import Foundation
import Observation

/// Loads an ad group's product ads, keywords, and targeting clauses in parallel.
/// A failure in one kind degrades that section; a top-level error is shown only
/// if all three fail.
@MainActor
@Observable
final class AdGroupDetailViewModel {
    private(set) var productAds: [ProductAd] = []
    private(set) var keywords: [Keyword] = []
    private(set) var targetingClauses: [TargetingClause] = []
    private(set) var isLoading = false
    var errorMessage: String?

    func load(adGroupId: String, using accounts: AccountsViewModel) async {
        isLoading = true
        defer { isLoading = false }

        let scoped: ScopedClient
        do {
            scoped = try accounts.scopedClient()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return
        }

        let repository = AdGroupContentsRepository(scopedClient: scoped)
        async let ads = try? await repository.listProductAds(adGroupId: adGroupId)
        async let words = try? await repository.listKeywords(adGroupId: adGroupId)
        async let targets = try? await repository.listTargetingClauses(adGroupId: adGroupId)

        await apply(productAds: ads, keywords: words, targetingClauses: targets)
    }

    /// Folds the three (optional) results into state; sets a top-level error only
    /// when every kind failed. Separated for testability.
    func apply(
        productAds: [ProductAd]?,
        keywords: [Keyword]?,
        targetingClauses: [TargetingClause]?
    ) {
        self.productAds = productAds ?? []
        self.keywords = keywords ?? []
        self.targetingClauses = targetingClauses ?? []
        if productAds == nil, keywords == nil, targetingClauses == nil {
            errorMessage = "Couldn't load this ad group's contents."
        } else {
            errorMessage = nil
        }
    }

    var isEmpty: Bool {
        productAds.isEmpty && keywords.isEmpty && targetingClauses.isEmpty
    }
}
