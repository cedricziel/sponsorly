import AmazonAdsCore
import Foundation
import Observation

/// Observable auth state for the UI. Bridges the `@MainActor` view to the
/// `LWAAuthService` actor and the loopback web authenticator, and owns the
/// user-selected Amazon region.
@MainActor
@Observable
final class AuthViewModel {
    private(set) var isSignedIn = false
    private(set) var isBusy = false
    private(set) var selectedRegion: AmazonRegion
    var errorMessage: String?

    private let configErrorMessage: String?
    private let storage = KeychainTokenStorage()
    private let authenticator = LoopbackWebAuthenticator()

    private static let regionDefaultsKey = "SponsorlySelectedAmazonRegion"

    init() {
        let region = Self.loadRegion()
        selectedRegion = region
        do {
            _ = try LWAConfig.fromBundle(region: region)
            configErrorMessage = nil
        } catch {
            configErrorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    /// Restores signed-in state for the selected region (stored refresh token).
    func restore() async {
        guard let (_, service) = try? makeService() else { return }
        isSignedIn = await service.isAuthenticated()
    }

    /// Changes the active region, persists it, and refreshes signed-in state.
    func selectRegion(_ region: AmazonRegion) {
        guard region != selectedRegion else { return }
        selectedRegion = region
        UserDefaults.standard.set(region.rawValue, forKey: Self.regionDefaultsKey)
        Task { await restore() }
    }

    func signIn() async {
        guard let (config, service) = try? makeService() else {
            errorMessage = configErrorMessage ?? LWAError.missingCredentials.errorDescription
            return
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            let request = try await service.makeAuthorizationRequest()
            let callbackURL = try await authenticator.authenticate(
                authorizeURL: request.url, port: config.callbackPort)
            try await service.handleCallback(url: callbackURL, request: request)
            isSignedIn = true
        } catch LWAError.userCancelled {
            // Benign: the user dismissed the sheet. Stay signed out, no error.
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    func signOut() async {
        guard let (_, service) = try? makeService() else { return }
        do {
            try await service.signOut()
            isSignedIn = false
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func makeService() throws -> (LWAConfig, LWAAuthService) {
        let config = try LWAConfig.fromBundle(region: selectedRegion)
        return (config, LWAAuthService(config: config, storage: storage))
    }

    private static func loadRegion() -> AmazonRegion {
        if let raw = UserDefaults.standard.string(forKey: regionDefaultsKey),
           let region = AmazonRegion(rawValue: raw) {
            return region
        }
        return LWAConfig.defaultRegion
    }
}

#if DEBUG
extension AuthViewModel {
    /// Preview/testing helper to force a presentation state.
    static func previewModel(signedIn: Bool) -> AuthViewModel {
        let model = AuthViewModel()
        model.isSignedIn = signedIn
        return model
    }
}
#endif
