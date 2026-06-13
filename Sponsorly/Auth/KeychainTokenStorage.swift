import AmazonAdsCore
import Foundation
import Security

/// `TokenStorageProtocol` backed by the iOS Keychain.
///
/// Items are stored as generic passwords, keyed per `AmazonRegion`. Keychain calls
/// are synchronous and thread-safe, so this is a value type with no mutable state.
struct KeychainTokenStorage: TokenStorageProtocol {
    private let service: String

    init(service: String = "com.cedricziel.sponsorly.tokens") {
        self.service = service
    }

    func save(_ value: String, for key: String, region: AmazonRegion) async throws {
        let data = Data(value.utf8)
        let match = baseQuery(for: key, region: region)

        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(match as CFDictionary, update as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var insert = match
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw TokenStorageError.storageError("SecItemAdd failed: \(addStatus)")
            }
        default:
            throw TokenStorageError.storageError("SecItemUpdate failed: \(updateStatus)")
        }
    }

    func retrieve(for key: String, region: AmazonRegion) async throws -> String {
        var query = baseQuery(for: key, region: region)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let value = String(data: data, encoding: .utf8)
            else {
                throw TokenStorageError.invalidData
            }
            return value
        case errSecItemNotFound:
            throw TokenStorageError.notFound
        default:
            throw TokenStorageError.storageError("SecItemCopyMatching failed: \(status)")
        }
    }

    func exists(for key: String, region: AmazonRegion) async -> Bool {
        var query = baseQuery(for: key, region: region)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    func delete(for key: String, region: AmazonRegion) async throws {
        let status = SecItemDelete(baseQuery(for: key, region: region) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TokenStorageError.storageError("SecItemDelete failed: \(status)")
        }
    }

    func deleteAll(for region: AmazonRegion) async throws {
        let keys = [
            TokenStorageKey.accessToken,
            TokenStorageKey.refreshToken,
            TokenStorageKey.tokenExpiry,
            TokenStorageKey.profileId,
        ]
        for key in keys {
            try await delete(for: key, region: region)
        }
    }

    // MARK: - Helpers

    private func account(for key: String, region: AmazonRegion) -> String {
        "\(region.rawValue)_\(key)"
    }

    private func baseQuery(for key: String, region: AmazonRegion) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: key, region: region),
        ]
    }
}
