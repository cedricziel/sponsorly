import AmazonAdsCore
import Foundation

extension AmazonRegion {
    /// Region-specific Login with Amazon authorize endpoint.
    ///
    /// `swift-amazon-ads` hardcodes the North America host in `authorizationURL`
    /// for every region, so we map the correct per-region endpoint here. (Token
    /// and advertising API endpoints in the package are already region-correct.)
    var lwaAuthorizeURL: URL {
        switch self {
        case .northAmerica:
            return URL(string: "https://www.amazon.com/ap/oa")!
        case .europe:
            return URL(string: "https://eu.account.amazon.com/ap/oa")!
        case .farEast:
            return URL(string: "https://apac.account.amazon.com/ap/oa")!
        @unknown default:
            return URL(string: "https://www.amazon.com/ap/oa")!
        }
    }
}
