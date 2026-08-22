import Foundation

enum OwnerAPIError: Error, Equatable, LocalizedError, Sendable {
    case credentialsMissing
    case invalidCredentials
    case refreshRejected
    case vehicleUnavailable
    case rateLimited
    /// Tesla refused the request outright rather than refusing the credential.
    case preconditionFailed
    case commandRejected(String)
    case unexpectedStatus(Int)
    case invalidResponse
    case transport

    var errorDescription: String? {
        switch self {
        case .credentialsMissing: "Paste both Owner API tokens to connect."
        case .invalidCredentials: "The Owner API token was rejected. Generate a fresh token pair and try again."
        case .refreshRejected: "Tesla rejected the refresh token. Generate a new Owner API token pair."
        case .vehicleUnavailable: "The vehicle is asleep or temporarily unavailable. Tessalytics did not wake it."
        case .rateLimited: "Tesla is receiving too many requests. Try again shortly."
        case .preconditionFailed:
            "Tesla refused this request (HTTP 412). The Owner API is unofficial and Tesla changes it without notice; this usually means the account or the endpoint is no longer served."
        case .commandRejected(let reason): reason.isEmpty ? "The vehicle rejected the command." : reason
        case .unexpectedStatus(let status): "Tesla returned an unexpected response (HTTP \(status))."
        case .invalidResponse: "Tesla returned data this version of Tessalytics could not read."
        case .transport: "Tesla could not be reached. Check the network connection."
        }
    }
}

enum OwnerVehicleCommand: String, CaseIterable, Identifiable, Sendable {
    case lock
    case unlock
    case climateOn
    case climateOff
    case chargeStart
    case chargeStop
    case openTrunk
    case openFrunk

    var id: Self { self }
    var title: String {
        switch self {
        case .lock: "Lock"
        case .unlock: "Unlock"
        case .climateOn: "Climate on"
        case .climateOff: "Climate off"
        case .chargeStart: "Start charge"
        case .chargeStop: "Stop charge"
        case .openTrunk: "Open trunk"
        case .openFrunk: "Open frunk"
        }
    }
    var symbol: String {
        switch self {
        case .lock: "lock.fill"
        case .unlock: "lock.open.fill"
        case .climateOn: "fan.fill"
        case .climateOff: "fan.slash.fill"
        case .chargeStart: "bolt.fill"
        case .chargeStop: "bolt.slash.fill"
        case .openTrunk: "car.rear.waves.up"
        case .openFrunk: "car.front.waves.up"
        }
    }
    fileprivate var endpoint: String {
        switch self {
        case .lock: "door_lock"
        case .unlock: "door_unlock"
        case .climateOn: "auto_conditioning_start"
        case .climateOff: "auto_conditioning_stop"
        case .chargeStart: "charge_start"
        case .chargeStop: "charge_stop"
        case .openTrunk, .openFrunk: "actuate_trunk"
        }
    }
    fileprivate var body: [String: String] {
        switch self {
        case .openTrunk: ["which_trunk": "rear"]
        case .openFrunk: ["which_trunk": "front"]
        default: [:]
        }
    }
}

