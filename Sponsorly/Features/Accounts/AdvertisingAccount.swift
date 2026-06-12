import AmazonAdsCore
import Foundation

/// A selectable advertising profile, flattened from the package's profile and
/// manager-account types and tagged with the region it came from. The `profileId`
/// is the unit that scopes Amazon Ads API calls.
struct AdvertisingProfile: Identifiable, Hashable {
    let profileId: String
    let region: AmazonRegion
    let accountName: String
    let countryCode: String?
    let currencyCode: String?
    let accountType: String?
    let managerAccountName: String?

    /// Stable identity across regions (the same profileId can exist per region).
    var id: String {
        "\(region.rawValue):\(profileId)"
    }
}

/// The aggregated result of discovering accounts across connected regions:
/// the flattened, deduped profiles plus any per-region failures.
struct ConnectedAccounts {
    var profiles: [AdvertisingProfile] = []
    /// Region → human-readable error for regions whose fetch failed.
    var failures: [AmazonRegion: String] = [:]

    var isEmpty: Bool {
        profiles.isEmpty && failures.isEmpty
    }
}

extension AdvertisingProfile {
    /// A standalone profile from `GET /v2/profiles`.
    init(profile: AmazonProfile, region: AmazonRegion) {
        self.init(
            profileId: profile.profileId,
            region: region,
            accountName: profile.accountInfo.name,
            countryCode: profile.countryCode,
            currencyCode: profile.currencyCode,
            accountType: profile.accountInfo.type,
            managerAccountName: nil
        )
    }

    /// A profile linked under a manager account from `GET /managerAccounts`.
    /// The country (and thus flag) is recovered from the `marketplaceId`.
    init(linked: AmazonLinkedAccount, managerName: String, region: AmazonRegion) {
        self.init(
            profileId: linked.profileId,
            region: region,
            accountName: linked.accountName,
            countryCode: Marketplace.countryCode(for: linked.marketplaceId),
            currencyCode: nil,
            accountType: nil,
            managerAccountName: managerName
        )
    }
}

enum AdvertisingAccountAggregator {
    /// Flattens profiles + manager accounts for one region into leaf profiles.
    static func profiles(
        profiles: [AmazonProfile],
        managerAccounts: [AmazonManagerAccount],
        region: AmazonRegion
    ) -> [AdvertisingProfile] {
        let standalone = profiles.map { AdvertisingProfile(profile: $0, region: region) }
        let linked = managerAccounts.flatMap { manager in
            manager.linkedAccounts.map {
                AdvertisingProfile(linked: $0, managerName: manager.managerAccountName, region: region)
            }
        }
        return dedupe(standalone + linked)
    }

    /// Dedupes by stable `id`, preferring the entry that carries a manager-account
    /// name, then the one with the richer (country/type) standalone metadata.
    static func dedupe(_ items: [AdvertisingProfile]) -> [AdvertisingProfile] {
        var byID: [String: AdvertisingProfile] = [:]
        for item in items {
            guard let existing = byID[item.id] else {
                byID[item.id] = item
                continue
            }
            byID[item.id] = merge(existing, item)
        }
        return byID.values.sorted {
            $0.accountName.localizedCaseInsensitiveCompare($1.accountName) == .orderedAscending
        }
    }

    private static func merge(_ lhs: AdvertisingProfile, _ rhs: AdvertisingProfile) -> AdvertisingProfile {
        AdvertisingProfile(
            profileId: lhs.profileId,
            region: lhs.region,
            accountName: lhs.accountName.isEmpty ? rhs.accountName : lhs.accountName,
            countryCode: lhs.countryCode ?? rhs.countryCode,
            currencyCode: lhs.currencyCode ?? rhs.currencyCode,
            accountType: lhs.accountType ?? rhs.accountType,
            managerAccountName: lhs.managerAccountName ?? rhs.managerAccountName
        )
    }
}
