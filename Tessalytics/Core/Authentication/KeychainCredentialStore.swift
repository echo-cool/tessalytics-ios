import Foundation
import Security

protocol CredentialStore: Sendable {
    func save(_ credentials: StoredCredentials, profileID: UUID) throws
    func credentials(profileID: UUID) throws -> StoredCredentials?
    func delete(profileID: UUID) throws
}

enum KeychainError: Error { case unhandled(OSStatus), invalidData }

struct KeychainCredentialStore: CredentialStore, Sendable {
    private let service = "com.echocool.Tessalytics.server-credentials"

    func save(_ credentials: StoredCredentials, profileID: UUID) throws {
        let data = try JSONEncoder().encode(credentials)
        let account = profileID.uuidString
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        var query = base
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    func credentials(profileID: UUID) throws -> StoredCredentials? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: profileID.uuidString,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError.unhandled(status) }
        return try JSONDecoder().decode(StoredCredentials.self, from: data)
    }

    func delete(profileID: UUID) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: profileID.uuidString]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.unhandled(status) }
    }
}
