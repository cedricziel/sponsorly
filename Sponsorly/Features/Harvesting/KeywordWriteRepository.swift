import Foundation

/// Outcome of a single keyword/negative write.
enum WriteStatus: Hashable {
    case succeeded
    case alreadyExists
    case failed(String)
}

/// SP v3 batch write response (`{ keywords|negativeKeywords: { success:[], error:[] } }`).
private struct BatchWriteResponse: Decodable {
    let keywords: BatchResult?
    let negativeKeywords: BatchResult?
}

private struct BatchResult: Decodable {
    let success: [Item]?
    let error: [Item]?

    struct Item: Decodable {
        let index: Int?
        let errors: [ErrorDetail]?
    }

    struct ErrorDetail: Decodable {
        let errorType: String?
    }
}

/// Creates exact keywords and negative-exact keywords for harvesting.
/// Batch endpoints return per-item success/error; we map indices back to terms.
actor KeywordWriteRepository {
    private let scopedClient: ScopedClient
    private let urlSession: URLSession

    private static let keywordContentType = "application/vnd.spKeyword.v3+json"
    private static let negativeContentType = "application/vnd.spNegativeKeyword.v3+json"

    init(scopedClient: ScopedClient, urlSession: URLSession = .shared) {
        self.scopedClient = scopedClient
        self.urlSession = urlSession
    }

    /// Creates `terms` as EXACT keywords in the target ad group.
    func createExactKeywords(
        campaignId: String, adGroupId: String, terms: [String], bid: Double
    ) async throws -> [String: WriteStatus] {
        guard !terms.isEmpty else { return [:] }
        let keywords: [[String: Any]] = terms.map {
            [
                "campaignId": campaignId, "adGroupId": adGroupId, "keywordText": $0,
                "matchType": "EXACT", "state": "ENABLED", "bid": bid,
            ]
        }
        let data = try await post(
            path: "sp/keywords", contentType: Self.keywordContentType, body: ["keywords": keywords]
        )
        let response = try JSONDecoder().decode(BatchWriteResponse.self, from: data)
        return outcomes(terms: terms, result: response.keywords)
    }

    /// Creates `terms` as NEGATIVE_EXACT keywords in the (auto) campaign's ad group.
    func createNegativeExact(
        campaignId: String, adGroupId: String, terms: [String]
    ) async throws -> [String: WriteStatus] {
        guard !terms.isEmpty else { return [:] }
        let keywords: [[String: Any]] = terms.map {
            [
                "campaignId": campaignId, "adGroupId": adGroupId, "keywordText": $0,
                "matchType": "NEGATIVE_EXACT", "state": "ENABLED",
            ]
        }
        let data = try await post(
            path: "sp/negativeKeywords", contentType: Self.negativeContentType,
            body: ["negativeKeywords": keywords]
        )
        let response = try JSONDecoder().decode(BatchWriteResponse.self, from: data)
        return outcomes(terms: terms, result: response.negativeKeywords)
    }

    private func outcomes(terms: [String], result: BatchResult?) -> [String: WriteStatus] {
        var byTerm: [String: WriteStatus] = [:]
        for item in result?.success ?? [] {
            if let index = item.index, terms.indices.contains(index) { byTerm[terms[index]] = .succeeded }
        }
        for item in result?.error ?? [] {
            guard let index = item.index, terms.indices.contains(index) else { continue }
            let type = item.errors?.first?.errorType ?? ""
            byTerm[terms[index]] = type.uppercased().contains("DUPLICATE")
                ? .alreadyExists
                : .failed(type.isEmpty ? "Rejected by Amazon" : type)
        }
        for term in terms where byTerm[term] == nil {
            byTerm[term] = .failed("No response")
        }
        return byTerm
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
