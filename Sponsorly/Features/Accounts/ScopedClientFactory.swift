import AmazonAdsCore
import Foundation

enum ScopedClientError: LocalizedError {
    case noActiveProfile

    var errorDescription: String? {
        switch self {
        case .noActiveProfile:
            return "Select an advertising profile before loading data."
        }
    }
}

/// Everything a data feature needs to make profile-scoped Amazon Ads calls for
/// the active profile: the region base URL, the `client_id`, the `profileId`
/// scope, a token provider, and a ready `AuthenticatedTransport` (for callers
/// that prefer the generated clients).
struct ScopedClient: Sendable {
    let transport: AuthenticatedTransport
    let baseURL: URL
    let region: AmazonRegion
    let profileId: String
    let clientID: String
    let tokenProvider: @Sendable () async throws -> String
}

enum ActiveProfileClientFactory {
    /// Builds a `ScopedClient` for the active selection.
    /// - Parameter tokenProvider: yields the access-token provider for a region.
    /// - Throws: `ScopedClientError.noActiveProfile` when nothing is selected.
    static func make(
        selection: ActiveProfileSelection?,
        clientID: String,
        tokenProvider: (AmazonRegion) throws -> @Sendable () async throws -> String
    ) throws -> ScopedClient {
        guard let selection else { throw ScopedClientError.noActiveProfile }
        let provider = try tokenProvider(selection.region)
        let transport = AuthenticatedTransport(
            tokenProvider: provider,
            clientId: clientID,
            profileId: selection.profileId
        )
        return ScopedClient(
            transport: transport,
            baseURL: selection.region.advertisingAPIBaseURL,
            region: selection.region,
            profileId: selection.profileId,
            clientID: clientID,
            tokenProvider: provider
        )
    }
}
