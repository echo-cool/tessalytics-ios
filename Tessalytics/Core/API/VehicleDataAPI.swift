//  The vocabulary every caller shares: the data protocol, its errors, and the
//  check that a URL really is a Tessalytics Backend.
//
//  This file replaced TeslaMateAPIClient.swift. The app spoke TeslaMateApi's HTTP
//  surface directly until the backend took over every endpoint it had; keeping a
//  second client afterwards meant two code paths for one job, and every fix had
//  to be made twice.

import Foundation

protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {}

protocol VehicleDataAPI: Sendable {
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
    /// The server explained the failure itself.
    ///
    /// Tessalytics Backend answers errors as RFC 9457 problem documents whose
    /// `detail` is written for a person — "Parameter 'units' must be one of …"
    /// beats any message this app could invent for a 422.
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Enter a valid server URL. HTTPS is required unless local HTTP is explicitly enabled."
        case .transport: "The server could not be reached. Check the address and network connection."
        case .badToken: "Authentication failed. Check the configured credentials."
        case .forbidden: "This operation is disabled or forbidden by the server."
        case .notFound: "The requested vehicle or record is no longer available."
        case .rateLimited: "The server is receiving too many requests. Try again shortly."
        case .backendUnavailable: "The server or one of its data sources is temporarily unavailable."
        case .decoding: "The server responded, but its data is not compatible with this version of Tessalytics."
        case .unexpectedStatus(let code): "The server returned an unexpected response (HTTP \(code))."
        case .serverMessage(let message): message
        }
    }
}

struct ConnectionTestResult: Sendable {
    let reachable: Bool
    let authenticated: Bool
    let compatible: Bool
    let vehicleCount: Int
    /// What the server said it supports.
    var capabilities: BackendCapabilities?
}

/// Verifies that a URL is a Tessalytics Backend before a profile is saved.
///
/// The `/v1` discovery document is a positive identification, so a wrong address
/// or a TeslaMate install without this service fails here rather than after
/// onboarding with an empty dashboard.
enum ServerProbe {
    static func test(
        baseURL: URL,
        authentication: Authentication,
        transport: any HTTPTransport = URLSession.shared
    ) async throws -> ConnectionTestResult {
        let backend = TessalyticsBackendClient(
            baseURL: baseURL, authentication: authentication, transport: transport, timeout: 20
        )
        let capabilities = try await backend.capabilities()
        let vehicles = try await backend.cars()
        return ConnectionTestResult(
            reachable: true,
            authenticated: true,
            compatible: true,
            vehicleCount: vehicles.cars.count,
            capabilities: capabilities
        )
    }
}
