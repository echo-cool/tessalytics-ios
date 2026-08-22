import XCTest
@testable import Tessalytics

/// The reported figure was "this drive"; the number under it was the last eight
/// minutes. `LiveTelemetryBuffer` is capped at 1,200 samples, and a streaming
/// drive produces two or three a second — so on any journey longer than that the
/// totals derived from it quietly described a window, under a label that did not.
final class LiveDriveTotalsTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// Drives for `minutes` at a steady 60 units/hour and 30 kW, publishing at
    /// the rate the stream does.
    private func driven(minutes: Double, from odometer: Double = 12_000) -> LiveDriveTotals {
        var totals = LiveDriveTotals()
        let step = 0.4
        let ticks = Int(minutes * 60 / step)
        for index in 0...ticks {
            let elapsed = Double(index) * step
            totals.record(
                odometer: odometer + 60 * (elapsed / 3_600),
                speed: 60,
                power: 30,
                at: start.addingTimeInterval(elapsed)
            )
        }
        return totals
    }

    func testTheTotalsCoverTheWholeDriveNotTheChartWindow() {
        // Forty minutes: five times what the buffer can hold.
        let totals = driven(minutes: 40)
        XCTAssertEqual(try XCTUnwrap(totals.distance), 40, accuracy: 0.05, "Forty minutes at 60 is forty")

        var buffer = LiveTelemetryBuffer()
        for index in 0...Int(40 * 60 / 0.4) {
            let elapsed = Double(index) * 0.4
            buffer.append(
                date: start.addingTimeInterval(elapsed),
                speed: 60,
                power: 30,
                level: 70,
                odometer: 12_000 + 60 * (elapsed / 3_600)
            )
        }
        let windowed = try? XCTUnwrap(buffer.distance)
        XCTAssertLessThan(
            windowed ?? 0,
            20,
            "The buffer is pruned — this is the number that used to be labelled 'this drive'"
        )
    }

    func testEnergyIsIntegratedAcrossTheWholeDrive() {
        // 30 kW for an hour is 30 kWh; for forty minutes, twenty.
        let totals = driven(minutes: 40)
        XCTAssertEqual(try XCTUnwrap(totals.energyUsed), 20, accuracy: 0.1)
    }

    func testAGapInTheStreamIsNotIntegratedOver() {
        // A tunnel: the readings resume ten minutes later. The car did not draw
        // 30 kW for the whole of that, and inventing the energy would be worse
        // than reporting only what was seen.
        var totals = LiveDriveTotals()
        totals.record(odometer: 100, speed: 60, power: 30, at: start)
        totals.record(odometer: 101, speed: 60, power: 30, at: start.addingTimeInterval(60))
        let beforeGap = try? XCTUnwrap(totals.energyUsed)
        totals.record(odometer: 110, speed: 60, power: 30, at: start.addingTimeInterval(660))
        XCTAssertEqual(totals.energyUsed ?? 0, beforeGap ?? 0, accuracy: 0.001, "The gap contributed nothing")
        // The odometer counted the distance whether or not the phone was listening.
        XCTAssertEqual(try XCTUnwrap(totals.distance), 10, accuracy: 0.001)
    }

    func testTheOdometerIsTreatedAsMonotonic() {
        var totals = LiveDriveTotals()
        totals.record(odometer: 100, speed: 10, power: 5, at: start)
        totals.record(odometer: 120, speed: 10, power: 5, at: start.addingTimeInterval(60))
        totals.record(odometer: 90, speed: 10, power: 5, at: start.addingTimeInterval(120))
        XCTAssertEqual(try XCTUnwrap(totals.distance), 20, "A reading that goes backwards is a bad sample")
    }

    func testAZeroOdometerIsNoReadingRatherThanTheStartOfTheDrive() {
        // A server with no odometer reading publishes 0. Taking that as the start
        // would report the car's whole lifetime mileage as this journey.
        var totals = LiveDriveTotals()
        totals.record(odometer: 0, speed: 10, power: 5, at: start)
        totals.record(odometer: 18_000, speed: 10, power: 5, at: start.addingTimeInterval(5))
        totals.record(odometer: 18_002, speed: 10, power: 5, at: start.addingTimeInterval(10))
        XCTAssertEqual(try XCTUnwrap(totals.distance), 2, accuracy: 0.001)
    }

    func testStandingStillIsZeroDistanceRatherThanUnknown() {
        var totals = LiveDriveTotals()
        totals.record(odometer: 500, speed: 0, power: 0, at: start)
        totals.record(odometer: 500, speed: 0, power: 0, at: start.addingTimeInterval(5))
        XCTAssertEqual(totals.distance, 0, "Two equal odometer readings measure standing still")
    }

    func testThePeaksAreTheDrivesPeaksNotTheWindows() {
        var totals = LiveDriveTotals()
        totals.record(odometer: 1, speed: 120, power: 180, at: start)
        // Twenty minutes later — long past the buffer's reach.
        for index in 1...100 {
            totals.record(
                odometer: 1 + Double(index) * 0.1,
                speed: 30,
                power: -40,
                at: start.addingTimeInterval(Double(index) * 12)
            )
        }
        XCTAssertEqual(totals.maximumSpeed, 120, "The fast bit was at the start of the drive")
        XCTAssertEqual(totals.maximumPower, 180)
        XCTAssertEqual(totals.maximumRegeneration, 40)
    }

    func testConsumptionNeedsBothHalvesOfIt() {
        XCTAssertNil(LiveDriveTotals().consumption)
        let totals = driven(minutes: 40)
        // 20 kWh over 40 units is 500 Wh per unit.
        XCTAssertEqual(try XCTUnwrap(totals.consumption), 500, accuracy: 5)
    }

    func testAnEmptyTotalsSaysSo() {
        var totals = LiveDriveTotals()
        XCTAssertTrue(totals.isEmpty)
        XCTAssertNil(totals.elapsed)
        totals.record(odometer: 1, speed: 1, power: 1, at: start)
        XCTAssertFalse(totals.isEmpty)
        totals.reset()
        XCTAssertTrue(totals.isEmpty, "A finished journey leaves nothing behind for the next one")
        XCTAssertNil(totals.distance)
    }

    func testElapsedReportsHowMuchOfTheDriveIsAccountedFor() {
        let totals = driven(minutes: 10)
        XCTAssertEqual(try XCTUnwrap(totals.elapsed), 600, accuracy: 1)
    }
}
