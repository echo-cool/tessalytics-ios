import XCTest
@testable import Tessalytics

/// A car standing at a light is doing 0 mph. Reporting that as "Unavailable" says
/// the app has lost the vehicle, in the middle of a drive it is streaming — which
/// is a different and much more alarming claim than the truth.
final class LiveMetricsTests: XCTestCase {
    private func status(
        state: String = "driving",
        shift: String? = "D",
        speed: Double? = nil,
        power: Double? = nil,
        elevation: Double? = 42,
        outside: Double? = 14,
        level: Int? = 62,
        range: Double? = 240,
        odometer: Double? = 12_000
    ) -> VehicleStatus {
        VehicleStatus(
            displayName: "Car",
            state: state,
            stateSince: nil,
            odometer: odometer,
            carStatus: nil,
            carDetails: nil,
            carGeodata: nil,
            carVersions: nil,
            drivingDetails: DrivingDetailsDTO(
                shiftState: shift, power: power, speed: speed, heading: 90, elevation: elevation
            ),
            climateDetails: ClimateDetailsDTO(
                isClimateOn: true, insideTemp: 21, outsideTemp: outside,
                isPreconditioning: false, climateKeeperMode: nil
            ),
            batteryDetails: StatusBatteryDTO(
                estBatteryRange: range, ratedBatteryRange: nil, idealBatteryRange: nil,
                batteryLevel: level, usableBatteryLevel: level
            ),
            chargingDetails: nil,
            tpmsDetails: nil
        )
    }

    private func buffer(odometerStart: Double = 12_000, power: Double = 30) -> LiveTelemetryBuffer {
        var buffer = LiveTelemetryBuffer()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for index in 0...24 {
            buffer.append(
                date: start.addingTimeInterval(Double(index) * 5),
                speed: 60,
                power: power,
                level: 62,
                odometer: odometerStart + Double(index) * 0.1
            )
        }
        return buffer
    }

    func testStandingStillIsZeroRatherThanUnavailable() {
        // TeslaMate publishes a null speed while the car waits at a light.
        let stopped = status(speed: nil, power: nil)
        XCTAssertEqual(stopped.liveSpeed, 0)
        XCTAssertEqual(stopped.livePower, 0)

        let metrics = LiveMetrics.hero(status: stopped, buffer: buffer(), units: .metricDefaults)
        let speed = try? XCTUnwrap(metrics.first { $0.id == "speed" })
        let power = try? XCTUnwrap(metrics.first { $0.id == "power" })
        XCTAssertEqual(speed?.value, "0 km/h")
        XCTAssertEqual(power?.value, "0 kW")
        XCTAssertFalse(metrics.contains { $0.value == "Unavailable" }, "Nothing on a live card should say unavailable")
    }

    func testAParkedCarStillDistinguishesMissingReadingsFromZero() {
        // Asleep on a driveway: the app genuinely does not know, and should not
        // invent a zero for a car it cannot hear from.
        let asleep = status(state: "asleep", shift: nil, speed: nil, power: nil)
        XCTAssertNil(asleep.liveSpeed)
        XCTAssertNil(asleep.livePower)
    }

    func testRealReadingsPassThroughUnchanged() {
        let moving = status(speed: 63, power: -18)
        XCTAssertEqual(moving.liveSpeed, 63)
        XCTAssertEqual(moving.livePower, -18)

        let power = LiveMetrics.power(moving)
        XCTAssertEqual(power.value, "-18 kW")
        XCTAssertEqual(power.label, "regenerating", "The sign is the interesting part")
        XCTAssertEqual(power.tone, .positive)
    }

    func testTheHeroGridFillsAllSixOfItsPlaces() {
        // The grid is three across and two down. Four figures left two holes in it.
        let metrics = LiveMetrics.hero(status: status(speed: 63, power: 34), buffer: buffer(), units: .metricDefaults)
        XCTAssertEqual(metrics.count, 6)
        XCTAssertEqual(Set(metrics.map(\.id)).count, 6, "Six places saying six different things")
        XCTAssertEqual(metrics.map(\.id), ["speed", "power", "distance", "energy", "outside", "elevation"])
    }

    func testTheHeroGridDoesNotRepeatWhatTheRingAlreadySays() {
        // Battery level, range and the odometer are drawn directly above this grid.
        let metrics = LiveMetrics.hero(status: status(), buffer: buffer(), units: .metricDefaults)
        XCTAssertFalse(metrics.contains { $0.id == "battery" })
        XCTAssertFalse(metrics.contains { $0.id == "range" })
    }

    func testTheFullScreenMapHasRoomForTheRestOfThem() {
        // No ring gauge on the map, so the figures it replaces come back.
        let metrics = LiveMetrics.expanded(status: status(), buffer: buffer(), units: .metricDefaults)
        XCTAssertEqual(metrics.count, 9)
        XCTAssertTrue(metrics.contains { $0.id == "battery" })
        XCTAssertTrue(metrics.contains { $0.id == "range" })
        XCTAssertTrue(metrics.contains { $0.id == "consumption" })
    }

    func testAccessibilityIdentifiersAreStable() {
        // A UI test taps these by name; guessing at indices passes for the wrong
        // reason the first time the order changes.
        let metrics = LiveMetrics.expanded(status: status(), buffer: buffer(), units: .metricDefaults)
        for metric in metrics {
            XCTAssertFalse(metric.id.isEmpty)
            XCTAssertFalse(metric.label.isEmpty)
        }
    }

    func testUnitsFollowTheServer() {
        let imperial = UnitsDTO(unitOfLength: "mi", unitOfPressure: "psi", unitOfTemperature: "F")
        let metrics = LiveMetrics.hero(status: status(speed: 0, power: 0), buffer: buffer(), units: imperial)
        XCTAssertEqual(metrics.first { $0.id == "speed" }?.value, "0 mph")
    }
}
