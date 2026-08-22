import XCTest
@testable import Tessalytics

/// Tests for the Tessalytics Backend client and its mapping onto the app's models.
///
/// The property that matters most: a reading the backend reports as `null` must
/// arrive as `nil`, not as `false` or `0`. That is the entire reason for moving
/// off TeslaMateApi, and a mapping that quietly substituted defaults would undo
/// it silently.
final class BackendClientTests: XCTestCase {
    private let baseURL = URL(string: "https://backend.invalid")!

    private func client(_ responses: [String: String]) -> TessalyticsBackendClient {
        TessalyticsBackendClient(
            baseURL: baseURL,
            authentication: .bearer("token"),
            transport: StubTransport(responses: responses)
        )
    }

    // MARK: - Null handling

    func testAbsentLiveReadingsStayNil() async throws {
        // What the backend sends when the MQTT cache has heard nothing.
        let body = """
        {"data":{"state":{"vehicle_id":1,"state":"offline","name":"Aurora",
        "security":{"locked":null,"sentry_mode":null,"windows_open":null,
        "doors_open":null,"trunk_open":null,"frunk_open":null},
        "battery":{"level":79,"usable_level":79,"range":260.8,"range_rated":260.8,
        "range_ideal":null,"range_estimated":null},
        "charging":{"plugged_in":null,"state":null,"charge_limit":null,"power":null},
        "tyres":{"front_left":{"pressure":null,"warning":null}},
        "climate":{"inside_temperature":null,"outside_temperature":null},
        "driving":{"odometer":21068.6}},
        "meta":{"source":"database"}}}
        """
        let status = try await client(["/v1/vehicles/1/state": body]).status(carID: 1).status

        // Every one of these is `false` or `0` coming from TeslaMateApi.
        XCTAssertNil(status.carStatus?.locked)
        XCTAssertNil(status.carStatus?.sentryMode)
        XCTAssertNil(status.carStatus?.doorsOpen)
        XCTAssertNil(status.chargingDetails?.pluggedIn)
        XCTAssertNil(status.chargingDetails?.chargeLimitSoc)
        XCTAssertNil(status.tpmsDetails?.tpmsPressureFl)
        XCTAssertNil(status.climateDetails?.insideTemp)

        // And the readings that are present survive.
        XCTAssertEqual(status.batteryDetails?.batteryLevel, 79)
        XCTAssertEqual(status.odometer ?? 0, 21_068.6, accuracy: 0.01)
        XCTAssertEqual(status.state, "offline")
    }

    func testPresentLiveReadingsAreCarriedThrough() async throws {
        let body = """
        {"data":{"state":{"vehicle_id":1,"state":"online",
        "security":{"locked":true,"sentry_mode":false,"doors_open":false},
        "charging":{"plugged_in":true,"state":"Charging","charge_limit":80,"power":11.5,"voltage":240},
        "tyres":{"front_left":{"pressure":2.75,"warning":false}},
        "battery":{"level":54,"usable_level":53}}},"meta":{"source":"mixed"}}
        """
        let status = try await client(["/v1/vehicles/1/state": body]).status(carID: 1).status

        XCTAssertEqual(status.carStatus?.locked, true)
        XCTAssertEqual(status.carStatus?.sentryMode, false)
        XCTAssertEqual(status.chargingDetails?.chargeLimitSoc, 80)
        XCTAssertEqual(status.chargingDetails?.chargerVoltage, 240)
        XCTAssertEqual(status.tpmsDetails?.tpmsPressureFl ?? 0, 2.75, accuracy: 0.001)
        // The cold-weather buffer is derivable because both levels are present.
        XCTAssertEqual(status.batteryDetails?.batteryLevel, 54)
        XCTAssertEqual(status.batteryDetails?.usableBatteryLevel, 53)
    }

    // MARK: - Mapping

    func testVehiclesMapOntoCarDTOs() async throws {
        let body = """
        {"data":{"vehicles":[{"id":1,"name":"Aurora","model":"3","model_name":"Model 3",
        "trim":"74","rated_consumption":219.0,
        "coverage":{"drives":798,"charges":87,"updates":9}}]},
        "meta":{"units":{"length":"mi","temperature":"C","pressure":"psi","range":"rated"}}}
        """
        let cars = try await client(["/v1/vehicles": body]).cars()
        let car = try XCTUnwrap(cars.cars.first)

        XCTAssertEqual(car.carId, 1)
        XCTAssertEqual(car.name, "Aurora")
        XCTAssertEqual(car.carDetails?.model, "3")
        XCTAssertEqual(car.teslamateStats?.totalDrives, 798)
        // Wh per unit distance becomes kWh, which is the app's convention.
        XCTAssertEqual(car.carDetails?.efficiency ?? 0, 0.219, accuracy: 0.0001)
    }

