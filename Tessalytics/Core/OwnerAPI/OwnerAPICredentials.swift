import Foundation
import Security

enum OwnerAPIRegion: String, Codable, CaseIterable, Identifiable, Sendable {
    case global
    case china

    var id: Self { self }
    var title: String { self == .global ? "Global" : "China" }
    var authenticationURL: URL {
        URL(string: self == .global ? "https://auth.tesla.com" : "https://auth.tesla.cn")!
    }
    var ownerAPIURL: URL {
        URL(string: self == .global ? "https://owner-api.teslamotors.com" : "https://owner-api.vn.cloud.tesla.cn")!
    }
}

struct OwnerAPICredentials: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date?
    let region: OwnerAPIRegion

    init(accessToken: String, refreshToken: String, expiresAt: Date? = nil, region: OwnerAPIRegion) {
        self.accessToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        self.refreshToken = refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        self.expiresAt = expiresAt ?? Self.expirationDate(in: accessToken)
        self.region = region
    }

    var isUsable: Bool { !accessToken.isEmpty && !refreshToken.isEmpty }

    func needsRefresh(at date: Date = .now, leeway: TimeInterval = 60) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= date.addingTimeInterval(leeway)
    }

    private static func expirationDate(in token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var encoded = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let expiry = object["exp"] as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: expiry.doubleValue)
    }
}

protocol OwnerCredentialStore: Sendable {
    func save(_ credentials: OwnerAPICredentials) throws
    func credentials() throws -> OwnerAPICredentials?
    func delete() throws
}

/// The Tesla tokens, in iCloud Keychain.
///
/// The most consequential item this app stores: a refresh token that can unlock
/// and start the car. It syncs for the same reason the server does — an owner with
/// an iPad should not have to mint a second token — and it syncs through iCloud
/// Keychain rather than through CloudKit or a file, because that is the only
/// mechanism here that is end-to-end encrypted with keys Apple does not hold.
///
/// `WhenUnlocked` rather than `WhenUnlockedThisDeviceOnly`, which is a real
/// reduction from what shipped before 1.9.6: a device-only item cannot sync. A
/// locked device still yields nothing, and the command path is unchanged — every
/// command still needs Face ID or the passcode, so a synced token alone does not
/// move the car.
struct KeychainOwnerCredentialStore: OwnerCredentialStore, Sendable {
    private let service = "com.echocool.Tessalytics.owner-api-credentials"
    private let account = "primary"

    func save(_ credentials: OwnerAPICredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        // Both variants first: an item from an older release is device-only, and
        // leaving it beside the synced one makes reads ambiguous.
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
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    func credentials() throws -> OwnerAPICredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError.unhandled(status) }
        let credentials = try JSONDecoder().decode(OwnerAPICredentials.self, from: data)
        migrateToSynchronizable(credentials)
        return credentials
    }

    /// Rewrites a device-only item from an older release as a synced one, so the
    /// owner's other devices find it. Silent on failure: the caller already has
    /// the token, and a token that stays on one device is the old behaviour
    /// rather than a fault.
    private func migrateToSynchronizable(_ credentials: OwnerAPICredentials) {
        let deviceOnly: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecReturnData as String: true
        ]
        var existing: CFTypeRef?
        guard SecItemCopyMatching(deviceOnly as CFDictionary, &existing) == errSecSuccess else { return }
        try? save(credentials)
    }

    func delete() throws {
        // Signing out removes the token from the account, not just from here.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.unhandled(status) }
    }
}
