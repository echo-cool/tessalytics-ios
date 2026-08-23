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
    // Names the service the URL must point at: TeslaMate itself does not serve this API.
    var name = "My Tessalytics Backend"
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
              scheme == "https" || (scheme == "http" && allowsLocalHTTP)
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

    /// Whether a host is on the local network. Public HTTP can also be enabled
    /// explicitly for compatibility, but is presented as the less-safe case.
    ///
    /// Matched as an address rather than as a prefix of a name. `hasPrefix("10.")`
    /// is true of `10.example.com`, which is a public host an attacker can
    /// register — and answering yes to it downgraded the connection to cleartext
    /// and put the bearer token on the wire in the clear. The private ranges are
    /// also checked properly: 172.16.0.0/12 is 172.16 through 172.31, and the
    /// old prefix test rejected the 172.17–172.31 addresses Docker hands out by
    /// default.
    static func isLocal(_ host: String) -> Bool {
        let name = host.lowercased()
        if name == "localhost" || name.hasSuffix(".local") || name.hasSuffix(".localhost") { return true }
        // IPv6 loopback and unique-local, with or without the URL's brackets.
        let bare = name.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if bare == "::1" { return true }
        if bare.hasPrefix("fd") || bare.hasPrefix("fc") || bare.hasPrefix("fe80:") { return true }

        let octets = bare.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard octets.count == 4, let first = UInt8(octets[0]), let second = UInt8(octets[1]),
              octets.allSatisfy({ UInt8($0) != nil }) else { return false }
        switch first {
        case 10: return true
        case 127: return true
        case 169: return second == 254            // link-local
        case 172: return (16...31).contains(second)
        case 192: return second == 168
        case 100: return (64...127).contains(second) // CGNAT/overlay networks such as Tailscale
        default: return false
        }
    }
}

struct Vehicle: Identifiable, Hashable, Sendable {
    let serverID: UUID
    let id: Int
    let name: String?
    let model: String?
    let trim: String?
    /// Optional because TeslaMateApi does not report it and an older cache has
    /// none. Everything that reads it treats absence as "cannot tell".
    var vin: String?
    let totalDrives: Int?
    let totalCharges: Int?
    let totalUpdates: Int?

    init(
        serverID: UUID,
        id: Int,
        name: String?,
        model: String?,
        trim: String?,
        vin: String? = nil,
        totalDrives: Int?,
        totalCharges: Int?,
        totalUpdates: Int?
    ) {
        self.serverID = serverID
        self.id = id
        self.name = name
        self.model = model
        self.trim = trim
        self.vin = vin
        self.totalDrives = totalDrives
        self.totalCharges = totalCharges
        self.totalUpdates = totalUpdates
    }
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

extension Authentication {
    /// Sets the Authorization header this method needs, if any.
    ///
    /// Shared by the request client and the event stream: two copies of a header
    /// rule is one copy too many when a wrong one means a silent 401.
    func apply(to request: inout URLRequest) {
        switch self {
        case .bearer(let token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .basic(let username, let password):
            let encoded = Data("\(username):\(password)".utf8).base64EncodedString()
            request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        case .none:
            break
        }
    }
}
