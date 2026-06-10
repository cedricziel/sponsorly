import Foundation
import Observation

/// Observable auth state for the UI. Bridges the `@MainActor` view to the
/// `LWAAuthService` actor and the `WebAuthenticator`.
@MainActor
@Observable
final class AuthViewModel {
    private(set) var isSignedIn = false
    private(set) var isBusy = false
    var errorMessage: String?

    private let service: LWAAuthService?
    private let config: LWAConfig?
    private let configErrorMessage: String?
    private let authenticator = WebAuthenticator()

    init() {
        do {
            let config = try LWAConfig.fromBundle()
            self.config = config
            service = LWAAuthService(config: config, storage: KeychainTokenStorage())
            configErrorMessage = nil
        } catch {
            config = nil
            service = nil
            configErrorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    /// Restores signed-in state on launch by checking for a stored refresh token.
    func restore() async {
        guard let service else { return }
        isSignedIn = await service.isAuthenticated()
    }

    func signIn() async {
        guard let service, let config else {
            errorMessage = configErrorMessage ?? LWAError.missingCredentials.errorDescription
            return
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            let request = try await service.makeAuthorizationRequest()
            let callbackURL = try await authenticator.authenticate(
                url: request.url, callbackScheme: config.callbackScheme
            )
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
        guard let service else { return }
        do {
            try await service.signOut()
            isSignedIn = false
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
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