    func testDrivesPreferGeofenceNamesOverRawAddresses() async throws {
        let body = """
        {"data":{"drives":[{"id":841,"start_date":"2026-08-19T22:15:00",
        "end_date":"2026-08-19T22:32:00","duration_minutes":17,"distance":6.7,
        "odometer":{"start":21050.0,"end":21056.7},
        "speed":{"max":52.0,"average":23.6},
        "battery":{"start_level":80,"end_level":78},
        "range":{"start":260.0,"end":253.0,"consumed":7.0},
        "start":{"address":"Hamilton Avenue 4785, San Jose","geofence":null},
        "end":{"address":"2479 Crystal Dr","geofence":"Home"}}]},
        "meta":{"page":{"limit":50,"returned":1,"has_more":false,"next":null}}}
        """
        let drives = try await client(["/v1/vehicles/1/drives": body]).drives(carID: 1, page: 1, show: 50, filter: .init())
        let drive = try XCTUnwrap(drives.drives.first)

        XCTAssertEqual(drive.driveId, 841)
        XCTAssertEqual(drive.odometerDetails?.odometerDistance ?? 0, 6.7, accuracy: 0.001)
        // A geofence is what the owner named the place; the raw address is a
        // fallback, not a preference.
        XCTAssertEqual(drive.endAddress, "Home")
        XCTAssertEqual(drive.startAddress, "Hamilton Avenue 4785, San Jose")
        XCTAssertEqual(drive.batteryDetails?.endBatteryLevel, 78)
        XCTAssertEqual(drive.rangeRated?.endRange ?? 0, 253.0, accuracy: 0.001)
    }

    func testDriveSamplesWithoutCoordinatesAreDropped() async throws {
        // A sample without a fix cannot be drawn, and plotting it at (0,0) would
        // put a route leg in the Gulf of Guinea.
        let body = """
        {"data":{"drive":{"id":5,"start_date":"2026-08-19T10:00:00","distance":3.0,
        "samples":[{"date":"2026-08-19T10:00:00","latitude":37.3,"longitude":-121.9,"speed":10},
                   {"date":"2026-08-19T10:01:00","latitude":null,"longitude":null,"speed":20},
                   {"date":"2026-08-19T10:02:00","latitude":37.4,"longitude":-121.8,"speed":30}]}},
        "meta":{}}
        """
        let detail = try await client(["/v1/vehicles/1/drives/5": body]).drive(carID: 1, driveID: 5).drive
        XCTAssertEqual(detail.driveDetails.count, 2)
        XCTAssertEqual(detail.driveDetails.map(\.latitude), [37.3, 37.4])
    }

    func testChargesMapEnergyCostAndPosition() async throws {
        let body = """
        {"data":{"charges":[{"id":87,"start_date":"2026-08-19T14:37:00",
        "end_date":"2026-08-19T14:56:30","duration_minutes":20,
        "energy":{"added":20.52,"used":22.05,"efficiency":0.9306},
        "cost":{"total":null,"per_kwh":null},
        "battery":{"start_level":54,"end_level":83},
        "range":{"start":178.6,"end":272.5,"added":93.9},
        "location":{"address":"Tesla Supercharger, San Jose","geofence":null,
                    "latitude":37.300528,"longitude":-121.981734,"odometer":21058.9}}]},
        "meta":{}}
        """
        let charges = try await client(["/v1/vehicles/1/charges": body]).charges(carID: 1, page: 1, show: 50, filter: .init())
        let charge = try XCTUnwrap(charges.charges.first)

        XCTAssertEqual(charge.chargeEnergyAdded ?? 0, 20.52, accuracy: 0.001)
        // A null cost stays nil rather than becoming a misleading 0.00.
        XCTAssertNil(charge.cost)
        XCTAssertEqual(charge.odometer ?? 0, 21_058.9, accuracy: 0.01)
        XCTAssertEqual(charge.batteryDetails?.endBatteryLevel, 83)
        XCTAssertEqual(charge.rangeRated?.endRange ?? 0, 272.5, accuracy: 0.01)
    }

    func testActiveChargeAbsenceBecomesNotFound() async throws {
        // The backend answers `{"charge": null}`, which is the better contract,
        // but the app's protocol expresses "nothing charging" as a throw.
        let body = #"{"data":{"charge":null},"meta":{}}"#
        do {
            _ = try await client(["/v1/vehicles/1/charges/active": body]).currentCharge(carID: 1)
            XCTFail("Expected notFound for an absent active charge")
        } catch ClientError.notFound {
            // Expected.
        }
    }

