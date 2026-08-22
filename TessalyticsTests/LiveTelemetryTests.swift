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

    func testThinningKeepsTheShapeAndTheNewestReading() {
        // The charts and the map redraw on every reading, two or three a second.
        // Drawing every point in the buffer costs the live figures beside them the
        // responsiveness the stream exists to provide.
        let buffer = buffer(seconds: (0..<1_000).map(Double.init))
        let plotted = buffer.plotted(limit: 180)

        XCTAssertLessThanOrEqual(plotted.count, 181, "Thinned to the limit, plus the newest reading")
        XCTAssertGreaterThan(plotted.count, 100, "Still enough points to draw a shape")
        XCTAssertEqual(plotted.first, buffer.samples.first)
        XCTAssertEqual(plotted.last, buffer.samples.last, "A live chart's right edge has to be the newest reading")
        // Order is what a route and a time axis both depend on.
        for (previous, next) in zip(plotted, plotted.dropFirst()) {
            XCTAssertLessThan(previous.date, next.date)
        }
    }

    func testShortBuffersAreNotThinned() {
        let buffer = buffer(seconds: [0, 10, 20, 30])
        XCTAssertEqual(buffer.plotted(limit: 180), buffer.samples)
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

    func testNoRegenerationIsZeroRatherThanUnavailable() {
        // A drive with no regeneration in it is a fact about the drive. Reporting
        // nothing would say the app could not tell, which is a different claim —
        // and it is what put "Unavailable" on a live card during a working stream.
        let buffer = buffer(seconds: [0, 10], power: { _ in 40 })
        XCTAssertEqual(buffer.maximumRegeneration, 0)
    }

    func testWithNoPowerReadingsAtAllRegenerationIsUnknown() {
        // No readings is the one case where there is genuinely nothing to say.
        let buffer = buffer(seconds: [0, 10], power: { _ in Double?.none })
        XCTAssertNil(buffer.maximumRegeneration)
    }

    func testACarThatHasNotMovedYetHasDrivenZeroRatherThanAnUnknownDistance() {
        var buffer = LiveTelemetryBuffer()
        for index in 0...4 {
            buffer.append(
                date: start.addingTimeInterval(Double(index) * 5),
                speed: 0, power: 0, level: 80, odometer: 1_000
            )
        }
        XCTAssertEqual(buffer.distance, 0)
        XCTAssertEqual(buffer.maximumSpeed, 0)
        XCTAssertEqual(buffer.maximumPower, 0)
        XCTAssertEqual(try XCTUnwrap(buffer.energyUsed), 0, accuracy: 1e-9)
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
        XCTAssertEqual(buffer.routePath, [CoordinateDTO(latitude: 37.4, longitude: -122.1)])
    }

    func testTheRoutePathIsNotThinned() {
        // Thinning here is what made the map flash: which points survived changed
        // every time the buffer grew. `LiveRouteTrail` thins by distance instead,
        // and it needs every position to do that.
        let buffer = buffer(seconds: (0..<1_000).map(Double.init))
        var positioned = LiveTelemetryBuffer()
        for (index, sample) in buffer.samples.enumerated() {
            positioned.append(
                date: sample.date, speed: sample.speed, power: sample.power, level: sample.level,
                odometer: sample.odometer, latitude: 37 + Double(index) * 0.001, longitude: -122
            )
        }
        XCTAssertEqual(positioned.routePath.count, positioned.samples.count)
    }

    func testAChartWindowShowsTheLastFewMinutesAndNoMore() {
        // Measured back from the newest reading rather than from now, so a stream
        // that goes quiet leaves the last minute of the drive on screen.
        let buffer = buffer(seconds: (0..<600).map { Double($0) })
        let window = buffer.samples(within: 120)
        XCTAssertEqual(window.count, 121)
        XCTAssertEqual(window.last, buffer.samples.last)
        XCTAssertEqual(
            try XCTUnwrap(window.first).date.timeIntervalSince(try XCTUnwrap(buffer.samples.last).date),
            -120,
            accuracy: 0.001
        )
    }

    func testAWindowedChartIsStillThinnedAndStillEndsOnTheNewestReading() {
        let buffer = buffer(seconds: (0..<1_200).map { Double($0) * 0.5 })
        let plotted = buffer.plotted(within: 300, limit: 60)
        XCTAssertLessThanOrEqual(plotted.count, 61)
        XCTAssertEqual(plotted.last, buffer.samples.last)
    }

    func testAWindowLongerThanTheDriveIsTheWholeDrive() {
        let buffer = buffer(seconds: [0, 10, 20])
        XCTAssertEqual(buffer.samples(within: LiveTelemetryBuffer.window), buffer.samples)
    }

    func testElevationIsRecordedSoItCanBeCharted() {
        var buffer = LiveTelemetryBuffer()
        buffer.append(date: start, speed: 30, power: 10, level: 80, odometer: 1_000, elevation: 42)
        XCTAssertEqual(buffer.samples.first?.elevation, 42)
    }

    func testResetClearsEverything() {
        var buffer = buffer(seconds: [0, 10, 20])
        buffer.reset()
        XCTAssertTrue(buffer.samples.isEmpty)
        XCTAssertNil(buffer.distance)
        XCTAssertNil(buffer.span)
    }
}
