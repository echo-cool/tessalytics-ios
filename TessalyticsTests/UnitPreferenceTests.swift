import XCTest
@testable import Tessalytics

/// The car reports in its own units and the app may be asked to show another, so
/// the choice has to *convert* rather than relabel. Relabelling would put "mi"
/// beside a number of kilometres, which is worse than showing the wrong unit
/// honestly.
final class UnitPreferenceTests: XCTestCase {
    private let metricCar = UnitsDTO(unitOfLength: "km", unitOfPressure: "bar", unitOfTemperature: "C")
    private let imperialCar = UnitsDTO(unitOfLength: "mi", unitOfPressure: "psi", unitOfTemperature: "F")

    func testFollowingTheCarChangesNothing() {
        let units = metricCar.with(preference: .automatic)
        XCTAssertFalse(units.isConverting)
        XCTAssertEqual(units.lengthSymbol, "km")
        XCTAssertEqual(units.displayDistance(100), 100)
        XCTAssertEqual(ValueFormatting.distance(100, units: units, digits: 0), "100 km")
    }

    func testAMetricCarShownInImperialConvertsTheNumbers() {
        let units = metricCar.with(preference: .imperial)
        XCTAssertTrue(units.isConverting)
        XCTAssertEqual(try XCTUnwrap(units.displayDistance(100)), 62.137, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(units.displayTemperature(20)), 68, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(units.displayPressure(2.9)), 42.06, accuracy: 0.01)
        XCTAssertEqual(units.lengthSymbol, "mi")
        XCTAssertEqual(units.speedSymbol, "mph")
        XCTAssertEqual(units.temperatureSymbol, "°F")
        XCTAssertEqual(units.pressureSymbol, "psi")
    }

    func testAnImperialCarShownInMetricConvertsTheOtherWay() {
        let units = imperialCar.with(preference: .metric)
        XCTAssertEqual(try XCTUnwrap(units.displayDistance(62.137)), 100, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(units.displayTemperature(68)), 20, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(units.displayPressure(42.06)), 2.9, accuracy: 0.01)
    }

    /// Watt-hours *per* unit distance, so the factor inverts. Getting this the
    /// usual way round would report a car as far more efficient than it is.
    func testEfficiencyConvertsInverselyToDistance() throws {
        let units = metricCar.with(preference: .imperial)
        // 150 Wh/km is about 241 Wh/mi — more watt-hours in the longer unit.
        XCTAssertEqual(try XCTUnwrap(units.displayEfficiency(150)), 241.4, accuracy: 0.5)
        XCTAssertEqual(units.efficiencySymbol, "Wh/mi")
    }

    func testSpeedUsesTheSameFactorAsDistance() throws {
        let units = metricCar.with(preference: .imperial)
        XCTAssertEqual(try XCTUnwrap(units.displaySpeed(100)), 62.137, accuracy: 0.01)
    }

    func testConvertingIsReversible() throws {
        let there = metricCar.with(preference: .imperial)
        let back = imperialCar.with(preference: .metric)
        let value = 237.5
        let roundTrip = try XCTUnwrap(back.displayDistance(there.displayDistance(value)))
        XCTAssertEqual(roundTrip, value, accuracy: 0.0001)
    }

    /// A preference is this app's business, not the server's, so it must not be
    /// written into a payload or read out of one.
    func testThePreferenceIsNotPartOfTheServersPayload() throws {
        let encoded = try JSONEncoder().encode(metricCar.with(preference: .imperial))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertNil(object["preference"])

        let decoded = try JSONDecoder().decode(UnitsDTO.self, from: encoded)
        XCTAssertEqual(decoded.preference, .automatic, "A decoded payload carries no opinion")
    }

    func testNilUnitsStillFormatSomething() {
        XCTAssertEqual(ValueFormatting.distance(10, units: nil, digits: 0), "10 km")
    }
}

/// The conversion lives in `UnitsDTO`, but a call site that formats a raw value
/// itself skips it — and then shows a number in one unit wearing another's name.
/// A car reporting psi displayed "42.1 bar", which is worse than not converting
/// at all, because it looks like an answer.
@MainActor
final class UnitConversionReachesTheScreenTests: XCTestCase {
    private func status(rangeMiles: Double, odometerMiles: Double) -> VehicleStatus {
        VehicleStatus(
            displayName: "Aurora",
            state: "online",
            stateSince: nil,
            odometer: odometerMiles,
            carStatus: nil,
            carDetails: nil,
            carGeodata: nil,
            carVersions: nil,
            drivingDetails: DrivingDetailsDTO(shiftState: "P", power: 0, speed: 0, heading: nil, elevation: nil),
            climateDetails: nil,
            batteryDetails: StatusBatteryDTO(
                estBatteryRange: rangeMiles,
                ratedBatteryRange: rangeMiles,
                idealBatteryRange: rangeMiles,
                batteryLevel: 78,
                usableBatteryLevel: 78
            ),
            chargingDetails: nil,
            tpmsDetails: nil
        )
    }

    private let imperialCar = UnitsDTO(unitOfLength: "mi", unitOfPressure: "psi", unitOfTemperature: "F")

    func testTheHeroRangeIsConvertedNotJustRelabelled() {
        let summary = VehicleHeroSummary(
            status: status(rangeMiles: 238, odometerMiles: 18_642),
            units: imperialCar.with(preference: .metric)
        )
        XCTAssertTrue(summary.rangeLabel.hasPrefix("km"), summary.rangeLabel)
        XCTAssertEqual(
            Double(summary.rangeValue.replacingOccurrences(of: ",", with: "")) ?? 0,
            383.02,
            accuracy: 0.1,
            "238 miles is 383 km, and the label already says km"
        )
    }

    func testFollowingTheCarLeavesTheHeroFiguresAlone() {
        let summary = VehicleHeroSummary(
            status: status(rangeMiles: 238, odometerMiles: 18_642),
            units: imperialCar.with(preference: .automatic)
        )
        XCTAssertTrue(summary.rangeLabel.hasPrefix("mi"))
        XCTAssertEqual(Double(summary.rangeValue.replacingOccurrences(of: ",", with: "")) ?? 0, 238, accuracy: 0.01)
    }
}
