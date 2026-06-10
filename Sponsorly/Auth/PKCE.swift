import CryptoKit
import Foundation

/// Helpers for OAuth 2.0 Proof Key for Code Exchange (RFC 7636), S256 method.
enum PKCE {
    /// A high-entropy, URL-safe code verifier (43 characters from 32 random bytes).
    static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "Unable to generate secure random bytes")
        return base64URLEncode(Data(bytes))
    }

    /// The S256 challenge derived from a verifier: BASE64URL(SHA256(verifier)).
    static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(digest))
    }

    /// Base64URL encoding without padding (RFC 4648 §5).
    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
