import AmazonAdsCore
import Foundation

/// Static configuration for the Login with Amazon flow.
///
/// Client credentials are injected at build time from `Secrets.xcconfig` into the
/// app's Info.plist (see `project.yml`) and read here at runtime.
struct LWAConfig {
    let clientID: String
    let clientSecret: String
    let region: AmazonRegion
    let redirectURI: String
    let callbackScheme: String
    let scopes: [String]

    /// Custom URL scheme registered in `CFBundleURLTypes` and as an Allowed Return
    /// URL on the LWA Security Profile. Amazon's documented native format is
    /// `amzn-<bundleID>`.
    static let defaultCallbackScheme = "amzn-com.cedricziel.sponsorly"
    static let defaultRedirectURI = "amzn-com.cedricziel.sponsorly://oauth"
    static let defaultScopes = ["profile", "advertising::campaign_management"]
    /// Region selection UI is out of scope for now; default to Europe.
    static let defaultRegion: AmazonRegion = .europe

    /// Builds the configuration from the app bundle's Info dictionary.
    /// - Throws: `LWAError.missingCredentials` when either credential is absent or blank.
    static func fromBundle(
        _ bundle: Bundle = .main,
        region: AmazonRegion = defaultRegion
    ) throws -> LWAConfig {
        let clientID = string(forKey: "LWAClientID", in: bundle)
        let clientSecret = string(forKey: "LWAClientSecret", in: bundle)
        guard !clientID.isEmpty, !clientSecret.isEmpty else {
            throw LWAError.missingCredentials
        }
        return LWAConfig(
            clientID: clientID,
            clientSecret: clientSecret,
            region: region,
            redirectURI: defaultRedirectURI,
            callbackScheme: defaultCallbackScheme,
            scopes: defaultScopes
        )
    }

    private static func string(forKey key: String, in bundle: Bundle) -> String {
        let value = bundle.object(forInfoDictionaryKey: key) as? String ?? ""
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
