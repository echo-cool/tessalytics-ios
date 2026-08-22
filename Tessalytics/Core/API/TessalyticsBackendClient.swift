import Foundation

/// Client for Tessalytics Backend.
///
/// The backend serves a different, better-shaped API than TeslaMateApi: one
/// envelope, requested units, cursor pagination, and — the reason it exists — a
/// missing reading is `null` rather than `false` or `0`.
///
/// This adapts that surface onto the same `VehicleDataAPI` protocol the rest of the
/// app already speaks, so the repositories, persistence and views are untouched.
/// The app gains the correctness without a rewrite, and the two server types stay
/// interchangeable behind one protocol.
///
/// Where the mapping loses nothing it is direct. Where the backend knows *more*
/// than the old DTOs can express — lifetime totals, the state timeline, the
/// position track — that is reached through the dedicated methods below rather
/// than forced through a TeslaMateApi shape.
struct TessalyticsBackendClient: VehicleDataAPI, Sendable {
    let baseURL: URL
    let authentication: Authentication
    private let transport: any HTTPTransport
    private let decoder: JSONDecoder
    private let timeout: TimeInterval

    /// Ask for the units the server itself is configured for, so the app keeps
    /// rendering in the owner's chosen scale without having to convert.
    ///
    /// Shared with the event stream: readings that arrive by two routes have to be
    /// on the same scale, or a speed changes by a factor of 1.6 depending on
    /// whether the poll or the stream delivered it.
    static let unitSystem = "teslamate"

