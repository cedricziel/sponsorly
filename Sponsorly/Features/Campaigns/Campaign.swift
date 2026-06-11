import Foundation

/// A Sponsored Products campaign (subset of the SP v3 management fields).
struct Campaign: Identifiable, Sendable, Decodable, Hashable {
    let campaignId: String
    let name: String
    let state: String
    let targetingType: String?
    let budget: Budget?

    var id: String { campaignId }

    struct Budget: Sendable, Decodable, Hashable {
        let budget: Double?
        let budgetType: String?
    }
}

/// A Sponsored Products ad group (subset of the SP v3 fields).
struct AdGroup: Identifiable, Sendable, Decodable, Hashable {
    let adGroupId: String
    let name: String
    let state: String
    let defaultBid: Double?

    var id: String { adGroupId }
}

/// SP v3 `POST /sp/campaigns/list` response envelope.
struct CampaignListResponse: Decodable {
    let campaigns: [Campaign]?
    let nextToken: String?
}

/// SP v3 `POST /sp/adGroups/list` response envelope.
struct AdGroupListResponse: Decodable {
    let adGroups: [AdGroup]?
    let nextToken: String?
}
