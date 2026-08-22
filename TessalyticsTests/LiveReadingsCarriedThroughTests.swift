import XCTest
@testable import Tessalytics

/// The server was already sending these and the app was decoding them and
/// throwing them away: the car's own tyre warnings, whether anyone is aboard, the
/// cold-weather buffer, and — once the backend learned to report it — what is
/// steering. A field that reaches the device and never reaches a screen is worse
/// than one that was never sent, because nobody thinks to look for it.
final class LiveReadingsCarriedThroughTests: XCTestCase {
    private static let body = Data(
        """
        {"data":{"state":{"vehicle_id":1,"state":"driving","state_since":"2026-08-21T04:12:19Z",
        "name":"Aurora","location":{"latitude":37.3861,"longitude":-122.0839,"heading":118,"geofence":null},
        "battery":{"level":71,"usable_level":68,"buffer":3,"range":214,"range_rated":214},
        "driving":{"shift_state":"D","speed":63.0,"power":34.0,"odometer":18654.2,"is_user_present":true,
        "autopilot":{"state":"Full Self-Driving","engaged":true}},
        "tyres":{"front_left":{"pressure":2.75,"warning":false},"front_right":{"pressure":2.4,"warning":true},
        "rear_left":{"pressure":2.8,"warning":null},"rear_right":{"pressure":2.8,"warning":false}}}},
        "meta":{"source":"mixed","units":{"length":"km","temperature":"C","pressure":"bar","range":"rated"}}}
        """.utf8
    )

    private func status() throws -> VehicleStatus {
        let decoded = LiveStateStream.decode(body: Self.body, carID: 1)
        return try XCTUnwrap(decoded?.status)
    }

    func testTheSelfDrivingReadingSurvivesTheWire() throws {
        let status = try status()
        XCTAssertEqual(status.drivingDetails?.autopilotState, "Full Self-Driving")
        XCTAssertEqual(status.drivingDetails?.isAutopilotEngaged, true)
        XCTAssertEqual(status.selfDrivingMode, .fullSelfDriving)
    }

    func testTyreWarningsSurviveTheWire() throws {
        let tyres = try XCTUnwrap(status().tpmsDetails)
        XCTAssertEqual(tyres.tpmsWarningFr, true, "The car said the front right is soft")
        XCTAssertEqual(tyres.tpmsWarningFl, false)
        XCTAssertNil(tyres.tpmsWarningRl, "A tyre the car said nothing about is unknown, not fine")
        XCTAssertTrue(tyres.hasAnyWarning)
    }

    func testACarWithNoWarningsReportsNone() {
        let quiet = TPMSDTO(tpmsPressureFl: 2.8, tpmsPressureFr: 2.8, tpmsPressureRl: 2.8, tpmsPressureRr: 2.8)
        XCTAssertFalse(quiet.hasAnyWarning, "Silence about warnings is not a warning")
        XCTAssertTrue(quiet.hasAnyReading)
    }

    func testOccupancySurvivesTheWire() throws {
        XCTAssertEqual(try status().drivingDetails?.isUserPresent, true)
    }

    func testTheColdBufferSurvivesTheWire() throws {
        XCTAssertEqual(try status().batteryDetails?.bufferLevel, 3)
    }

    func testAServerThatReportsNoneOfThisDecodesToNils() throws {
        // Every one of these is optional on the wire, because most TeslaMate
        // deployments publish none of them.
        let plain = Data(
            """
            {"data":{"state":{"vehicle_id":1,"state":"online",
            "driving":{"shift_state":"P","speed":null,"power":null},
            "battery":{"level":71},"tyres":{"front_left":{"pressure":2.75}}}},"meta":{"source":"database"}}
            """.utf8
        )
        let status = try XCTUnwrap(LiveStateStream.decode(body: plain, carID: 1)?.status)
        XCTAssertNil(status.drivingDetails?.autopilotState)
        XCTAssertNil(status.drivingDetails?.isAutopilotEngaged)
        XCTAssertNil(status.drivingDetails?.isUserPresent)
        XCTAssertNil(status.batteryDetails?.bufferLevel)
        XCTAssertNil(status.tpmsDetails?.tpmsWarningFl)
        XCTAssertFalse(status.tpmsDetails?.hasAnyWarning ?? true)
    }

    func testAStatusRoundTripsThroughTheCacheWithTheNewFieldsIntact() throws {
        // The status is cached as JSON, so a field that does not round-trip is a
        // field that vanishes on the next cold launch.
        let original = try status()
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(VehicleStatus.self, from: data)
        XCTAssertEqual(restored.drivingDetails?.autopilotState, "Full Self-Driving")
        XCTAssertEqual(restored.drivingDetails?.isUserPresent, true)
        XCTAssertEqual(restored.batteryDetails?.bufferLevel, 3)
        XCTAssertEqual(restored.tpmsDetails?.tpmsWarningFr, true)
    }

    func testAnOlderCachedStatusStillDecodes() throws {
        // Written by a build that had never heard of any of these.
        let legacy = Data(
            """
            {"state":"driving","odometer":100,
            "drivingDetails":{"shiftState":"D","power":10,"speed":40},
            "batteryDetails":{"batteryLevel":70},
            "tpmsDetails":{"tpmsPressureFl":2.7}}
            """.utf8
        )
        let status = try JSONDecoder().decode(VehicleStatus.self, from: legacy)
        XCTAssertEqual(status.drivingDetails?.speed, 40)
        XCTAssertNil(status.drivingDetails?.autopilotState)
        XCTAssertNil(status.tpmsDetails?.tpmsWarningFl)
    }

    func testTheExpandedReadoutNamesTheDirectionOfTravel() throws {
        let metrics = LiveMetrics.expanded(
            status: try status(),
            totals: LiveDriveTotals(),
            units: .metricDefaults
        )
        let heading = try XCTUnwrap(metrics.first { $0.id == "heading" })
        XCTAssertEqual(heading.value, "SE · 118°")
    }
}