    func testBatteryHealthConvertsConsumptionForCapacityModelling() async throws {
        // The app models capacity with kWh per 100 km. The backend reports Wh per
        // display unit, which here is miles.
        let body = """
        {"data":{"battery":{"capacity":{"when_new":74.29,"now":72.35,"lost":1.94,"retained":0.9739},
        "range":{"when_new":337.17,"now":330.15,"lost":7.02,"retained":0.9792},
        "rated_consumption":219.0,"observations":87,"is_estimate":true}},
        "meta":{"units":{"length":"mi","temperature":"C","pressure":"psi","range":"rated"}}}
        """
        let health = try await client(["/v1/vehicles/1/battery": body]).batteryHealth(carID: 1).batteryHealth

        XCTAssertEqual(health.maxCapacity ?? 0, 74.29, accuracy: 0.01)
        XCTAssertEqual(health.currentCapacity ?? 0, 72.35, accuracy: 0.01)
        XCTAssertEqual(health.maxRange ?? 0, 337.17, accuracy: 0.01)
        // 219 Wh/mi is 136.1 Wh/km, so 13.61 kWh/100km — the figure TeslaMateApi
        // reports as rated_efficiency, which validates the conversion.
        XCTAssertEqual(health.ratedEfficiency ?? 0, 13.61, accuracy: 0.05)
        XCTAssertEqual(health.batteryHealthPercentage ?? 0, 97.39, accuracy: 0.05)
    }

    func testTotalsDecode() async throws {
        let body = """
        {"data":{"totals":{"driving":{"drives":798,"distance_logged":4323.1,
        "odometer":21068.6,"distance_unlogged":928.8,"coverage":0.8232},
        "charging":{"charges":87,"energy_added":1102.8,"energy_used":1146.08,
        "efficiency":0.9622,"cycles":14.82,"cost_total":84.6,"priced_charges":40},
        "updates":9}},"meta":{}}
        """
        let totals = try await client(["/v1/vehicles/1/totals": body]).totals(carID: 1)
        XCTAssertEqual(totals.driving?.drives, 798)
        XCTAssertEqual(totals.charging?.cycles ?? 0, 14.82, accuracy: 0.01)
        XCTAssertEqual(totals.driving?.coverage ?? 0, 0.8232, accuracy: 0.0001)
    }

    func testServerTotalsOverrideLocallySummedFigures() async throws {
        // The local sums only cover whatever history this device has paged.
        var statistics = FleetStatistics()
        statistics.drives = FleetStatistics.DriveStats(
            loggedDistance: 100, odometer: 200, firstLoggedOdometer: 0, driveCount: 5
        )
        statistics.isComplete = false

        let body = """
        {"data":{"totals":{"driving":{"drives":798,"distance_logged":4323.1,
        "odometer":21068.6,"distance_unlogged":928.8,"coverage":0.8232},
        "charging":{"charges":87,"energy_added":1102.8,"energy_used":1146.08,"cycles":14.82}}},
        "meta":{}}
        """
        let totals = try await client(["/v1/vehicles/1/totals": body]).totals(carID: 1)
        statistics.applyServerTotals(totals)

        XCTAssertEqual(statistics.drives.driveCount, 798)
        XCTAssertEqual(statistics.drives.unloggedDistance ?? 0, 928.8, accuracy: 0.1)
        XCTAssertEqual(statistics.drives.coverage ?? 0, 0.8232, accuracy: 0.0001)
        XCTAssertEqual(statistics.charging.cycles(capacityNew: nil) ?? 0, 14.82, accuracy: 0.01)
        // Server totals are complete by construction.
        XCTAssertTrue(statistics.isComplete)
    }

    // MARK: - Discovery and errors

    func testCapabilitiesIdentifyTheBackend() async throws {
        let body = """
        {"data":{"service":"Tessalytics Backend","version":"0.1.0",
        "capabilities":{"resources":["vehicles","state","positions","states"],
        "analytics":{"queries":182},"actions":{"enabled":true,"upstream":"http://x"},
        "live_state":{"enabled":true,"connected":true},
        "units":["teslamate","metric","imperial","raw"]}}}
        """
        let capabilities = try await client(["/v1": body]).capabilities()
        XCTAssertEqual(capabilities.service, "Tessalytics Backend")
        XCTAssertTrue(capabilities.supportsActions)
        XCTAssertTrue(capabilities.supportsLiveState)
        XCTAssertEqual(capabilities.analyticsQueryCount, 182)
    }

