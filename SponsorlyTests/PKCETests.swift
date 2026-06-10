import CryptoKit
@testable import Sponsorly
import XCTest

final class PKCETests: XCTestCase {
    func testVerifierIsURLSafeAndSizedForRFC7636() {
        let verifier = PKCE.makeCodeVerifier()
        // 32 random bytes -> 43 unpadded base64url characters.
        XCTAssertEqual(verifier.count, 43)
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        XCTAssertTrue(verifier.unicodeScalars.allSatisfy { allowed.contains($0) })
    }

    func testVerifiersAreUnique() {
        XCTAssertNotEqual(PKCE.makeCodeVerifier(), PKCE.makeCodeVerifier())
    }

    func testChallengeIsBase64URLSHA256OfVerifier() {
        let verifier = "test-verifier-value"
        let expected = PKCE.base64URLEncode(Data(SHA256.hash(data: Data(verifier.utf8))))
        let challenge = PKCE.codeChallenge(for: verifier)
        XCTAssertEqual(challenge, expected)
        XCTAssertFalse(challenge.contains("="))
        XCTAssertFalse(challenge.contains("+"))
        XCTAssertFalse(challenge.contains("/"))
    }

    func testChallengeMatchesKnownRFC7636Vector() {
        // RFC 7636 Appendix B reference vector.
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let challenge = PKCE.codeChallenge(for: verifier)
        XCTAssertEqual(challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }
}