    init(
        baseURL: URL,
        authentication: Authentication,
        transport: any HTTPTransport = URLSession.shared,
        timeout: TimeInterval = 30
    ) {
        self.baseURL = baseURL
        self.authentication = authentication
        self.transport = transport
        self.timeout = timeout
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    // MARK: - Probing

    /// Whether a server is a Tessalytics Backend.
    ///
    /// `/v1` is the discovery document and exists only here; TeslaMateApi answers
    /// 404. Used to pick a client without asking the user which they configured.
    static func detect(
        baseURL: URL,
        authentication: Authentication,
        transport: any HTTPTransport = URLSession.shared
    ) async -> BackendCapabilities? {
        let client = TessalyticsBackendClient(baseURL: baseURL, authentication: authentication, transport: transport, timeout: 12)
        return try? await client.capabilities()
    }

    func capabilities() async throws -> BackendCapabilities {
        try await get("v1", as: BackendDiscoveryDTO.self).data
    }

    // MARK: - VehicleDataAPI

    func ping() async throws {
        _ = try await get("api/ping", as: BackendPingDTO.self)
    }

    func cars() async throws -> CarsDataDTO {
        let response = try await get("v1/vehicles", as: BackendEnvelope<BackendVehicleListDTO>.self)
        return CarsDataDTO(cars: response.data.vehicles.map(\.carDTO))
    }

    func car(carID: Int) async throws -> CarsDataDTO {
        let response = try await get("v1/vehicles/\(carID)", as: BackendEnvelope<BackendVehicleWrapperDTO>.self)
        return CarsDataDTO(cars: [response.data.vehicle.carDTO])
    }

    func status(carID: Int) async throws -> StatusDataDTO {
        try await get(
            "v1/vehicles/\(carID)/state",
            query: [URLQueryItem(name: "units", value: Self.unitSystem)],
            as: BackendEnvelope<BackendStateWrapperDTO>.self
        ).statusData(carID: carID)
    }

    func drives(carID: Int, page: Int, show: Int = 30, filter: DateRangeFilter = .init()) async throws -> DrivesDataDTO {
        // The backend paginates by cursor, which is strictly better but has no
        // page number. Offsets are emulated by walking cursors, and because the
        // app only ever asks for page 1 in normal use this costs nothing there;
        // a deep page costs one request per page skipped.
        var cursor: String?
        for _ in 1..<max(page, 1) {
            let step = try await drivePage(carID: carID, show: show, filter: filter, cursor: cursor)
            guard let next = step.meta?.page?.next else {
                return DrivesDataDTO(car: CarReferenceDTO(carId: carID, carName: nil), drives: [], units: step.meta?.units?.unitsDTO)
            }
            cursor = next
        }
        let response = try await drivePage(carID: carID, show: show, filter: filter, cursor: cursor)
        return DrivesDataDTO(
            car: CarReferenceDTO(carId: carID, carName: nil),
            drives: response.data.drives.map(\.summaryDTO),
            units: response.meta?.units?.unitsDTO
        )
    }

    private func drivePage(
        carID: Int,
        show: Int,
        filter: DateRangeFilter,
        cursor: String?
    ) async throws -> BackendEnvelope<BackendDriveListDTO> {
        var query = [
            URLQueryItem(name: "limit", value: String(min(max(show, 1), 500))),
            URLQueryItem(name: "units", value: Self.unitSystem)
        ]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        query.append(contentsOf: filter.backendQuery)
        return try await get("v1/vehicles/\(carID)/drives", query: query, as: BackendEnvelope<BackendDriveListDTO>.self)
    }

    func drive(carID: Int, driveID: Int) async throws -> DriveDataDTO {
        let response = try await get(
            "v1/vehicles/\(carID)/drives/\(driveID)",
            query: [URLQueryItem(name: "units", value: Self.unitSystem), URLQueryItem(name: "samples", value: "true")],
            as: BackendEnvelope<BackendDriveWrapperDTO>.self
        )
        return DriveDataDTO(
            car: CarReferenceDTO(carId: carID, carName: nil),
            drive: response.data.drive.detailDTO,
            units: response.meta?.units?.unitsDTO
        )
    }

    func charges(carID: Int, page: Int, show: Int = 30, filter: DateRangeFilter = .init()) async throws -> ChargesDataDTO {
        var cursor: String?
        for _ in 1..<max(page, 1) {
            let step = try await chargePage(carID: carID, show: show, filter: filter, cursor: cursor)
            guard let next = step.meta?.page?.next else {
                return ChargesDataDTO(car: CarReferenceDTO(carId: carID, carName: nil), charges: [], units: step.meta?.units?.unitsDTO)
            }
            cursor = next
        }
        let response = try await chargePage(carID: carID, show: show, filter: filter, cursor: cursor)
        return ChargesDataDTO(
            car: CarReferenceDTO(carId: carID, carName: nil),
            charges: response.data.charges.map(\.summaryDTO),
            units: response.meta?.units?.unitsDTO
        )
    }

    private func chargePage(
        carID: Int,
        show: Int,
        filter: DateRangeFilter,
        cursor: String?
    ) async throws -> BackendEnvelope<BackendChargeListDTO> {
        var query = [
            URLQueryItem(name: "limit", value: String(min(max(show, 1), 500))),
            URLQueryItem(name: "units", value: Self.unitSystem)
        ]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        query.append(contentsOf: filter.backendQuery)
        return try await get("v1/vehicles/\(carID)/charges", query: query, as: BackendEnvelope<BackendChargeListDTO>.self)
    }

    func charge(carID: Int, chargeID: Int) async throws -> ChargeDataDTO {
        let response = try await get(
            "v1/vehicles/\(carID)/charges/\(chargeID)",
            query: [URLQueryItem(name: "units", value: Self.unitSystem), URLQueryItem(name: "samples", value: "true")],
            as: BackendEnvelope<BackendChargeWrapperDTO>.self
        )
        return ChargeDataDTO(
            car: CarReferenceDTO(carId: carID, carName: nil),
            charge: response.data.charge.detailDTO,
            units: response.meta?.units?.unitsDTO
        )
    }

    func currentCharge(carID: Int) async throws -> ChargeDataDTO {
        let response = try await get(
            "v1/vehicles/\(carID)/charges/active",
            query: [URLQueryItem(name: "units", value: Self.unitSystem)],
            as: BackendEnvelope<BackendOptionalChargeDTO>.self
        )
        // The backend answers null for "nothing charging" rather than 404, which
        // is the better contract; the app's protocol expects a throw.
        guard let charge = response.data.charge else { throw ClientError.notFound }
        return ChargeDataDTO(
            car: CarReferenceDTO(carId: carID, carName: nil),
            charge: charge.detailDTO,
            units: response.meta?.units?.unitsDTO
        )
    }

    func batteryHealth(carID: Int) async throws -> BatteryHealthDataDTO {
        let response = try await get(
            "v1/vehicles/\(carID)/battery",
            query: [URLQueryItem(name: "units", value: Self.unitSystem)],
            as: BackendEnvelope<BackendBatteryWrapperDTO>.self
        )
        return BatteryHealthDataDTO(
            car: CarReferenceDTO(carId: carID, carName: nil),
            batteryHealth: response.data.battery.healthDTO(units: response.meta?.units),
            units: response.meta?.units?.unitsDTO
        )
    }

    func updates(carID: Int) async throws -> UpdatesDataDTO {
        let response = try await get("v1/vehicles/\(carID)/updates", as: BackendEnvelope<BackendUpdateListDTO>.self)
        return UpdatesDataDTO(
            car: CarReferenceDTO(carId: carID, carName: nil),
            updates: response.data.updates.map(\.updateDTO)
        )
    }

    func globalSettings() async throws -> GlobalSettingsDataDTO {
        let response = try await get("v1/settings", as: BackendEnvelope<BackendSettingsWrapperDTO>.self)
        return GlobalSettingsDataDTO(
            settings: GlobalSettingsDTO(teslamateUnits: response.data.settings?.units?.unitsDTO)
        )
    }

    // MARK: - Beyond TeslaMateApi

    /// Lifetime totals, computed by the server.
    ///
    /// This is the one that earns the migration: the app previously paged the
    /// entire drive and charge history to sum these itself — eight requests for
    /// 800 drives, repeated per install.
    func totals(carID: Int) async throws -> BackendTotals {
        try await get(
            "v1/vehicles/\(carID)/totals",
            query: [URLQueryItem(name: "units", value: Self.unitSystem)],
            as: BackendEnvelope<BackendTotalsWrapperDTO>.self
        ).data.totals
    }

    /// The driven path, aggregated and simplified by the server.
    ///
    /// 1.7 million position rows cannot be paged onto a phone, and they do not
    /// need to be: the server groups them per drive, drops the points that lie on
    /// a line their neighbours already describe, and answers with a few hundred
    /// kilobytes. One request replaces what would otherwise be hundreds.
    /// - Parameters:
    ///   - filter: Narrows the window. Used by the live map to ask for nothing but
    ///     the drive in progress.
    ///   - minimumSegmentPoints: Segments shorter than this are dropped as noise.
    ///     Worth lowering when the window is a single drive that has only just
    ///     started, where the default would discard the first few positions.
    func track(
        carID: Int,
        every: Int = 10,
        maxPoints: Int = 24_000,
        filter: DateRangeFilter = .init(),
        minimumSegmentPoints: Int? = nil
    ) async throws -> [[CoordinateDTO]] {
        var query = [
            URLQueryItem(name: "every", value: String(every)),
            URLQueryItem(name: "max_points", value: String(maxPoints))
        ]
        if let minimumSegmentPoints {
            query.append(URLQueryItem(name: "min_segment_points", value: String(minimumSegmentPoints)))
        }
        query.append(contentsOf: filter.backendQuery)
        let response = try await get(
            "v1/vehicles/\(carID)/track",
            query: query,
            as: BackendEnvelope<BackendTrackDTO>.self
        )
        return response.data.segments.map { segment in
            segment.points.compactMap { pair in
                guard pair.count == 2 else { return nil }
                return CoordinateDTO(latitude: pair[0], longitude: pair[1])
            }
        }
    }

    func connectionTest() async throws -> ConnectionTestResult {
        let discovered = try await capabilities()
        let vehicles = try await cars()
        return ConnectionTestResult(
            reachable: true,
            authenticated: true,
            compatible: true,
            vehicleCount: vehicles.cars.count
        )
        // `discovered` is intentionally unused beyond proving the shape decoded;
        // the caller fetches capabilities separately when it needs them.
        _ = discovered
    }

    // MARK: - Transport

    private func get<T: Decodable & Sendable>(
        _ path: String,
        query: [URLQueryItem] = [],
        as type: T.Type
    ) async throws -> T {
        try await send("GET", path, query: query, as: type)
    }

    /// One request, with retries and the server's own error messages.
    ///
    /// Not `private`: the pairing calls live in their own file and go through this
    /// same path deliberately. A second request builder is a second place for the
    /// header rules, the retry policy and the problem-document handling to drift.
    func send<T: Decodable & Sendable>(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (any Encodable & Sendable)? = nil,
        as type: T.Type
    ) async throws -> T {
        guard var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false) else {
            throw ClientError.invalidConfiguration
        }
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw ClientError.invalidConfiguration }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        authentication.apply(to: &request)

