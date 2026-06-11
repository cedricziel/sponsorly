import AmazonAdsCore
import Foundation

enum AccountsError: LocalizedError {
    case invalidResponse
    case http(status: Int, body: String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Received an unexpected response from Amazon."
        case let .http(status, _): "Amazon returned HTTP \(status)."
        }
    }
}

/// Discovers advertising profiles and manager accounts across connected regions.
///
/// Fetches are direct `GET` requests (Bearer + ClientId headers) decoded into the
/// package's `AmazonProfile` / `AmazonManagerAccount` types. Each region is fetched
/// independently; a failing region is reported without failing the others.
actor AccountsRepository {
    private let clientID: String
    private let urlSession: URLSession

    init(clientID: String, urlSession: URLSession = .shared) {
        self.clientID = clientID
        self.urlSession = urlSession
    }

    /// Fetches and aggregates accounts for every provided region in parallel.
    /// - Parameter providers: region → access-token provider for that region.
    func discover(
        _ providers: [AmazonRegion: @Sendable () async throws -> String]
    ) async -> ConnectedAccounts {
        await withTaskGroup(
            of: (AmazonRegion, Result<[AdvertisingProfile], Error>).self
        ) { group in
            for (region, provider) in providers {
                group.addTask {
                    do {
                        let profiles = try await self.fetchProfiles(region: region, provider: provider)
                        return (region, .success(profiles))
                    } catch {
                        return (region, .failure(error))
                    }
                }
            }

            var result = ConnectedAccounts()
            for await (region, outcome) in group {
                switch outcome {
                case let .success(profiles):
                    result.profiles.append(contentsOf: profiles)
                case let .failure(error):
                    result.failures[region] = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                }
            }
            result.profiles = AdvertisingAccountAggregator.dedupe(result.profiles)
            return result
        }
    }

    private func fetchProfiles(
        region: AmazonRegion,
        provider: @Sendable () async throws -> String
    ) async throws -> [AdvertisingProfile] {
        let token = try await provider()
        async let profiles = getProfiles(region: region, token: token)
        async let managers = getManagerAccounts(region: region, token: token)
        return try await AdvertisingAccountAggregator.profiles(
            profiles: profiles, managerAccounts: managers, region: region
        )
    }

    private func getProfiles(region: AmazonRegion, token: String) async throws -> [AmazonProfile] {
        let url = region.advertisingAPIBaseURL.appendingPathComponent("v2/profiles")
        let (data, response) = try await get(url, token: token)
        try Self.ensureSuccess(response, data: data)
        return try JSONDecoder().decode([AmazonProfile].self, from: data)
    }

    private func getManagerAccounts(
        region: AmazonRegion, token: String
    ) async throws -> [AmazonManagerAccount] {
        let url = region.advertisingAPIBaseURL.appendingPathComponent("managerAccounts")
        let (data, response) = try await get(url, token: token)
        // Not all accounts have manager accounts; treat 404/empty as "none".
        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            return []
        }
        try Self.ensureSuccess(response, data: data)
        guard !data.isEmpty else { return [] }
        return try JSONDecoder().decode(AmazonManagerAccountsResponse.self, from: data).managerAccounts
    }

    private func get(_ url: URL, token: String) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientID, forHTTPHeaderField: "Amazon-Advertising-API-ClientId")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await urlSession.data(for: request)
    }

    private static func ensureSuccess(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw AccountsError.invalidResponse }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw AccountsError.http(status: http.statusCode, body: httpResponseBody(data))
        }
    }
}
