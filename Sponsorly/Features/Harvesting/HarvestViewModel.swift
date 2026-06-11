import Foundation
import Observation

/// The outcome of one write, for the results screen.
struct WriteOutcome: Identifiable, Hashable {
    enum Kind: Hashable { case keyword, negative }
    let term: String
    let kind: Kind
    let status: WriteStatus
    var id: String {
        "\(kind)-\(term)"
    }
}

/// Drives the harvesting wizard for a (source/auto) campaign: load the
/// search-term report, bucket it by tunable criteria, let the user pick what to
/// graduate/negate and where, then perform the writes.
@MainActor
@Observable
final class HarvestViewModel {
    enum Step: Hashable { case criteria, review, results }

    let sourceCampaign: Campaign
    private let accounts: AccountsViewModel
    private let cache = ReportCache()

    var step: Step = .criteria
    var criteria = HarvestCriteria()
    private(set) var allTerms: [SearchTerm] = []
    private(set) var isLoading = false
    var errorMessage: String?
    var errorResponseBody: String?

    // Target (manual exact) selection.
    private(set) var manualCampaigns: [Campaign] = []
    private(set) var targetAdGroups: [AdGroup] = []
    var targetCampaignId: String?
    var targetAdGroupId: String?
    var bid = 0.75

    // What's checked.
    var selectedGraduate: Set<String> = []
    var selectedNegate: Set<String> = []

    // Writing.
    private(set) var isWriting = false
    private(set) var results: [WriteOutcome] = []

    init(campaign: Campaign, accounts: AccountsViewModel) {
        sourceCampaign = campaign
        self.accounts = accounts
    }

    var graduateTerms: [SearchTerm] {
        HarvestScorer.graduate(allTerms, criteria)
    }

    var negateTerms: [SearchTerm] {
        HarvestScorer.negate(allTerms, criteria)
    }

    var selectedGraduateCount: Int {
        selectedGraduate.count
    }

    var selectedNegateOnlyCount: Int {
        selectedNegate.count
    }

    /// Every selected term gets negated in the source (graduated ones too).
    var totalNegateCount: Int {
        selectedGraduate.union(selectedNegate).count
    }

    var canConfirm: Bool {
        !selectedGraduate.isEmpty || !selectedNegate.isEmpty
    }

