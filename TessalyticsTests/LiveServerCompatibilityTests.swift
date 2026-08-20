import XCTest
@testable import Tessalytics

final class LiveServerCompatibilityTests: XCTestCase {
    func testLiveSummaryEndpointsDecode() async throws {
        let client = try await liveClient()
        let cars = try await client.cars()
        let carID = try XCTUnwrap(cars.cars.first?.carId)

        _ = try await client.car(carID: carID)
        _ = try await client.status(carID: carID)
        _ = try await client.drives(carID: carID, page: 1, show: 3, filter: .init())
        _ = try await client.charges(carID: carID, page: 1, show: 3, filter: .init())
        _ = try await client.batteryHealth(carID: carID)
        _ = try await client.updates(carID: carID)
        _ = try await client.globalSettings()
    }

    func testLiveHistoryDetailsDecode() async throws {
        let client = try await liveClient()
        let cars = try await client.cars()
        let carID = try XCTUnwrap(cars.cars.first?.carId)
        let drives = try await client.drives(carID: carID, page: 1, show: 1, filter: .init())
        let charges = try await client.charges(carID: carID, page: 1, show: 1, filter: .init())

        if let driveID = drives.drives.first?.driveId {
            _ = try await client.drive(carID: carID, driveID: driveID)
        }
        if let chargeID = charges.charges.first?.chargeId {
            _ = try await client.charge(carID: carID, chargeID: chargeID)
        }
    }

    func testLiveCurrentChargeIsDataOrNotFound() async throws {
        let client = try await liveClient()
        let cars = try await client.cars()
        let carID = try XCTUnwrap(cars.cars.first?.carId)

        do {
            _ = try await client.currentCharge(carID: carID)
        } catch ClientError.notFound {
            // A parked, unplugged vehicle has no active charging session.
        }
    }

    // MARK: - Tessalytics Backend

    /// Exercises the same surface against a live Tessalytics Backend.
    ///
    /// Skipped unless TESSALYTICS_BACKEND_URL and TESSALYTICS_BACKEND_TOKEN are
    /// set, so it never fails a normal run.
    func testLiveBackendDetectsAndDecodes() async throws {
        let client = try liveBackendClient()

        let capabilities = try await client.capabilities()
        XCTAssertEqual(capabilities.service, "Tessalytics Backend")

        let cars = try await client.cars()
        let carID = try XCTUnwrap(cars.cars.first?.carId)

        let status = try await client.status(carID: carID).status
        // The point of the migration: a reading the server does not have comes
        // back absent rather than as a confident false.
        if status.reportsLiveTelemetry == false, status.carStatus?.locked == nil {
            XCTAssertNil(status.carStatus?.sentryMode, "Unknown lock state must not carry a known sentry state")
        }

        _ = try await client.drives(carID: carID, page: 1, show: 3, filter: .init())
        _ = try await client.charges(carID: carID, page: 1, show: 3, filter: .init())
        _ = try await client.batteryHealth(carID: carID)
        _ = try await client.updates(carID: carID)
        _ = try await client.globalSettings()

        let totals = try await client.totals(carID: carID)
        XCTAssertNotNil(totals.driving?.drives)
    }

    func testLiveProbeAcceptsTheBackendAndCountsVehicles() async throws {
        let (baseURL, token) = try liveBackendCredentials()
        let result = try await ServerProbe.test(baseURL: baseURL, authentication: .bearer(token))
        XCTAssertTrue(result.reachable)
        XCTAssertTrue(result.authenticated)
        XCTAssertTrue(result.compatible)
        XCTAssertGreaterThan(result.vehicleCount, 0)
        XCTAssertEqual(result.capabilities?.service, "Tessalytics Backend")
    }

    private func liveBackendCredentials() throws -> (URL, String) {
        let environment = ProcessInfo.processInfo.environment
        guard let rawURL = environment["TESSALYTICS_BACKEND_URL"],
              let baseURL = URL(string: rawURL),
              let token = environment["TESSALYTICS_BACKEND_TOKEN"],
              !token.isEmpty else {
            throw XCTSkip("Live Tessalytics Backend credentials are not configured.")
        }
        return (baseURL, token)
    }

    private func liveBackendClient() throws -> TessalyticsBackendClient {
        let (baseURL, token) = try liveBackendCredentials()
        return TessalyticsBackendClient(baseURL: baseURL, authentication: .bearer(token))
    }

    /// A client for the configured server.
    private func liveClient() async throws -> any VehicleDataAPI {
        let environment = ProcessInfo.processInfo.environment
        guard let rawURL = environment["TESSALYTICS_TEST_BASE_URL"],
              let baseURL = URL(string: rawURL),
              let token = environment["TESSALYTICS_TEST_API_TOKEN"],
              !token.isEmpty else {
            throw XCTSkip("Live server credentials are not configured.")
        }
        return TessalyticsBackendClient(baseURL: baseURL, authentication: .bearer(token))
    }
}
