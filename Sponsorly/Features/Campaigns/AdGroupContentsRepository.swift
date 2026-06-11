import Foundation

/// Fetches an ad group's product ads, keywords, and targeting clauses for the
/// active profile, following the SP v3 direct-POST + `nextToken` paging pattern.
actor AdGroupContentsRepository {
    private let scopedClient: ScopedClient
    private let urlSession: URLSession

    private static let pageSize = 100
    private static let maxPages = 10
    private static let productAdContentType = "application/vnd.spProductAd.v3+json"
    private static let keywordContentType = "application/vnd.spKeyword.v3+json"
    private static let targetingClauseContentType = "application/vnd.spTargetingClause.v3+json"

    init(scopedClient: ScopedClient, urlSession: URLSession = .shared) {
        self.scopedClient = scopedClient
        self.urlSession = urlSession
    }

    func listProductAds(adGroupId: String) async throws -> [ProductAd] {
        try await fetchAll(
            path: "sp/productAds/list",
            contentType: Self.productAdContentType,
            adGroupId: adGroupId
        ) { data in
            let response = try JSONDecoder().decode(ProductAdListResponse.self, from: data)
            return (response.productAds ?? [], response.nextToken)
        }
    }

    func listKeywords(adGroupId: String) async throws -> [Keyword] {
        try await fetchAll(
            path: "sp/keywords/list",
            contentType: Self.keywordContentType,
            adGroupId: adGroupId
        ) { data in
            let response = try JSONDecoder().decode(KeywordListResponse.self, from: data)
            return (response.keywords ?? [], response.nextToken)
        }
    }

    func listTargetingClauses(adGroupId: String) async throws -> [TargetingClause] {
        try await fetchAll(
            path: "sp/targets/list",
            contentType: Self.targetingClauseContentType,
            adGroupId: adGroupId
        ) { data in
            let response = try JSONDecoder().decode(TargetingClauseListResponse.self, from: data)
            return (response.targetingClauses ?? [], response.nextToken)
        }
    }

    // MARK: - Paging

    private func fetchAll<T>(
        path: String,
        contentType: String,
        adGroupId: String,
        decode: (Data) throws -> ([T], String?)
    ) async throws -> [T] {
        var items: [T] = []
        var token: String?

        for _ in 0 ..< Self.maxPages {
            var body: [String: Any] = [
                "maxResults": Self.pageSize,
                "adGroupIdFilter": ["include": [adGroupId]],
            ]
            if let token { body["nextToken"] = token }
            let data = try await post(path: path, contentType: contentType, body: body)
            let (pageItems, next) = try decode(data)
            items.append(contentsOf: pageItems)
            if let next, !next.isEmpty { token = next } else { break }
        }
        return items
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
            throw CampaignsError.http(status: http.statusCode)
        }
        return data
    }
}
