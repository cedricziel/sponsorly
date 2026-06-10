import AuthenticationServices
import UIKit

/// Drives the system sign-in sheet via `ASWebAuthenticationSession` and returns the
/// redirect callback URL. Cancellation is mapped to `LWAError.userCancelled`.
@MainActor
final class WebAuthenticator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    /// Presents `url` and resolves with the callback URL on the given scheme.
    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error {
                    let cancelled = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                    continuation.resume(throwing: cancelled ? LWAError.userCancelled : error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: LWAError.invalidResponse)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            // Use the shared browser session so an existing Amazon login can carry over.
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: LWAError.invalidResponse)
            }
        }
    }

    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let window = Self.activeWindow() else {
            // The system only queries this while presenting, i.e. with a
            // foreground window on screen, so this is an unreachable state.
            preconditionFailure("No active window scene to present over")
        }
        return window
    }

    private static func activeWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.keyWindow ?? scene?.windows.first
    }
}
