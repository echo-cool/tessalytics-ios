import XCTest
@testable import Tessalytics

final class OwnerAPIClientTests: XCTestCase {
    func testValidAccessTokenIsUsedWithoutRefresh() async throws {
        let store = MemoryOwnerCredentialStore(OwnerAPICredentials(
            accessToken: "current-access",
            refreshToken: "current-refresh",
            expiresAt: .now.addingTimeInterval(3_600),
            region: .global
        ))
        let transport = OwnerMockTransport(scenario: .vehicles)
        let session = OwnerAPISession(store: store, transport: transport)

        let vehicles = try await session.vehicles()

        XCTAssertEqual(vehicles.first?.displayName, "Roadrunner")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer current-access")
        XCTAssertTrue(requests[0].value(forHTTPHeaderField: "X-Tesla-User-Agent")?.contains("Tessalytics") == true)
        XCTAssertEqual(requests[0].url?.host, "owner-api.teslamotors.com")
    }

    func testExpiredAccessTokenRefreshesAndPersistsRotatedPair() async throws {
        let store = MemoryOwnerCredentialStore(OwnerAPICredentials(
            accessToken: "expired-access",
            refreshToken: "original-refresh",
            expiresAt: .now.addingTimeInterval(-60),
            region: .global
        ))
        let transport = OwnerMockTransport(scenario: .refreshThenVehicles)
        let session = OwnerAPISession(store: store, transport: transport)

        _ = try await session.vehicles()

        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].url?.absoluteString, "https://auth.tesla.com/oauth2/v3/token")
        let body = try XCTUnwrap(requests[0].httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json["grant_type"], "refresh_token")
        XCTAssertEqual(json["client_id"], "ownerapi")
        XCTAssertEqual(json["scope"], "openid email offline_access")
        XCTAssertEqual(json["refresh_token"], "original-refresh")
        XCTAssertTrue(requests[0].value(forHTTPHeaderField: "X-Tesla-User-Agent")?.contains("TeslaApp/4.12.0") == true)
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer rotated-access")
        XCTAssertEqual(try store.credentials()?.refreshToken, "rotated-refresh")
    }

    func testUnauthorizedRequestRefreshesOnceAndRetries() async throws {
        let store = MemoryOwnerCredentialStore(OwnerAPICredentials(
            accessToken: "rejected-access",
            refreshToken: "refresh-me",
            expiresAt: .now.addingTimeInterval(3_600),
            region: .global
        ))
        let transport = OwnerMockTransport(scenario: .unauthorizedThenRefresh)
        let session = OwnerAPISession(store: store, transport: transport)

        let vehicles = try await session.vehicles()

        XCTAssertEqual(vehicles.count, 1)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer rotated-access")
    }

    func testConcurrentExpiredRequestsShareOneRefresh() async throws {
        let store = MemoryOwnerCredentialStore(OwnerAPICredentials(
            accessToken: "expired",
            refreshToken: "single-use-refresh",
            expiresAt: .now.addingTimeInterval(-60),
            region: .global
        ))
        let transport = OwnerMockTransport(scenario: .concurrentRefresh)
        let session = OwnerAPISession(store: store, transport: transport)

        async let first = session.vehicles()
        async let second = session.vehicles()
        _ = try await (first, second)

        let requests = await transport.requests
        XCTAssertEqual(requests.filter { $0.url?.host == "auth.tesla.com" }.count, 1)
        XCTAssertEqual(requests.filter { $0.url?.host == "owner-api.teslamotors.com" }.count, 2)
    }

    func testCommandUsesExpectedEndpointAndBody() async throws {
        let store = MemoryOwnerCredentialStore(OwnerAPICredentials(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: .now.addingTimeInterval(3_600),
            region: .global
        ))
        let transport = OwnerMockTransport(scenario: .command)
        let session = OwnerAPISession(store: store, transport: transport)

        try await session.send(.openTrunk, vehicleID: 42)

        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/1/vehicles/42/command/actuate_trunk")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json, ["which_trunk": "rear"])
    }

    func testVehicleDataMapsToDashboardStatus() throws {
        let json = Data(Self.vehicleDataJSON.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let data = try decoder.decode(OwnerAPIEnvelope<OwnerVehicleData>.self, from: json).response
        let status = data.tessalyticsStatus

        XCTAssertEqual(status.displayName, "Roadrunner")
        XCTAssertEqual(status.batteryDetails?.batteryLevel, 72)
        XCTAssertEqual(status.carStatus?.locked, true)
        XCTAssertEqual(status.carStatus?.windowsOpen, true)
        XCTAssertEqual(status.climateDetails?.insideTemp, 21.5)
        XCTAssertEqual(status.chargingDetails?.chargerPower, 7)
        XCTAssertEqual(status.carGeodata?.location?.latitude, 37.3)
        XCTAssertEqual(data.tessalyticsUnits.unitOfLength, "mi")
    }

    private static let vehicleDataJSON = """
    {
      "response": {
        "id": 42,
        "vin": "5YJTEST",
        "display_name": "Roadrunner",
        "state": "online",
        "drive_state": {"latitude": 37.3, "longitude": -122.0, "heading": 90, "power": 0, "shift_state": null, "speed": 0},
        "climate_state": {"inside_temp": 21.5, "outside_temp": 16.0, "is_climate_on": false, "is_preconditioning": false, "climate_keeper_mode": "off"},
        "charge_state": {"battery_level": 72, "usable_battery_level": 71, "battery_range": 220.0, "est_battery_range": 225.0, "ideal_battery_range": 240.0, "charging_state": "Charging", "charge_energy_added": 4.2, "charge_limit_soc": 80, "charge_port_door_open": true, "charger_actual_current": 32, "charger_phases": 1, "charger_power": 7, "charger_voltage": 240, "time_to_full_charge": 1.5},
        "vehicle_state": {"locked": true, "sentry_mode": false, "odometer": 12000.5, "car_version": "2026.20", "df": 0, "dr": 0, "pf": 0, "pr": 0, "fd": 1, "fp": 0, "rd": 0, "rp": 0, "ft": 0, "rt": 0, "tpms_pressure_fl": 2.9, "tpms_pressure_fr": 2.9, "tpms_pressure_rl": 3.0, "tpms_pressure_rr": 3.0},
        "vehicle_config": {"car_type": "modely", "trim_badging": "Long Range"},
        "gui_settings": {"gui_distance_units": "mi/hr", "gui_temperature_units": "C"}
      }
    }
    """
}

