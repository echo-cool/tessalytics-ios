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

struct KeychainOwnerCredentialStore: OwnerCredentialStore, Sendable {
    private let service = "com.echocool.Tessalytics.owner-api-credentials"
    private let account = "primary"

    func save(_ credentials: OwnerAPICredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        var query = base
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    func credentials() throws -> OwnerAPICredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError.unhandled(status) }
        return try JSONDecoder().decode(OwnerAPICredentials.self, from: data)
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.unhandled(status) }
    }
}
