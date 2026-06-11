import AmazonAdsCore
import Foundation
import Observation

/// Observable auth state for the UI. Each Amazon region (NA/EU/FE) is connected
/// independently; sign in/out operate per region. Bridges the `@MainActor` view
/// to the `LWAAuthService` actor and the loopback web authenticator.
@MainActor
@Observable
final class AuthViewModel {
    private(set) var connectedRegions: Set<AmazonRegion> = []
    private(set) var busyRegion: AmazonRegion?
    var errorMessage: String?

    private let configErrorMessage: String?
    private let storage = KeychainTokenStorage()
    private let authenticator = LoopbackWebAuthenticator()

    init() {
        do {
            // Credentials are region-independent; probe once.
            _ = try LWAConfig.fromBundle(region: LWAConfig.defaultRegion)
            configErrorMessage = nil
        } catch {
            configErrorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    func isConnected(_ region: AmazonRegion) -> Bool { connectedRegions.contains(region) }
    func isBusy(_ region: AmazonRegion) -> Bool { busyRegion == region }

    /// Restores per-region connection state from stored refresh tokens.
    func restore() async {
        var connected: Set<AmazonRegion> = []
        for region in AmazonRegion.allCases {
            guard let (_, service) = try? makeService(region: region) else { continue }
            if await service.isAuthenticated() {
                connected.insert(region)
            }
        }
        connectedRegions = connected
    }

    func signIn(region: AmazonRegion) async {
        guard let (config, service) = try? makeService(region: region) else {
            errorMessage = configErrorMessage ?? LWAError.missingCredentials.errorDescription
            return
        }
        busyRegion = region
        errorMessage = nil
        defer { busyRegion = nil }

        do {
            let request = try await service.makeAuthorizationRequest()
            let callbackURL = try await authenticator.authenticate(
                authorizeURL: request.url, port: config.callbackPort)
            try await service.handleCallback(url: callbackURL, request: request)
            connectedRegions.insert(region)
        } catch LWAError.userCancelled {
            // Benign: the user dismissed the sheet. No change, no error.
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    func signOut(region: AmazonRegion) async {
        guard let (_, service) = try? makeService(region: region) else { return }
        do {
            try await service.signOut()
            connectedRegions.remove(region)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    /// A token provider for a connected region — used by the accounts layer to
    /// build region-scoped API clients.
    func tokenProvider(for region: AmazonRegion) throws -> @Sendable () async throws -> String {
        let (_, service) = try makeService(region: region)
        return service.tokenProvider()
    }

    private func makeService(region: AmazonRegion) throws -> (LWAConfig, LWAAuthService) {
        let config = try LWAConfig.fromBundle(region: region)
        return (config, LWAAuthService(config: config, storage: storage))
    }
}

#if DEBUG
extension AuthViewModel {
    /// Preview/testing helper to force connection state.
    static func previewModel(connected: Set<AmazonRegion>) -> AuthViewModel {
        let model = AuthViewModel()
        model.connectedRegions = connected
        return model
    }
}
#endif