private final class MemoryOwnerCredentialStore: OwnerCredentialStore, @unchecked Sendable {
    private var value: OwnerAPICredentials?
    init(_ value: OwnerAPICredentials? = nil) { self.value = value }
    func save(_ credentials: OwnerAPICredentials) throws { value = credentials }
    func credentials() throws -> OwnerAPICredentials? { value }
    func delete() throws { value = nil }
}

private actor OwnerMockTransport: HTTPTransport {
    enum Scenario: Equatable, Sendable { case vehicles, refreshThenVehicles, unauthorizedThenRefresh, concurrentRefresh, command }
    let scenario: Scenario
    private(set) var requests: [URLRequest] = []
    private var ownerRequestCount = 0

    init(scenario: Scenario) { self.scenario = scenario }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let isAuthentication = request.url?.host?.hasPrefix("auth.tesla") == true
        if isAuthentication {
            if scenario == .concurrentRefresh { try await Task.sleep(for: .milliseconds(100)) }
            return response(request, 200, #"{"access_token":"rotated-access","refresh_token":"rotated-refresh","expires_in":28800,"token_type":"bearer"}"#)
        }
        ownerRequestCount += 1
        if scenario == .unauthorizedThenRefresh && ownerRequestCount == 1 {
            return response(request, 401, "{}")
        }
        if scenario == .command {
            return response(request, 200, #"{"response":{"result":true,"reason":""}}"#)
        }
        return response(request, 200, #"{"response":[{"id":42,"vehicle_id":84,"vin":"5YJTEST","display_name":"Roadrunner","state":"online"}],"count":1}"#)
    }

    private func response(_ request: URLRequest, _ status: Int, _ body: String) -> (Data, URLResponse) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/2", headerFields: nil)!
        return (Data(body.utf8), response)
    }
}
