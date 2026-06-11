import Foundation

enum CampaignsError: LocalizedError {
    case invalidResponse
    case http(status: Int, body: String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Received an unexpected response from Amazon."
        case let .http(status, _):
            "Amazon returned HTTP \(status)."
        }
    }
}

/// A page-collected result that flags whether the page cap truncated the list.
struct CampaignList {
    let campaigns: [Campaign]
    let truncated: Bool
}

struct AdGroupList {
    let adGroups: [AdGroup]
    let truncated: Bool
}

/// Fetches Sponsored Products campaigns and ad groups for the active profile.
///
/// SP v3 list endpoints are `POST .../list` with a vendored content type and
/// `nextToken` paging; we set the headers directly and decode small models.
actor CampaignsRepository {
    private let scopedClient: ScopedClient
    private let urlSession: URLSession

    private static let pageSize = 100
    private static let maxPages = 10
    private static let campaignContentType = "application/vnd.spCampaign.v3+json"
    private static let adGroupContentType = "application/vnd.spAdGroup.v3+json"

    init(scopedClient: ScopedClient, urlSession: URLSession = .shared) {
        self.scopedClient = scopedClient
        self.urlSession = urlSession
    }

    func listCampaigns() async throws -> CampaignList {
        let (campaigns, truncated) = try await fetchAll(
            path: "sp/campaigns/list",
            contentType: Self.campaignContentType,
            baseBody: ["maxResults": Self.pageSize, "stateFilter": ["include": ["ENABLED", "PAUSED"]]]
        ) { data in
            let response = try JSONDecoder().decode(CampaignListResponse.self, from: data)
            return (response.campaigns ?? [], response.nextToken)
        }
        return CampaignList(campaigns: campaigns, truncated: truncated)
    }

    func listAdGroups(campaignId: String) async throws -> AdGroupList {
        let (adGroups, truncated) = try await fetchAll(
            path: "sp/adGroups/list",
            contentType: Self.adGroupContentType,
            baseBody: [
                "maxResults": Self.pageSize,
                "stateFilter": ["include": ["ENABLED", "PAUSED"]],
                "campaignIdFilter": ["include": [campaignId]],
            ]
        ) { data in
            let response = try JSONDecoder().decode(AdGroupListResponse.self, from: data)
            return (response.adGroups ?? [], response.nextToken)
        }
        return AdGroupList(adGroups: adGroups, truncated: truncated)
    }

    // MARK: - Paging

    private func fetchAll<T>(
        path: String,
        contentType: String,
        baseBody: [String: Any],
        decode: (Data) throws -> ([T], String?)
    ) async throws -> ([T], Bool) {
        var items: [T] = []
        var token: String?
        var truncated = false

        for page in 0 ..< Self.maxPages {
            var body = baseBody
            if let token { body["nextToken"] = token }
            let data = try await post(path: path, contentType: contentType, body: body)
            let (pageItems, next) = try decode(data)
            items.append(contentsOf: pageItems)

            if let next, !next.isEmpty {
                token = next
                if page == Self.maxPages - 1 { truncated = true }
            } else {
                break
            }
        }
        return (items, truncated)
    }

    private func post(path: String, contentType: String, body: [String: Any]) async throws -> Data {
        let url = scopedClient.baseURL.appendingPathComponent(path)
        let token = try await scopedClient.tokenProvider()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(scopedClient.clientID, forHTTPHeaderField: "Amazon-Advertising-API-ClientId")
        request.setValue(scopedClient.profileId, forHTTPHeaderField: "Amazon-Advertising-API-Scope")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(contentType, forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CampaignsError.invalidResponse }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw CampaignsError.http(status: http.statusCode, body: httpResponseBody(data))
        }
        return data
    }
}
