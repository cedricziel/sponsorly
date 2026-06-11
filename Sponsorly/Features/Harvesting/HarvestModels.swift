import Foundation

/// User-tunable thresholds for bucketing search terms.
struct HarvestCriteria: Hashable {
    var minOrders = 2
    var minClicks = 10
    var targetACOS = 0.25
    var negateMinClicks = 10
}

/// A customer search term with its performance, normalized from a report row.
struct SearchTerm: Identifiable, Hashable {
    let term: String
    let campaignId: String
    let adGroupId: String?
    let clicks: Int
    let spend: Double
    let sales: Double
    let orders: Int

    var id: String {
        term
    }

    var acos: Double? {
        sales > 0 ? spend / sales : nil
    }

    /// Auto-target search terms are frequently product ASINs (e.g. "b07ndcwkjw"),
    /// not typed queries. ASINs graduate/negate as product *targets*, not keywords.
    var isASIN: Bool {
        term.range(of: #"^[bB]0[a-zA-Z0-9]{8}$"#, options: .regularExpression) != nil
    }
}

enum HarvestScorer {
    /// Normalizes report rows into search terms (drops rows missing a term/campaign).
    static func searchTerms(from rows: [SearchTermReportRow]) -> [SearchTerm] {
        rows.compactMap { row in
            guard let term = row.searchTerm, !term.isEmpty, let campaignId = row.campaignId else {
                return nil
            }
            return SearchTerm(
                term: term, campaignId: campaignId, adGroupId: row.adGroupId,
                clicks: row.clicks ?? 0, spend: row.cost ?? 0,
                sales: row.sales30d ?? 0, orders: row.purchases30d ?? 0
            )
        }
    }

    /// Winners: enough orders + clicks and efficient enough to promote to exact.
    static func graduate(_ terms: [SearchTerm], _ criteria: HarvestCriteria) -> [SearchTerm] {
        terms
            .filter { term in
                term.orders >= criteria.minOrders
                    && term.clicks >= criteria.minClicks
                    && (term.acos.map { $0 <= criteria.targetACOS } ?? false)
            }
            .sorted { $0.spend > $1.spend }
    }

    /// Wasteful: enough clicks but no orders — negate in the source campaign.
    static func negate(_ terms: [SearchTerm], _ criteria: HarvestCriteria) -> [SearchTerm] {
        terms
            .filter { $0.clicks >= criteria.negateMinClicks && $0.orders == 0 }
            .sorted { $0.spend > $1.spend }
    }
}