    func loadReport() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        guard let scoped = try? accounts.scopedClient() else {
            errorMessage = "Select an advertising profile first."
            return
        }
        let (start, end) = SpendOverviewViewModel.reportRange()
        let cacheKey = ReportCacheKey(
            profileId: scoped.profileId, reportTypeId: "spSearchTerm",
            startDate: start, endDate: end, timeUnit: "SUMMARY"
        )
        // The report covers "30 days ending yesterday" (immutable) and spans the
        // whole profile, so a cached copy is reused across harvests of any campaign.
        if let cached: [SearchTermReportRow] = await cache.load(cacheKey, as: SearchTermReportRow.self) {
            apply(rows: cached)
            return
        }
        let request = ReportRequest.spSearchTerm(name: "harvest", startDate: start, endDate: end)
        do {
            let rows: [SearchTermReportRow] = try await ReportingRepository(scopedClient: scoped)
                .fetchRows(request)
            await cache.save(rows, for: cacheKey, ttl: ReportCache.immutableTTL)
            apply(rows: rows)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            errorResponseBody = apiResponseBody(from: error)
        }
    }

    /// Filters the profile-wide report to this campaign and pre-selects the buckets.
    private func apply(rows: [SearchTermReportRow]) {
        let campaignRows = rows.filter { $0.campaignId == sourceCampaign.campaignId }
        allTerms = HarvestScorer.searchTerms(from: campaignRows)
        selectedGraduate = Set(graduateTerms.map(\.id))
        selectedNegate = Set(negateTerms.map(\.id))
    }

    func loadTargets() async {
        guard let scoped = try? accounts.scopedClient() else { return }
        if let result = try? await CampaignsRepository(scopedClient: scoped).listCampaigns() {
            manualCampaigns = result.campaigns.filter { $0.targetingType?.uppercased() == "MANUAL" }
        }
    }

    func loadAdGroups(for campaignId: String) async {
        targetAdGroups = []
        targetAdGroupId = nil
        guard let scoped = try? accounts.scopedClient() else { return }
        if let result = try? await CampaignsRepository(scopedClient: scoped).listAdGroups(campaignId: campaignId) {
            targetAdGroups = result.adGroups
        }
    }

    func apply() async {
        guard let targetCampaignId, let targetAdGroupId else { return }
        guard let scoped = try? accounts.scopedClient() else {
            errorMessage = "Select an advertising profile first."
            return
        }
        isWriting = true
        defer { isWriting = false }
        let repository = KeywordWriteRepository(scopedClient: scoped)

        var outcomes: [WriteOutcome] = []

        // 1. Graduate the checked winners → exact keywords in the target ad group.
        let graduating = graduateTerms.filter { selectedGraduate.contains($0.id) }
        if !graduating.isEmpty,
           let statuses = try? await repository.createExactKeywords(
               campaignId: targetCampaignId, adGroupId: targetAdGroupId,
               terms: graduating.map(\.term), bid: bid
           )
        {
            outcomes += Self.outcomes(statuses, kind: .keyword)
        }

        // 2. Negate every selected term in its source ad group (graduated + negate-only).
        let negating = Self.negateTargets(
            graduating: graduating,
            negateSelected: negateTerms.filter { selectedNegate.contains($0.id) }
        )
        for (adGroupId, terms) in Dictionary(grouping: negating, by: { $0.adGroupId ?? "" })
            where !adGroupId.isEmpty
        {
            guard let campaignId = terms.first?.campaignId else { continue }
            if let statuses = try? await repository.createNegativeExact(
                campaignId: campaignId, adGroupId: adGroupId, terms: terms.map(\.term)
            ) {
                outcomes += Self.outcomes(statuses, kind: .negative)
            }
        }

        results = outcomes
        step = .results
    }

    // MARK: - Pure helpers (testable)

    /// Every graduated term is *also* negated in its source — that's the point of
    /// harvesting (stop the auto and manual double-bidding on the same query).
    nonisolated static func negateTargets(
        graduating: [SearchTerm], negateSelected: [SearchTerm]
    ) -> [SearchTerm] {
        graduating + negateSelected
    }

    nonisolated static func outcomes(
        _ statuses: [String: WriteStatus], kind: WriteOutcome.Kind
    ) -> [WriteOutcome] {
        statuses
            .map { WriteOutcome(term: $0.key, kind: kind, status: $0.value) }
            .sorted { $0.term < $1.term }
    }
}

#if DEBUG
    extension HarvestViewModel {
        static func preview(step: Step = .review) -> HarvestViewModel {
            let campaign = Campaign(
                campaignId: "1", name: "SP | Demo | Auto", state: "ENABLED",
                targetingType: "AUTO", budget: nil
            )
            let model = HarvestViewModel(campaign: campaign, accounts: .previewModel())
            model.allTerms = [
                SearchTerm(term: "running shoes", campaignId: "1", adGroupId: "ag",
                           clicks: 20, spend: 10, sales: 50, orders: 3),
                SearchTerm(term: "trail runners", campaignId: "1", adGroupId: "ag",
                           clicks: 15, spend: 8, sales: 36, orders: 2),
                SearchTerm(term: "free shoes", campaignId: "1", adGroupId: "ag",
                           clicks: 14, spend: 9, sales: 0, orders: 0),
            ]
            model.selectedGraduate = Set(model.graduateTerms.map(\.id))
            model.selectedNegate = Set(model.negateTerms.map(\.id))
            model.results = [
                WriteOutcome(term: "running shoes", kind: .keyword, status: .succeeded),
                WriteOutcome(term: "free shoes", kind: .negative, status: .succeeded),
            ]
            model.step = step
            return model
        }
    }
#endif
