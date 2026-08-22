import Foundation
import LocalAuthentication

/// Signing a browser in to the read-only web dashboard.
///
/// The dashboard runs on a screen that cannot reasonably be asked to hold this
/// app's bearer token — a car's touchscreen, parked, with no clipboard worth
/// using. So the server issues a short-lived pairing code, draws it as a QR
/// symbol, and this app approves it. What the browser receives is deliberately
/// weaker than what this app holds: read-only, expiring, revocable from here, and
/// refused by the backend's vehicle-action routes.
///
/// This app never handles the browser's credential. Approval tells the server to
/// mint one; the waiting browser collects it directly.

/// A scanned pairing code.
///
/// Parsed from the QR payload rather than trusted: the payload is a string from a
/// camera pointed at whatever happened to be in front of it, and everything
/// downstream — which server, which pairing — comes from these three fields.
struct WebPairingCode: Equatable, Sendable {
    let pairingID: String
    let code: String
    /// The address the *browser* reached the server at, as the server saw it.
    ///
    /// Shown to the person approving. It is the field that reveals a QR code
    /// belonging to somebody else's server, so it is displayed even when it
    /// matches, rather than only when it does not.
    let origin: String?

    /// Parses a scanned string, or returns nil.
    ///
    /// Accepts exactly what this project's servers emit:
    /// `tessalytics://pair?v=1&id=<hex>&code=XXXX-XXXX&origin=<url>`.
    /// A custom scheme rather than an https URL, because a payload that a browser
    /// would happily open is a payload somebody will eventually open in a browser.
    init?(scanned raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "tessalytics",
              // `tessalytics://pair?…` puts "pair" in the host; a three-slash form
              // would put it in the path. Accept either rather than fail on a
              // difference that carries no meaning.
              (components.host?.lowercased() == "pair" || components.path.lowercased().hasSuffix("pair"))
        else { return nil }

        let items = Dictionary(
            (components.queryItems ?? []).compactMap { item -> (String, String)? in
                guard let value = item.value else { return nil }
                return (item.name.lowercased(), value)
            },
            uniquingKeysWith: { first, _ in first }
        )

        guard let identifier = items["id"], Self.isPairingIdentifier(identifier),
              let rawCode = items["code"], let code = Self.normalisedCode(rawCode)
        else { return nil }

        self.pairingID = identifier
        self.code = code
        self.origin = items["origin"]
    }

    init(pairingID: String, code: String, origin: String?) {
        self.pairingID = pairingID
        self.code = code
        self.origin = origin
    }

    /// Hexadecimal, and long enough to be the server's identifier rather than
    /// something that happened to be in the frame.
    static func isPairingIdentifier(_ value: String) -> Bool {
        (8...64).contains(value.count) && value.allSatisfy(\.isHexDigit)
    }

    /// `ABCD-EFGH`, from anything that carries those eight characters.
    ///
    /// Case and the hyphen carry no information, so a code read in lower case or
    /// without its separator is the same code. The server normalises identically.
    static func normalisedCode(_ value: String) -> String? {
        let allowed = Set("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        let characters = value.uppercased().filter { allowed.contains($0) }
        guard characters.count == 8 else { return nil }
        let midpoint = characters.index(characters.startIndex, offsetBy: 4)
        return "\(characters[..<midpoint])-\(characters[midpoint...])"
    }
}

/// What the server says a pending pairing is asking for.
struct WebPairingRequest: Equatable, Sendable {
    let pairingID: String
    let code: String
    let status: String
    let expiresInSeconds: Int?
    let address: String?
    let userAgent: String?
    let origin: String?
    let label: String?

    var isPending: Bool { status == "pending" }

    /// The browser, named from whatever it said about itself.
    ///
    /// A user-agent string is unreadable on a confirmation sheet, and the question
    /// it has to answer is "is this the browser I am sitting in front of".
    var browser: String {
        let agent = (userAgent ?? "").lowercased()
        for (needle, name) in [
            ("tesla", "Tesla browser"),
            ("crios", "Chrome on iPhone"),
            ("edg/", "Edge"),
            ("chrome", "Chrome"),
            ("firefox", "Firefox"),
            ("safari", "Safari")
        ] where agent.contains(needle) {
            return name
        }
        return label ?? "Unknown browser"
    }
}

/// A browser that has been signed in.
struct WebSessionSummary: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let scope: String
    let createdAt: Date?
    let expiresAt: Date?
    let lastSeenAt: Date?
    let address: String?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt < Date()
    }
}

/// The device-owner check in front of an approval.
///
/// Granting a browser the whole location history is not a smaller decision than
/// sending the car a command, and the app already asks for Face ID before those.
/// It is also the one moment where a phone left unlocked on a table would
/// otherwise be enough to approve a code somebody else is showing it.
enum WebPairingAuthorization {
    @MainActor
    static func request(browser: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Confirm read-only access for \(browser)."
            )
        } catch {
            return false
        }
    }
}