        // A GET may be repeated freely. A POST may not: retrying an approval that
        // actually reached the server turns "already resolved" into a failure the
        // caller reports as one, having granted access.
        let maximumAttempts = method == "GET" ? 2 : 0
        var attempt = 0
        while true {
            do {
                try Task.checkCancellation()
                let (data, response) = try await transport.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw ClientError.transport }
                try Self.validate(http.statusCode, body: data, decoder: decoder)
                do {
                    return try decoder.decode(T.self, from: data)
                } catch is CancellationError { throw CancellationError() }
                catch { throw ClientError.decoding }
            } catch is CancellationError { throw CancellationError() }
            catch let error as ClientError {
                guard error.isRetryable, attempt < maximumAttempts else { throw error }
                attempt += 1
                try await Task.sleep(for: .milliseconds(250 * attempt))
            } catch {
                guard attempt < maximumAttempts else { throw ClientError.transport }
                attempt += 1
                try await Task.sleep(for: .milliseconds(250 * attempt))
            }
        }
    }

    /// Maps a status code to an error, preferring the server's own explanation.
    ///
    /// The backend answers failures as RFC 9457 problem documents, whose `detail`
    /// is written for a person — far more useful than a generic status message.
    private static func validate(_ code: Int, body: Data, decoder: JSONDecoder) throws {
        guard !(200..<300).contains(code) else { return }
        let problem = try? decoder.decode(BackendProblemDTO.self, from: body)
        switch code {
        case 401: throw ClientError.badToken
        case 403: throw ClientError.forbidden
        case 404: throw ClientError.notFound
        case 422: throw ClientError.serverMessage(problem?.detail ?? "The server rejected a parameter.")
        case 409: throw ClientError.serverMessage(problem?.detail ?? "That request is no longer valid.")
        case 429: throw ClientError.rateLimited
        case 500, 502, 503, 504:
            if let detail = problem?.detail { throw ClientError.serverMessage(detail) }
            throw ClientError.backendUnavailable
        default: throw ClientError.unexpectedStatus(code)
        }
    }

    private static var userAgent: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1"
        return "Tessalytics/\(version)"
    }
}

