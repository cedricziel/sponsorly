import SafariServices
import UIKit

/// Presents the Amazon authorize page in `SFSafariViewController` and captures
/// the redirect via an in-app loopback HTTP server (RFC 8252 native-app loopback).
///
/// `ASWebAuthenticationSession` can't be used here because it only intercepts
/// custom URL schemes, not the `http://localhost` redirect Amazon whitelists.
@MainActor
final class LoopbackWebAuthenticator: NSObject, SFSafariViewControllerDelegate {
    private var server: LoopbackRedirectServer?
    private var safariViewController: SFSafariViewController?
    private var continuation: CheckedContinuation<URL, Error>?

    /// Presents `authorizeURL`, runs a loopback server on `port`, and resolves
    /// with the redirect callback URL (or throws `LWAError.userCancelled`).
    func authenticate(authorizeURL: URL, port: UInt16) async throws -> URL {
        let server = LoopbackRedirectServer(port: port)
        try await server.start()
        self.server = server

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            Task {
                do {
                    let url = try await server.waitForCallback()
                    finish(.success(url))
                } catch {
                    finish(.failure(error))
                }
            }

            guard let presenter = Self.topViewController() else {
                finish(.failure(LWAError.invalidResponse))
                return
            }
            let safari = SFSafariViewController(url: authorizeURL)
            safari.delegate = self
            safariViewController = safari
            presenter.present(safari, animated: true)
        }
    }

    /// User tapped "Done" before completing sign-in. Delivered on the main thread.
    nonisolated func safariViewControllerDidFinish(_: SFSafariViewController) {
        MainActor.assumeIsolated {
            finish(.failure(LWAError.userCancelled))
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard let continuation else { return }
        self.continuation = nil

        let server = server
        Task { await server?.stop() }
        self.server = nil

        if let safariViewController, safariViewController.presentingViewController != nil {
            safariViewController.dismiss(animated: true)
        }
        safariViewController = nil

        continuation.resume(with: result)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = (scene?.keyWindow ?? scene?.windows.first)?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
