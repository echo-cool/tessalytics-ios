import Foundation

enum AuthenticationMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case bearer, basic, none
    var id: Self { self }
    var title: String {
        switch self { case .bearer: "Bearer token"; case .basic: "HTTP Basic"; case .none: "None (private network)" }
    }
}

enum Authentication: Equatable, Sendable {
    case bearer(String)
    case basic(username: String, password: String)
    case none
}

struct StoredCredentials: Equatable, Codable, Sendable {
    let method: AuthenticationMethod
    let username: String?
    let secret: String?
    var authentication: Authentication {
        switch method {
        case .bearer: .bearer(secret ?? "")
        case .basic: .basic(username: username ?? "", password: secret ?? "")
        case .none: .none
        }
    }
}


struct ServerProfile: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var baseURL: URL
    var authenticationMethod: AuthenticationMethod
    var allowsLocalHTTP: Bool
    var isSelected = false
}

struct ProfileDraft: Sendable {
    var name = "My TeslaMate"
    var serverURL = ""
    var authenticationMethod: AuthenticationMethod = .bearer
    var token = ""
    var username = ""
    var password = ""
    var allowsLocalHTTP = false

    func profile(id: UUID = UUID()) throws -> ServerProfile {
        let normalized = serverURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let components = URLComponents(string: normalized), let scheme = components.scheme?.lowercased(),
              let host = components.host, !host.isEmpty, let url = components.url,
              scheme == "https" || (scheme == "http" && allowsLocalHTTP && Self.isLocal(host))
        else { throw ClientError.invalidConfiguration }
        return ServerProfile(id: id, name: name.isEmpty ? host : name, baseURL: url,
                             authenticationMethod: authenticationMethod, allowsLocalHTTP: allowsLocalHTTP)
    }

    var credentials: StoredCredentials? {
        switch authenticationMethod {
        case .bearer: StoredCredentials(method: .bearer, username: nil, secret: token)
        case .basic: StoredCredentials(method: .basic, username: username, secret: password)
        case .none: StoredCredentials(method: .none, username: nil, secret: nil)
        }
    }

    private static func isLocal(_ host: String) -> Bool {
        host == "localhost" || host.hasSuffix(".local") || host.hasPrefix("127.") || host.hasPrefix("10.") || host.hasPrefix("192.168.") || host.hasPrefix("172.16.")
    }
}

struct Vehicle: Identifiable, Hashable, Sendable {
    let serverID: UUID
    let id: Int
    let name: String?
    let model: String?
    let trim: String?
    let totalDrives: Int?
    let totalCharges: Int?
    let totalUpdates: Int?
}

struct DateRangeFilter: Sendable {
    var start: Date?
    var end: Date?
    var location: String?
    var minimumDistance: Double?
    var maximumDistance: Double?
}

enum AnalyticsPeriod: String, CaseIterable, Identifiable, Sendable {
    case sevenDays = "7 days", thirtyDays = "30 days", currentMonth = "This month"
    case previousMonth = "Last month", currentYear = "This year", allTime = "All time"
    case custom = "Custom"
    var id: Self { self }
}
