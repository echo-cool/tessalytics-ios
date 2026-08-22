import XCTest
@testable import Tessalytics

/// The generated drive is test equipment as much as it is a demo, so its shape is
/// worth pinning down: a UI test that waits for the car to stop at a light needs
/// the light to be where it says it is.
final class DemoDriveSimulationTests: XCTestCase {
    func testTheDriveStartsStoppedAndPullsAway() {
        var drive = DemoDriveSimulation()
        XCTAssertEqual(drive.speed, 0, accuracy: 0.001)
        _ = drive.advance(by: 9)
        XCTAssertGreaterThan(drive.speed, 20, "Nine seconds in, the car is moving")
    }

    func testThereIsARedLightInEveryCycle() {
        // The case the hero card had nothing to say about: standing still in the
        // middle of a journey.
        for position in stride(from: 27.0, to: 43.0, by: 2) {
            XCTAssertEqual(
                DemoDriveSimulation.speed(atCyclePosition: position),
                0,
                "The car should be stopped at \(position)s into the cycle"
            )
        }
    }

    func testTheStopIsReachedByAdvancingThroughTheCycle() {
        var drive = DemoDriveSimulation()
        _ = drive.advance(by: 30)
        XCTAssertTrue(drive.isStopped)
        let status = drive.status()
        XCTAssertTrue(status.isDriving, "Stopped at a light is still a drive")
        XCTAssertTrue(status.isStoppedInDrive)
    }

    func testBothSelfDrivingStatesAppearInEveryCycle() {
        // A badge that is always on is indistinguishable from a badge that is
        // stuck on, so the demo has to show both.
        XCTAssertFalse(DemoDriveSimulation.autopilot(atCyclePosition: 10).engaged)
        XCTAssertTrue(DemoDriveSimulation.autopilot(atCyclePosition: 90).engaged)
        XCTAssertEqual(DemoDriveSimulation.autopilot(atCyclePosition: 90).state, "Full Self-Driving")
    }

    func testTheCarMovesAndTheOdometerFollowsIt() {
        var drive = DemoDriveSimulation()
        let start = CoordinateDTO(latitude: drive.latitude, longitude: drive.longitude)
        let startOdometer = drive.odometer
        for _ in 0..<150 { _ = drive.advance(by: DemoDriveSimulation.publishInterval) }
        let moved = LivePlaceName.distance(
            from: start,
            to: CoordinateDTO(latitude: drive.latitude, longitude: drive.longitude)
        )
        XCTAssertGreaterThan(moved, 200, "A minute of driving covers ground")
        XCTAssertGreaterThan(drive.odometer, startOdometer)
    }

    func testItStartsWhereItIsToldTo() {
        // The simulation continues the seeded drive rather than jumping back to
        // where that drive began, which drew the route as a hairpin.
        let elsewhere = CoordinateDTO(latitude: 51.5, longitude: -0.12)
        let drive = DemoDriveSimulation(from: elsewhere, odometer: 500)
        XCTAssertEqual(drive.latitude, elsewhere.latitude, accuracy: 0.000_001)
        XCTAssertEqual(drive.longitude, elsewhere.longitude, accuracy: 0.000_001)
        XCTAssertEqual(drive.odometer, 500, accuracy: 0.001)
    }

    func testTheGappyModeDropsSomeReadingsPositionsAndNotOthers() {
        // The fault that reproduces the flashing map, on demand.
        var drive = DemoDriveSimulation(dropsPositions: true)
        var withPosition = 0
        var without = 0
        for _ in 0..<30 {
            let status = drive.advance(by: DemoDriveSimulation.publishInterval)
            if status.carGeodata?.location == nil { without += 1 } else { withPosition += 1 }
        }
        XCTAssertGreaterThan(without, 0, "The fault has to actually happen")
        XCTAssertGreaterThan(withPosition, without, "And most readings still carry one")
    }

    func testTheOrdinaryModeNeverDropsAPosition() {
        var drive = DemoDriveSimulation()
        for _ in 0..<30 {
            XCTAssertNotNil(drive.advance(by: DemoDriveSimulation.publishInterval).carGeodata?.location)
        }
    }

    func testRegenerationAppearsWhileBraking() {
        // Braking for the light is between 18 and 26 seconds in.
        var drive = DemoDriveSimulation()
        _ = drive.advance(by: 22)
        XCTAssertLessThan(drive.power, 0, "Slowing down puts energy back")
    }
}
