import Foundation
import Security

protocol CredentialStore: Sendable {
    func save(_ credentials: StoredCredentials, profileID: UUID) throws
    func credentials(profileID: UUID) throws -> StoredCredentials?
    func delete(profileID: UUID) throws
}

enum KeychainError: Error { case unhandled(OSStatus), invalidData }

/// Server credentials, in iCloud Keychain.
///
/// Synchronised deliberately, and the trade is worth stating. Until 1.9.5 these
/// were written `WhenUnlockedThisDeviceOnly`, which is the strongest thing the
/// Keychain offers and meant a second device had to be set up by hand. Following
/// the owner's Apple Account requires giving that up: a device-only item cannot
/// sync, by construction.
///
/// What replaces it is not weak. iCloud Keychain is end-to-end encrypted with
/// keys derived from the account's own devices; Apple cannot read it, and neither
/// can this app on a device the owner has not signed in. `WhenUnlocked` still
/// means a locked phone yields nothing, and the item is still absent from
/// preferences, the SwiftData stores and diagnostics.
struct KeychainCredentialStore: CredentialStore, Sendable {
    private let service = "com.echocool.Tessalytics.server-credentials"

    func save(_ credentials: StoredCredentials, profileID: UUID) throws {
        let data = try JSONEncoder().encode(credentials)
        let account = profileID.uuidString
        // Both variants are deleted first. An item written by an older release is
        // device-only and not synchronisable, and adding the synced one beside it
        // would leave two items that `SecItemCopyMatching` picks between by rules
        // this code does not control.
        for synchronizable in [kCFBooleanTrue, kCFBooleanFalse] as [CFBoolean] {
            SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecAttrSynchronizable as String: synchronizable
            ] as CFDictionary)
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // Not `ThisDeviceOnly`: that class cannot leave the device, which is
            // the entire point of this change.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    func credentials(profileID: UUID) throws -> StoredCredentials? {
        // `kSecAttrSynchronizableAny` so this finds both the synced item and one
        // left behind by an older release on this device.
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: profileID.uuidString,
                                    kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError.unhandled(status) }
        let credentials = try JSONDecoder().decode(StoredCredentials.self, from: data)
        // Migrate a device-only item from an older release into iCloud Keychain,
        // so the second device the owner signs in on finds it. `SecItemUpdate`
        // cannot move an item between the synchronisable classes, so this is a
        // rewrite rather than an attribute change.
        migrateToSynchronizable(credentials, profileID: profileID)
        return credentials
    }

    /// Best effort, and silent on failure: the caller already has what it asked
    /// for, and a credential that stays device-local is a smaller problem than a
    /// read that throws because the rewrite did not take.
    private func migrateToSynchronizable(_ credentials: StoredCredentials, profileID: UUID) {
        let deviceOnly: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID.uuidString,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
        var existing: CFTypeRef?
        guard SecItemCopyMatching(
            deviceOnly.merging([kSecReturnData as String: true]) { current, _ in current } as CFDictionary,
            &existing
        ) == errSecSuccess else { return }
        try? save(credentials, profileID: profileID)
    }

    func delete(profileID: UUID) throws {
        // Removed from the account, not just from here. Deleting only the synced
        // item would leave a stale device-only one behind to be found later.
        var lastFailure: OSStatus?
        for synchronizable in [kSecAttrSynchronizableAny] as [Any] {
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                        kSecAttrService as String: service,
                                        kSecAttrAccount as String: profileID.uuidString,
                                        kSecAttrSynchronizable as String: synchronizable]
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound { lastFailure = status }
        }
        if let lastFailure { throw KeychainError.unhandled(lastFailure) }
    }
}
