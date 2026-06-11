import Foundation

/// A Sponsored Products product ad (an advertised ASIN/SKU) within an ad group.
struct ProductAd: Identifiable, Decodable, Hashable {
    let adId: String
    let asin: String?
    let sku: String?
    let state: String

    var id: String {
        adId
    }
}

/// A Sponsored Products keyword (manual keyword targeting).
struct Keyword: Identifiable, Decodable, Hashable {
    let keywordId: String
    let keywordText: String
    let matchType: String?
    let state: String
    let bid: Double?

    var id: String {
        keywordId
    }
}

/// A Sponsored Products targeting clause (auto targeting or product/category targets).
struct TargetingClause: Identifiable, Decodable, Hashable {
    let targetId: String
    let state: String
    let bid: Double?
    let expression: [Expression]?

    var id: String {
        targetId
    }

    /// A concise, human-readable rendering of the targeting expression.
    var displayExpression: String {
        guard let expression, !expression.isEmpty else { return "—" }
        return expression.map { expr in
            if let value = expr.value, !value.isEmpty {
                return value
            }
            return expr.type?
                .replacingOccurrences(of: "_", with: " ")
                .capitalized ?? "Target"
        }
        .joined(separator: ", ")
    }

    struct Expression: Decodable, Hashable {
        let type: String?
        let value: String?
    }
}

/// SP v3 `POST /sp/productAds/list` response envelope.
struct ProductAdListResponse: Decodable {
    let productAds: [ProductAd]?
    let nextToken: String?
}

/// SP v3 `POST /sp/keywords/list` response envelope.
struct KeywordListResponse: Decodable {
    let keywords: [Keyword]?
    let nextToken: String?
}

/// SP v3 `POST /sp/targets/list` response envelope.
struct TargetingClauseListResponse: Decodable {
    let targetingClauses: [TargetingClause]?
    let nextToken: String?
}
