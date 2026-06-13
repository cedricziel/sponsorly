import Foundation

/// Maps Amazon marketplace IDs to country codes. Manager-account linked profiles
/// carry a `marketplaceId` (not a `countryCode`), so this recovers the country —
/// and therefore the flag — for those entries.
enum Marketplace {
    /// Country code for a marketplace ID, or `nil` if unknown.
    static func countryCode(for marketplaceId: String) -> String? {
        countryCodesByMarketplaceID[marketplaceId]
    }

    private static let countryCodesByMarketplaceID: [String: String] = [
        // North America
        "ATVPDKIKX0DER": "US",
        "A2EUQ1WTGCTBG2": "CA",
        "A1AM78C64UM0Y8": "MX",
        "A2Q3Y263D00KWC": "BR",
        // Europe
        "A1F83G8C2ARO7P": "UK",
        "A1PA6795UKMFR9": "DE",
        "A13V1IB3VIYZZH": "FR",
        "APJ6JRA9NG5V4": "IT",
        "A1RKKUPIHCS9HS": "ES",
        "A1805IZSGTT6HS": "NL",
        "A2NODRKZP88ZB9": "SE",
        "A1C3SOZRARQ6R3": "PL",
        "AMEN7PMS3EDWL": "BE",
        "A33AVAJ2PDY3EV": "TR",
        "A2VIGQ35RCS4UG": "AE",
        "A17E79C6D8DWNP": "SA",
        "ARBP9OOSHTCHU": "EG",
        "A21TJRUUN4KGV": "IN",
        // Far East
        "A1VC38T7YXB528": "JP",
        "A39IBJ37TRP1C6": "AU",
        "A19VAU5U5O7RUS": "SG",
    ]
}
