import Foundation

/// The pairing and session routes.
///
/// Kept beside the client rather than inside it: these are the only calls this app
/// makes that are not about vehicle data, and the only ones that write anything.
/// They all go through `send`, so the retry policy, the header rules and the
/// server's own error messages are the same here as everywhere else.
extension TessalyticsBackendClient {
    /// What a scanned pairing is asking for, so the app can show it before
    /// anything is granted.
    func pairingRequest(id: String) async throws -> WebPairingRequest {
        try await send("GET", "v1/auth/pairing/\(id)", as: BackendEnvelope<BackendPairingWrapperDTO>.self)
            .data.pairing.request
    }

    /// Finds a pending pairing from the code printed beside the QR symbol.
    ///
    /// For a phone whose camera is unavailable, and for the simulator. The route
    /// requires this app's token, which is what keeps an eight-character code from
    /// being worth guessing.
    func findPairing(code: String) async throws -> WebPairingRequest {
        try await send(
            "POST",
            "v1/auth/pairing/lookup",
            body: PairingLookupBody(code: code),
            as: BackendEnvelope<BackendPairingWrapperDTO>.self
        ).data.pairing.request
    }

    /// Approves a pairing, and returns the session the server issued.
    ///
    /// The browser's token is not returned here and never reaches this app: the
    /// waiting browser collects it from the server itself. There is nothing to
    /// hold, so there is nothing to leak.
    func approvePairing(id: String, code: String, label: String?) async throws -> WebSessionSummary {
        try await send(
            "POST",
            "v1/auth/pairing/\(id)/approve",
            body: PairingApprovalBody(code: code, label: label),
            as: BackendEnvelope<BackendApprovalDTO>.self
        ).data.session.summary
    }

    func denyPairing(id: String) async throws {
        _ = try await send(
            "POST",
            "v1/auth/pairing/\(id)/deny",
            as: BackendEnvelope<BackendPairingWrapperDTO>.self
        )
    }

    /// Every browser currently signed in to this server.
    func webSessions() async throws -> [WebSessionSummary] {
        try await send("GET", "v1/auth/sessions", as: BackendEnvelope<BackendWebSessionListDTO>.self)
            .data.sessions.map(\.summary)
    }

    /// Takes a browser's access away, immediately and for good.
    func revokeWebSession(id: String) async throws {
        _ = try await send("DELETE", "v1/auth/sessions/\(id)", as: BackendEnvelope<BackendRevocationDTO>.self)
    }
}

// MARK: - Wire types

private struct PairingApprovalBody: Encodable, Sendable {
    let code: String
    let label: String?
}

private struct PairingLookupBody: Encodable, Sendable {
    let code: String
}

struct BackendPairingWrapperDTO: Decodable, Sendable {
    let pairing: BackendPairingDTO
}

struct BackendApprovalDTO: Decodable, Sendable {
    let pairing: BackendPairingDTO
    let session: BackendWebSessionDTO
}

struct BackendRevocationDTO: Decodable, Sendable {
    let revoked: String?
}

struct BackendPairingDTO: Decodable, Sendable {
    let id: String
    let code: String
    let status: String
    let expiresInSeconds: Int?
    let client: BackendPairingClientDTO?

    var request: WebPairingRequest {
        WebPairingRequest(
            pairingID: id,
            code: code,
            status: status,
            expiresInSeconds: expiresInSeconds,
            address: client?.address,
            userAgent: client?.userAgent,
            origin: client?.origin,
            label: client?.label
        )
    }
}

struct BackendPairingClientDTO: Decodable, Sendable {
    let address: String?
    let userAgent: String?
    let origin: String?
    let label: String?
}

struct BackendWebSessionListDTO: Decodable, Sendable {
    let sessions: [BackendWebSessionDTO]
}

struct BackendWebSessionDTO: Decodable, Sendable {
    let id: String
    let label: String?
    let scope: String?
    let createdAt: String?
    let expiresAt: String?
    let lastSeenAt: String?
    let client: BackendPairingClientDTO?

    var summary: WebSessionSummary {
        WebSessionSummary(
            id: id,
            label: label ?? "Paired browser",
            scope: scope ?? "read",
            createdAt: BackendPairingDate.parse(createdAt),
            expiresAt: BackendPairingDate.parse(expiresAt),
            lastSeenAt: BackendPairingDate.parse(lastSeenAt),
            address: client?.address
        )
    }
}

/// The timestamps on these routes are RFC 3339 with fractional seconds, which the
/// default `ISO8601DateFormatter` refuses. Parsed here rather than by the shared
/// decoder because these are the only dates on this surface, and a date that fails
/// to parse must read as "unknown" rather than take the whole response down.
enum BackendPairingDate {
    static func parse(_ value: String?) -> Date? {
        guard let value else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }
}