    func testAProblemDocumentsDetailBecomesTheUserFacingMessage() async throws {
        let problem = """
        {"type":"https://tessalytics.dev/errors/invalid-parameter","title":"Invalid parameter",
        "status":422,"detail":"Parameter 'units' must be one of teslamate, metric, imperial, raw.",
        "instance":"/v1/vehicles/1/drives"}
        """
        let stub = StubTransport(responses: ["/v1/vehicles": problem], statusCode: 422)
        let subject = TessalyticsBackendClient(baseURL: baseURL, authentication: .bearer("t"), transport: stub)
        do {
            _ = try await subject.cars()
            XCTFail("Expected a failure")
        } catch let error as ClientError {
            // The server wrote a better message than the app could invent.
            XCTAssertEqual(
                error.errorDescription,
                "Parameter 'units' must be one of teslamate, metric, imperial, raw."
            )
        }
    }

    func testAnUnauthorizedResponseIsABadTokenNotAGenericFailure() async throws {
        let stub = StubTransport(responses: ["/v1/vehicles": "{}"], statusCode: 401)
        let subject = TessalyticsBackendClient(baseURL: baseURL, authentication: .bearer("wrong"), transport: stub)
        do {
            _ = try await subject.cars()
            XCTFail("Expected a failure")
        } catch ClientError.badToken {
            // Expected: the UI can tell the user to check the token.
        }
    }

    func testTheBearerTokenIsSent() async throws {
        let stub = StubTransport(responses: ["/v1/vehicles": #"{"data":{"vehicles":[]},"meta":{}}"#])
        let subject = TessalyticsBackendClient(baseURL: baseURL, authentication: .bearer("secret"), transport: stub)
        _ = try await subject.cars()
        XCTAssertEqual(stub.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
    }

    func testUnitsAreRequestedFromTheServerRatherThanConvertedLocally() async throws {
        let stub = StubTransport(responses: ["/v1/vehicles/1/state": #"{"data":{"state":{}},"meta":{}}"#])
        let subject = TessalyticsBackendClient(baseURL: baseURL, authentication: .bearer("t"), transport: stub)
        _ = try await subject.status(carID: 1)
        let query = stub.lastRequest?.url?.query ?? ""
        XCTAssertTrue(query.contains("units=teslamate"), "Expected the install's own units, got \(query)")
    }
}

/// Serves canned bodies by URL path suffix.
extension BackendClientTests {
    /// The stream carries the body of `/state`, so the two routes have to agree:
    /// the same body must produce the same status whether it was polled or pushed.
    /// They did not — the stream decoded an envelope the backend never sends, and
    /// threw away every reading while reporting itself live.
    func testAStreamedReadingMatchesTheSameBodyFetchedByRequest() async throws {
        let body = """
        {"data":{"state":{"vehicle_id":1,"state":"driving","state_since":"2026-08-21T02:32:18Z","name":"wyy",
        "location":{"latitude":37.36705,"longitude":-121.983088,"heading":120},
        "battery":{"level":71,"usable_level":71,"range":234.8},
        "driving":{"shift_state":"D","speed":63.0,"power":34.0,"odometer":33938.43}}},
        "meta":{"source":"mixed","units":{"length":"mi","temperature":"C","pressure":"psi","range":"rated"}}}
        """
        let polled = try await client(["/v1/vehicles/1/state": body]).status(carID: 1)
        let streamed = try XCTUnwrap(LiveStateStream.decode(body: Data(body.utf8), carID: 1))

        XCTAssertEqual(streamed.status.state, polled.status.state)
        XCTAssertEqual(streamed.status.drivingDetails?.speed, polled.status.drivingDetails?.speed)
        XCTAssertEqual(streamed.status.drivingDetails?.power, polled.status.drivingDetails?.power)
        XCTAssertEqual(streamed.status.carGeodata?.location?.latitude, polled.status.carGeodata?.location?.latitude)
        XCTAssertEqual(streamed.status.odometer, polled.status.odometer)
        XCTAssertEqual(streamed.units, polled.units)
    }
}

private final class StubTransport: HTTPTransport, @unchecked Sendable {
    private let responses: [String: String]
    private let statusCode: Int
    private(set) var lastRequest: URLRequest?

    init(responses: [String: String], statusCode: Int = 200) {
        self.responses = responses
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let path = request.url?.path ?? ""
        guard let body = responses.first(where: { path.hasSuffix($0.key) })?.value else {
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil
            )!
            return (Data("{}".utf8), response)
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil
        )!
        return (Data(body.utf8), response)
    }
}