actor OwnerAPISession {
    private let store: any OwnerCredentialStore
    private let transport: any HTTPTransport
    private let decoder: JSONDecoder
    private var cachedCredentials: OwnerAPICredentials?
    private var refreshTask: Task<OwnerAPICredentials, any Error>?

    init(store: any OwnerCredentialStore = KeychainOwnerCredentialStore(), transport: any HTTPTransport = URLSession.shared) {
        self.store = store
        self.transport = transport
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    func isConfigured() -> Bool {
        (try? credentials())?.isUsable == true
    }

    /// Connects with a refresh token, and nothing else.
    ///
    /// The access token is minted here rather than asked for. It is derived from
    /// the refresh token by definition, it expires in hours where the refresh
    /// token lasts months, and asking for both meant a pair that had drifted
    /// apart — a stale access token beside a good refresh token — failed at the
    /// first request instead of simply being replaced. One field, one paste, and
    /// the app holds a token it minted itself.
    func configure(refreshToken: String, region: OwnerAPIRegion) async throws -> [OwnerVehicle] {
        let trimmed = refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OwnerAPIError.credentialsMissing }

        // Deliberately expired: this seed exists only to carry the refresh token
        // and the region into the exchange below, and must never be used to
        // authenticate a request.
        let seed = OwnerAPICredentials(
            accessToken: "",
            refreshToken: trimmed,
            expiresAt: .distantPast,
            region: region
        )
        // Saves the minted pair itself, so a failure here leaves nothing behind.
        let minted = try await Self.requestRefreshedCredentials(
            from: seed,
            store: store,
            transport: transport
        )
        cachedCredentials = minted
        do {
            return try await vehicles()
        } catch {
            // The token is good — Tesla just would not answer for the account.
            // Keeping a credential the owner cannot use is worse than making
            // them paste it again.
            try? store.delete()
            cachedCredentials = nil
            throw error
        }
    }

    func disconnect() throws {
        try store.delete()
        cachedCredentials = nil
    }

    /// The cars on the account.
    ///
    /// Read from `/api/1/products` rather than `/api/1/vehicles`. Tesla made the
    /// vehicles endpoint answer **412 Precondition Failed** in January 2023 and
    /// never brought it back, so every attempt to connect failed at the first
    /// request with a status the app reported as merely "unexpected". Products
    /// returns the same fields for a car — `id`, `vehicle_id`, `vin`,
    /// `display_name`, `state` — alongside the account's energy hardware, which
    /// is filtered out by the one thing only a car has: a VIN.
    func vehicles() async throws -> [OwnerVehicle] {
        let envelope: OwnerAPIEnvelope<[OwnerProduct]> = try await authenticatedRequest(path: "api/1/products")
        return envelope.response.compactMap(\.vehicle)
    }

    func vehicleData(vehicleID: Int64) async throws -> OwnerVehicleData {
        let envelope: OwnerAPIEnvelope<OwnerVehicleData> = try await authenticatedRequest(path: "api/1/vehicles/\(vehicleID)/vehicle_data")
        return envelope.response
    }

    func send(_ command: OwnerVehicleCommand, vehicleID: Int64) async throws {
        let envelope: OwnerAPIEnvelope<OwnerCommandResponse> = try await authenticatedRequest(
            path: "api/1/vehicles/\(vehicleID)/command/\(command.endpoint)",
            method: "POST",
            body: command.body
        )
        guard envelope.response.result else {
            throw OwnerAPIError.commandRejected(envelope.response.reason ?? "The vehicle rejected the command.")
        }
    }

    private func authenticatedRequest<Response: Decodable & Sendable>(
        path: String,
        method: String = "GET",
        body: [String: String]? = nil
    ) async throws -> Response {
        var current = try credentials()
        if current.needsRefresh() { current = try await refresh(current) }

        let first = try await perform(path: path, method: method, body: body, credentials: current)
        if first.statusCode == 401 {
            current = try await refresh(current)
            let retry = try await perform(path: path, method: method, body: body, credentials: current)
            try validate(retry.statusCode)
            return try decode(Response.self, from: retry.data)
        }
        try validate(first.statusCode)
        return try decode(Response.self, from: first.data)
    }

    private func credentials() throws -> OwnerAPICredentials {
        if let cachedCredentials { return cachedCredentials }
        guard let stored = try store.credentials(), stored.isUsable else { throw OwnerAPIError.credentialsMissing }
        cachedCredentials = stored
        return stored
    }

    /// Exchanges the refresh token for a new pair, once.
    ///
    /// Tesla rotates the refresh token: the old one is spent the moment it is
    /// used. Two requests that both meet a 401 therefore have to share one
    /// exchange, and a caller that arrives holding a copy from before someone
    /// else's exchange must take the result rather than spend a token that is
    /// already dead — which presented as "Tesla rejected the refresh token" and
    /// disconnected an account whose credentials were perfectly good.
    private func refresh(_ credentials: OwnerAPICredentials) async throws -> OwnerAPICredentials {
        if let refreshTask { return try await refreshTask.value }
        if let cachedCredentials, cachedCredentials.refreshToken != credentials.refreshToken {
            return cachedCredentials
        }

        let store = store
        let transport = transport
        let task = Task {
            try await Self.requestRefreshedCredentials(
                from: credentials,
                store: store,
                transport: transport
            )
        }
        refreshTask = task
        defer { refreshTask = nil }
        let replacement = try await task.value
        cachedCredentials = replacement
        return replacement
    }

    private nonisolated static func requestRefreshedCredentials(
        from credentials: OwnerAPICredentials,
        store: any OwnerCredentialStore,
        transport: any HTTPTransport
    ) async throws -> OwnerAPICredentials {
        let url = credentials.region.authenticationURL.appending(path: "oauth2/v3/token")
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Self.teslaUserAgent, forHTTPHeaderField: "X-Tesla-User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "scope": "openid email offline_access",
            "client_id": "ownerapi",
            "refresh_token": credentials.refreshToken
        ])

        let data: Data
        let response: URLResponse
        do { (data, response) = try await transport.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw OwnerAPIError.transport }
        guard let http = response as? HTTPURLResponse else { throw OwnerAPIError.transport }
        guard (200...299).contains(http.statusCode) else {
            if [400, 401, 403].contains(http.statusCode) { throw OwnerAPIError.refreshRejected }
            throw OwnerAPIError.unexpectedStatus(http.statusCode)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let token: OwnerTokenResponse
        do { token = try decoder.decode(OwnerTokenResponse.self, from: data) }
        catch { throw OwnerAPIError.invalidResponse }
        let replacement = OwnerAPICredentials(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: .now.addingTimeInterval(TimeInterval(token.expiresIn)),
            region: credentials.region
        )
        try store.save(replacement)
        return replacement
    }

    private func perform(
        path: String,
        method: String,
        body: [String: String]?,
        credentials: OwnerAPICredentials
    ) async throws -> (data: Data, statusCode: Int) {
        let url = credentials.region.ownerAPIURL.appending(path: path)
        var request = URLRequest(url: url, timeoutInterval: 25)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Self.teslaUserAgent, forHTTPHeaderField: "X-Tesla-User-Agent")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        do {
            let (data, response) = try await transport.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw OwnerAPIError.transport }
            return (data, http.statusCode)
        } catch is CancellationError { throw CancellationError() }
        catch let error as OwnerAPIError { throw error }
        catch { throw OwnerAPIError.transport }
    }

    private func validate(_ status: Int) throws {
        switch status {
        case 200...299: return
        case 401, 403: throw OwnerAPIError.invalidCredentials
        case 408, 423: throw OwnerAPIError.vehicleUnavailable
        // Not "unexpected": 412 is a specific and now-common answer from this
        // API, and reporting it as a surprise tells the owner nothing.
        case 412: throw OwnerAPIError.preconditionFailed
        case 429: throw OwnerAPIError.rateLimited
        default: throw OwnerAPIError.unexpectedStatus(status)
        }
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do { return try decoder.decode(type, from: data) }
        catch { throw OwnerAPIError.invalidResponse }
    }

    private nonisolated static var userAgent: String {
        "Tessalytics/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1")"
    }

    private nonisolated static var teslaUserAgent: String {
        "TeslaApp/4.12.0/Tessalytics/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1")"
    }
}
