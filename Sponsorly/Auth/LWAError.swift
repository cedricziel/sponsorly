import AmazonAdsCore
import Foundation

/// Errors surfaced by the Login with Amazon flow.
enum LWAError: LocalizedError {
    /// The LWA client id or secret was not provided at build time.
    case missingCredentials
    /// The `state` returned on the redirect did not match the value we sent (possible CSRF).
    case stateMismatch
    /// The user (or Amazon) denied authorization; carries the OAuth error description.
    case authorizationDenied(String)
    /// The redirect did not contain an authorization `code`.
    case missingAuthorizationCode
    /// Amazon returned a structured OAuth error from the token endpoint.
    case oauth(AmazonOAuthError)
    /// The token endpoint returned an unexpected (non-JSON / non-2xx) response.
    case invalidResponse
    /// No stored refresh token — the user is signed out.
    case notAuthenticated
    /// The user dismissed the sign-in sheet before completing it.
    case userCancelled

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            "Amazon credentials are not configured. Add LWA_CLIENT_ID and "
                + "LWA_CLIENT_SECRET to Secrets.xcconfig and regenerate the project."
        case .stateMismatch:
            "Sign-in could not be verified (state mismatch). Please try again."
        case let .authorizationDenied(detail):
            "Authorization was denied: \(detail)"
        case .missingAuthorizationCode:
            "Amazon did not return an authorization code."
        case let .oauth(error):
            error.errorDescription
        case .invalidResponse:
            "Received an unexpected response from Amazon."
        case .notAuthenticated:
            "You are not signed in to Amazon."
        case .userCancelled:
            "Sign-in was cancelled."
        }
    }
}
