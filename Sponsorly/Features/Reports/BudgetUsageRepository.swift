import Foundation

/// SP v3 `POST /sp/campaigns/budget/usage` response (per-campaign usage).
struct BudgetUsageResponse: Decodable {
    let success: [CampaignBudgetUsage]?
}

struct CampaignBudgetUsage: Decodable {
    let campaignId: String?
    let budget: Double?
    let budgetUsagePercent: Double?

    /// Approximate spend so far today for this campaign.
    var spentToday: Double {
        guard let budget, let budgetUsagePercent else { return 0 }
        return budget * budgetUsagePercent / 100
    }
}

/// Approximates the active profile's "today so far" spend from the synchronous
/// budget-usage endpoint (Σ budget × usage% across campaigns).
actor BudgetUsageRepository {
    private let scopedClient: ScopedClient
    private let urlSession: URLSession

    private static let contentType = "application/vnd.spcampaignbudgetusage.v1+json"
    private static let batchSize = 100

    init(scopedClient: ScopedClient, urlSession: URLSession = .shared) {
        self.scopedClient = scopedClient
        self.urlSession = urlSession
    }

    func todaySpend(campaignIds: [String]) async throws -> Double {
        guard !campaignIds.isEmpty else { return 0 }
        var total = 0.0
        for start in stride(from: 0, to: campaignIds.count, by: Self.batchSize) {
            let batch = Array(campaignIds[start ..< min(start + Self.batchSize, campaignIds.count)])
            let data = try await post(body: ["campaignIds": batch])
            let response = try JSONDecoder().decode(BudgetUsageResponse.self, from: data)
            total += (response.success ?? []).reduce(0) { $0 + $1.spentToday }
        }
        return total
    }

    private func post(body: [String: Any]) async throws -> Data {
        let url = scopedClient.baseURL.appendingPathComponent("sp/campaigns/budget/usage")
        let token = try await scopedClient.tokenProvider()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(scopedClient.clientID, forHTTPHeaderField: "Amazon-Advertising-API-ClientId")
        request.setValue(scopedClient.profileId, forHTTPHeaderField: "Amazon-Advertising-API-Scope")
        request.setValue(Self.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(Self.contentType, forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CampaignsError.invalidResponse }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw CampaignsError.http(status: http.statusCode)
        }
        return data
    }
}
