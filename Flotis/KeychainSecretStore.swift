import Foundation
import Security

protocol KeychainSecretStoring: AnyObject {
    @discardableResult
    func save(secret: String, for reference: String) -> Bool
    func load(for reference: String) -> String?
    @discardableResult
    func delete(for reference: String) -> Bool
}

final class KeychainSecretStore: KeychainSecretStoring {
    static let shared = KeychainSecretStore()

    // This value must remain stable across app versions so scoped items remain visible.
    static let service = "com.flotis.Flotis.speech-provider-api-key"

    private(set) var lastStatus: OSStatus = errSecSuccess

    private init() {}

    @discardableResult
    func save(secret: String, for reference: String) -> Bool {
        let normalizedSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSecret.isEmpty,
              !normalizedReference.isEmpty,
              let data = normalizedSecret.data(using: .utf8) else {
            lastStatus = errSecParam
            return false
        }

        let query = scopedQuery(for: normalizedReference)
        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        if updateStatus == errSecSuccess {
            lastStatus = updateStatus
            return true
        }

        guard updateStatus == errSecItemNotFound else {
            lastStatus = updateStatus
            return false
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        lastStatus = addStatus
        return addStatus == errSecSuccess
    }

    func load(for reference: String) -> String? {
        let normalizedReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedReference.isEmpty else {
            lastStatus = errSecParam
            return nil
        }

        if let scoped = loadScoped(for: normalizedReference) {
            return scoped
        }

        // v1 stored class+account without a service. Enumerate first and only select
        // items whose service is absent/empty, so a broad query never deletes a new item.
        guard let legacy = legacyItems(for: normalizedReference).first,
              let secret = legacy.secret else {
            return nil
        }

        // Write the scoped replacement first. Any cleanup uses the exact persistent
        // reference returned for the legacy item, never class+account alone.
        guard let persistentReference = legacy.persistentReference else {
            lastStatus = errSecInvalidItemRef
            return secret
        }
        guard save(secret: secret, for: normalizedReference) else {
            return secret
        }
        guard delete(persistentReference: persistentReference) else {
            // Keep the legacy item authoritative so a later load can retry migration.
            // Removing the newly scoped copy avoids creating an unreachable duplicate.
            let migrationStatus = lastStatus
            _ = deleteScoped(for: normalizedReference)
            lastStatus = migrationStatus
            return secret
        }
        return secret
    }

    @discardableResult
    func delete(for reference: String) -> Bool {
        let normalizedReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedReference.isEmpty else {
            lastStatus = errSecParam
            return false
        }

        let scopedStatus = SecItemDelete(scopedQuery(for: normalizedReference) as CFDictionary)
        var legacyCleanupSucceeded = true
        for item in legacyItems(for: normalizedReference) {
            guard let persistentReference = item.persistentReference else {
                legacyCleanupSucceeded = false
                continue
            }
            legacyCleanupSucceeded = delete(persistentReference: persistentReference)
                && legacyCleanupSucceeded
        }

        let scopedSucceeded = scopedStatus == errSecSuccess || scopedStatus == errSecItemNotFound
        lastStatus = scopedSucceeded && legacyCleanupSucceeded ? errSecSuccess : scopedStatus
        return scopedSucceeded && legacyCleanupSucceeded
    }

    private func scopedQuery(for reference: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: reference
        ]
    }

    private func loadScoped(for reference: String) -> String? {
        var query = scopedQuery(for: reference)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        lastStatus = status
        guard status == errSecSuccess,
              let data = result as? Data,
              let secret = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @discardableResult
    private func deleteScoped(for reference: String) -> Bool {
        let status = SecItemDelete(scopedQuery(for: reference) as CFDictionary)
        lastStatus = status
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private struct LegacyItem {
        var secret: String?
        var persistentReference: Data?
    }

    private func legacyItems(for reference: String) -> [LegacyItem] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: reference,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecReturnPersistentRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess else {
            lastStatus = status
            return []
        }

        let dictionaries: [[String: Any]]
        if let array = result as? [[String: Any]] {
            dictionaries = array
        } else if let dictionary = result as? [String: Any] {
            dictionaries = [dictionary]
        } else {
            return []
        }

        return dictionaries.compactMap { attributes in
            let itemService = attributes[kSecAttrService as String] as? String
            guard itemService == nil || itemService?.isEmpty == true else {
                return nil
            }

            let data = attributes[kSecValueData as String] as? Data
            let decodedSecret = data.flatMap { String(data: $0, encoding: .utf8) }
            let secret = decodedSecret?.trimmingCharacters(in: .whitespacesAndNewlines)
            let persistentReference = attributes[kSecValuePersistentRef as String] as? Data
            return LegacyItem(
                secret: secret?.isEmpty == false ? secret : nil,
                persistentReference: persistentReference
            )
        }
    }

    @discardableResult
    private func delete(persistentReference: Data) -> Bool {
        let query: [String: Any] = [
            kSecValuePersistentRef as String: persistentReference
        ]
        let status = SecItemDelete(query as CFDictionary)
        lastStatus = status
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
