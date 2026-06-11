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

    var step: Step = .criteria
    var criteria = HarvestCriteria()
    private(set) var allTerms: [SearchTerm] = []
    private(set) var isLoading = false
    var errorMessage: String?

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
        let request = ReportRequest.spSearchTerm(
            name: "harvest", startDate: start, endDate: end, campaignId: sourceCampaign.campaignId
        )
        do {
            let rows: [SearchTermReportRow] = try await ReportingRepository(scopedClient: scoped)
                .fetchRows(request)
            allTerms = HarvestScorer.searchTerms(from: rows)
            selectedGraduate = Set(graduateTerms.map(\.id))
            selectedNegate = Set(negateTerms.map(\.id))
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
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
            outcomes += statuses.map { WriteOutcome(term: $0.key, kind: .keyword, status: $0.value) }
        }

        // 2. Negate every selected term in its source ad group (graduated + negate-only).
        let negating = graduating + negateTerms.filter { selectedNegate.contains($0.id) }
        for (adGroupId, terms) in Dictionary(grouping: negating, by: { $0.adGroupId ?? "" })
            where !adGroupId.isEmpty
        {
            guard let campaignId = terms.first?.campaignId else { continue }
            if let statuses = try? await repository.createNegativeExact(
                campaignId: campaignId, adGroupId: adGroupId, terms: terms.map(\.term)
            ) {
                outcomes += statuses.map { WriteOutcome(term: $0.key, kind: .negative, status: $0.value) }
            }
        }

        results = outcomes
        step = .results
    }
}
