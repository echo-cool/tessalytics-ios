import XCTest
@testable import Tessalytics

final class LiveTelemetryBufferTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func buffer(seconds: [Double], speed: (Int) -> Double? = { Double($0) }, power: (Int) -> Double? = { _ in 20 }) -> LiveTelemetryBuffer {
        var buffer = LiveTelemetryBuffer()
        for (index, offset) in seconds.enumerated() {
            buffer.append(
                date: start.addingTimeInterval(offset),
                speed: speed(index),
                power: power(index),
                level: 80,
                odometer: 1_000 + Double(index)
            )
        }
        return buffer
    }

    func testAnEmptyReadingIsNotStored() {
        // An event carrying nothing to plot would otherwise pad the buffer.
        var buffer = LiveTelemetryBuffer()
        buffer.append(date: start, speed: nil, power: nil, level: nil, odometer: 1_000)
        XCTAssertTrue(buffer.samples.isEmpty)
    }

    func testReadingsAtTheSameInstantReplaceRatherThanStack() {
        var buffer = LiveTelemetryBuffer()
        buffer.append(date: start, speed: 30, power: 10, level: 80, odometer: 1_000)
        buffer.append(date: start.addingTimeInterval(0.1), speed: 40, power: 12, level: 80, odometer: 1_000)
        XCTAssertEqual(buffer.samples.count, 1)
        XCTAssertEqual(buffer.samples.first?.speed, 40)
    }

    func testReadingsOlderThanTheWindowAreDropped() {
        let buffer = buffer(seconds: [0, 60, LiveTelemetryBuffer.window + 120])
        XCTAssertEqual(buffer.samples.count, 1, "Only the newest sample is inside the window")
    }

    func testTheBufferIsCapped() {
        // A fault pushing readings in a tight loop must not grow this without end.
        var buffer = LiveTelemetryBuffer()
        for index in 0..<(LiveTelemetryBuffer.capacity + 400) {
            buffer.append(date: start.addingTimeInterval(Double(index) * 0.5), speed: 30, power: 10, level: 80, odometer: 1_000)
        }
        XCTAssertLessThanOrEqual(buffer.samples.count, LiveTelemetryBuffer.capacity)
    }

    func testIdsStayUniqueSoChartMarksAreNotDropped() {
        let buffer = buffer(seconds: (0..<40).map { Double($0) * 5 })
        XCTAssertEqual(Set(buffer.samples.map(\.id)).count, buffer.samples.count)
    }

    func testExtremesComeFromTheWindow() {
        let buffer = buffer(
            seconds: [0, 10, 20, 30],
            speed: { [12, 64, 31, 44][$0] },
            power: { [10, 88, -26, 30][$0] }
        )
        XCTAssertEqual(buffer.maximumSpeed, 64)
        XCTAssertEqual(buffer.maximumPower, 88)
        XCTAssertEqual(buffer.maximumRegeneration, 26, "Regen is reported as a positive peak")
    }

    func testNoRegenerationReportsNothingRatherThanZero() {
        let buffer = buffer(seconds: [0, 10], power: { _ in 40 })
        XCTAssertNil(buffer.maximumRegeneration)
    }

    func testDistanceComesFromTheOdometer() {
        let buffer = buffer(seconds: [0, 10, 20])
        XCTAssertEqual(buffer.distance, 2)
    }

    func testEnergyIsIntegratedOverTime() {
        // 60 kW held for two minutes is 2 kWh.
        var buffer = LiveTelemetryBuffer()
        for index in 0...24 {
            buffer.append(
                date: start.addingTimeInterval(Double(index) * 5),
                speed: 50,
                power: 60,
                level: 80,
                odometer: 1_000 + Double(index)
            )
        }
        XCTAssertEqual(try XCTUnwrap(buffer.energyUsed), 2.0, accuracy: 0.01)
    }

    func testRegenerationCountsAgainstEnergyUsed() throws {
        // The figure is net, not energy drawn: a descent gives some back.
        func energy(regenerating: Bool) throws -> Double {
            var buffer = LiveTelemetryBuffer()
            for index in 0...24 {
                buffer.append(
                    date: start.addingTimeInterval(Double(index) * 5),
                    speed: 50,
                    power: regenerating && index >= 12 ? -60 : 60,
                    level: 80,
                    odometer: 1_000 + Double(index)
                )
            }
            return try XCTUnwrap(buffer.energyUsed)
        }

        let drawnThroughout = try energy(regenerating: false)
        let halfRegenerating = try energy(regenerating: true)
        XCTAssertEqual(drawnThroughout, 2.0, accuracy: 0.01)
        XCTAssertLessThan(halfRegenerating, drawnThroughout / 2)
    }

    func testAGapInTheStreamIsNotIntegrated() {
        // The stream dropped; the car did not draw power for the whole interval.
        var buffer = LiveTelemetryBuffer()
        buffer.append(date: start, speed: 50, power: 60, level: 80, odometer: 1_000)
        buffer.append(date: start.addingTimeInterval(600), speed: 50, power: 60, level: 80, odometer: 1_010)
        XCTAssertNil(buffer.energyUsed, "A ten-minute gap contributes nothing")
    }

    func testConsumptionNeedsBothDistanceAndEnergy() {
        var buffer = LiveTelemetryBuffer()
        // Stationary with the climate running: energy but no distance.
        for index in 0...20 {
            buffer.append(
                date: start.addingTimeInterval(Double(index) * 5),
                speed: 0,
                power: 5,
                level: 80,
                odometer: 1_000
            )
        }
        XCTAssertNil(buffer.consumption(), "Dividing by no distance is not a figure")
    }

    func testTheTrailSkipsMissingAndNullIslandPositions() {
        var buffer = LiveTelemetryBuffer()
        buffer.append(date: start, speed: 30, power: 10, level: 80, odometer: 1_000, latitude: 0, longitude: 0)
        buffer.append(date: start.addingTimeInterval(5), speed: 30, power: 10, level: 80, odometer: 1_001)
        buffer.append(
            date: start.addingTimeInterval(10), speed: 30, power: 10, level: 80, odometer: 1_002,
            latitude: 37.4, longitude: -122.1
        )
        XCTAssertEqual(buffer.trail.count, 1)
        XCTAssertEqual(buffer.trail.first?.latitude, 37.4)
    }

    func testResetClearsEverything() {
        var buffer = buffer(seconds: [0, 10, 20])
        buffer.reset()
        XCTAssertTrue(buffer.samples.isEmpty)
        XCTAssertNil(buffer.distance)
        XCTAssertNil(buffer.span)
    }
}
