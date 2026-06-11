import AmazonAdsCore
import Foundation

/// The persisted active-profile pointer: a region plus its `profileId`.
struct ActiveProfileSelection: Codable, Sendable, Equatable {
    let region: AmazonRegion
    let profileId: String
}

/// Persists the active advertising-profile selection (not a secret — a pointer).
enum ActiveProfileStore {
    static let defaultsKey = "SponsorlyActiveProfile"

    static func load(_ defaults: UserDefaults = .standard) -> ActiveProfileSelection? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(ActiveProfileSelection.self, from: data)
    }

    static func save(_ selection: ActiveProfileSelection?, into defaults: UserDefaults = .standard) {
        guard let selection, let data = try? JSONEncoder().encode(selection) else {
            defaults.removeObject(forKey: defaultsKey)
            return
        }
        defaults.set(data, forKey: defaultsKey)
    }
}