extension BackendEnvelope where T == BackendStateWrapperDTO {
    /// The app's status model, from the backend's own state body.
    ///
    /// Shared by the request route and the event stream. They used to each decode
    /// the body themselves, and only one of them decoded the shape the backend
    /// actually sends — so the stream connected, reported itself live, and threw
    /// every reading away, leaving a poll every thirty seconds as the only thing
    /// that moved the numbers.
    func statusData(carID: Int) -> StatusDataDTO {
        StatusDataDTO(
            car: CarReferenceDTO(carId: carID, carName: data.state.name),
            status: data.state.vehicleStatus,
            units: meta?.units?.unitsDTO
        )
    }
}

private extension ClientError {
    var isRetryable: Bool {
        switch self {
        case .transport, .backendUnavailable, .rateLimited: true
        default: false
        }
    }
}

private extension DateRangeFilter {
    /// The backend's snake_case parameters, replacing TeslaMateApi's camelCase.
    var backendQuery: [URLQueryItem] {
        var items: [URLQueryItem] = []
        let formatter = ISO8601DateFormatter()
        if let start { items.append(URLQueryItem(name: "start_date", value: formatter.string(from: start))) }
        if let end { items.append(URLQueryItem(name: "end_date", value: formatter.string(from: end))) }
        if let location = location?.nilIfEmpty { items.append(URLQueryItem(name: "location", value: location)) }
        if let minimumDistance { items.append(URLQueryItem(name: "min_distance", value: String(minimumDistance))) }
        if let maximumDistance { items.append(URLQueryItem(name: "max_distance", value: String(maximumDistance))) }
        return items
    }
}
