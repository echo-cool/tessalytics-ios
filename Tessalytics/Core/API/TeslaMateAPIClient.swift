import Foundation

protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {}

protocol TeslaMateAPI: Sendable {
    func ping() async throws
    func cars() async throws -> CarsDataDTO
    func car(carID: Int) async throws -> CarsDataDTO
    func status(carID: Int) async throws -> StatusDataDTO
    func drives(carID: Int, page: Int, show: Int, filter: DateRangeFilter) async throws -> DrivesDataDTO
    func drive(carID: Int, driveID: Int) async throws -> DriveDataDTO
    func charges(carID: Int, page: Int, show: Int, filter: DateRangeFilter) async throws -> ChargesDataDTO
    func charge(carID: Int, chargeID: Int) async throws -> ChargeDataDTO
    func currentCharge(carID: Int) async throws -> ChargeDataDTO
    func batteryHealth(carID: Int) async throws -> BatteryHealthDataDTO
    func updates(carID: Int) async throws -> UpdatesDataDTO
    func globalSettings() async throws -> GlobalSettingsDataDTO
}

enum ClientError: Error, Equatable, LocalizedError, Sendable {
    case invalidConfiguration
    case transport
    case badToken
    case forbidden
    case notFound
    case rateLimited
    case backendUnavailable
    case decoding
    case unexpectedStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Enter a valid server URL. HTTPS is required unless local HTTP is explicitly enabled."
        case .transport: "The server could not be reached. Check the address and network connection."
        case .badToken: "Authentication failed. Check the configured credentials."
        case .forbidden: "This operation is disabled or forbidden by the server."
        case .notFound: "The requested vehicle or record is no longer available."
        case .rateLimited: "The server is receiving too many requests. Try again shortly."
        case .backendUnavailable: "TeslaMateApi or one of its data sources is temporarily unavailable."
        case .decoding: "The server responded, but its data is not compatible with this version of Tessalytics."
        case .unexpectedStatus(let code): "The server returned an unexpected response (HTTP \(code))."
        }
    }
}

struct ConnectionTestResult: Sendable {
    let reachable: Bool
    let authenticated: Bool
    let compatible: Bool
    let vehicleCount: Int
}

struct TeslaMateAPIClient: TeslaMateAPI, Sendable {
    let baseURL: URL
    let authentication: Authentication
    private let transport: any HTTPTransport
    private let decoder: JSONDecoder
    private let timeout: TimeInterval

    init(baseURL: URL, authentication: Authentication, transport: any HTTPTransport = URLSession.shared,
         timeout: TimeInterval = 20) {
        self.baseURL = baseURL
        self.authentication = authentication
        self.transport = transport
        self.timeout = timeout
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    func ping() async throws { let _: PingResponse = try await request("api/ping", authenticated: false, envelope: false) }
    func cars() async throws -> CarsDataDTO { try await request("api/v1/cars") }
    func car(carID: Int) async throws -> CarsDataDTO { try await request("api/v1/cars/\(carID)") }
    func status(carID: Int) async throws -> StatusDataDTO { try await request("api/v1/cars/\(carID)/status") }
    func drive(carID: Int, driveID: Int) async throws -> DriveDataDTO { try await request("api/v1/cars/\(carID)/drives/\(driveID)") }
    func charge(carID: Int, chargeID: Int) async throws -> ChargeDataDTO { try await request("api/v1/cars/\(carID)/charges/\(chargeID)") }
    func currentCharge(carID: Int) async throws -> ChargeDataDTO { try await request("api/v1/cars/\(carID)/charges/current") }
    func batteryHealth(carID: Int) async throws -> BatteryHealthDataDTO { try await request("api/v1/cars/\(carID)/battery-health") }
    func updates(carID: Int) async throws -> UpdatesDataDTO { try await request("api/v1/cars/\(carID)/updates") }
    func globalSettings() async throws -> GlobalSettingsDataDTO { try await request("api/v1/globalsettings") }

    func drives(carID: Int, page: Int, show: Int = 30, filter: DateRangeFilter = .init()) async throws -> DrivesDataDTO {
        var query = historyQuery(page: page, show: show, filter: filter)
        if let minimum = filter.minimumDistance { query.append(URLQueryItem(name: "minDistance", value: String(minimum))) }
        if let maximum = filter.maximumDistance { query.append(URLQueryItem(name: "maxDistance", value: String(maximum))) }
        return try await request("api/v1/cars/\(carID)/drives", query: query)
    }

    func charges(carID: Int, page: Int, show: Int = 30, filter: DateRangeFilter = .init()) async throws -> ChargesDataDTO {
        try await request("api/v1/cars/\(carID)/charges", query: historyQuery(page: page, show: show, filter: filter))
    }

    func testConnection() async throws -> ConnectionTestResult {
        try await ping()
        let cars = try await cars()
        return ConnectionTestResult(reachable: true, authenticated: true, compatible: true, vehicleCount: cars.cars.count)
    }

    private func historyQuery(page: Int, show: Int, filter: DateRangeFilter) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "page", value: String(max(page, 1))),
                     URLQueryItem(name: "show", value: String(min(max(show, 1), 100)))]
        let formatter = ISO8601DateFormatter()
        if let start = filter.start { items.append(URLQueryItem(name: "startDate", value: formatter.string(from: start))) }
        if let end = filter.end { items.append(URLQueryItem(name: "endDate", value: formatter.string(from: end))) }
        if let location = filter.location, !location.isEmpty { items.append(URLQueryItem(name: "location", value: location)) }
        return items
    }

    private func request<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem] = [],
                                                   authenticated: Bool = true, envelope: Bool = true) async throws -> T {
        guard var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false) else {
            throw ClientError.invalidConfiguration
        }
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw ClientError.invalidConfiguration }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated { applyAuthentication(to: &request) }

        var attempt = 0
        while true {
            do {
                try Task.checkCancellation()
                let (data, response) = try await transport.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw ClientError.transport }
                try validate(http.statusCode)
                do {
                    if envelope { return try decoder.decode(Envelope<T>.self, from: data).data }
                    return try decoder.decode(T.self, from: data)
                } catch is CancellationError { throw CancellationError() }
                catch { throw ClientError.decoding }
            } catch is CancellationError { throw CancellationError() }
            catch let error as ClientError {
                guard error.isTransient, attempt < 2 else { throw error }
                attempt += 1
                try await Task.sleep(for: .milliseconds(250 * attempt))
            } catch {
                guard attempt < 2 else { throw ClientError.transport }
                attempt += 1
                try await Task.sleep(for: .milliseconds(250 * attempt))
            }
        }
    }

    private func applyAuthentication(to request: inout URLRequest) {
        switch authentication {
        case .bearer(let token): request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .basic(let username, let password):
            let encoded = Data("\(username):\(password)".utf8).base64EncodedString()
            request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        case .none: break
        }
    }

    private func validate(_ code: Int) throws {
        switch code {
        case 200..<300: return
        case 401: throw ClientError.badToken
        case 403: throw ClientError.forbidden
        case 404: throw ClientError.notFound
        case 429: throw ClientError.rateLimited
        case 500, 502, 503, 504: throw ClientError.backendUnavailable
        default: throw ClientError.unexpectedStatus(code)
        }
    }
}

private struct PingResponse: Decodable, Sendable { let message: String? }
private extension ClientError {
    var isTransient: Bool { self == .transport || self == .backendUnavailable || self == .rateLimited }
}
