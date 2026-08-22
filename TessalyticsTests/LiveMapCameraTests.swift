import XCTest
@testable import Tessalytics

/// The live map's camera was reset on every reading, each time with a
/// six-tenths-of-a-second animation — so every animation was cut off by the next
/// reading's and the map never settled. These tests hold the quantisation that
/// stopped that.
final class LiveMapCameraTests: XCTestCase {
    private let car = CoordinateDTO(latitude: 37.5, longitude: -122.2)

    func testACameraAlreadyLookingAtThisDoesNotMove() {
        let framing = LiveMapCamera.framing(car: car, trail: [car])
        XCTAssertFalse(LiveMapCamera.shouldMove(from: framing, to: framing))
    }

    func testTheFirstFramingAlwaysMoves() {
        let framing = LiveMapCamera.framing(car: car, trail: [car])
        XCTAssertTrue(LiveMapCamera.shouldMove(from: nil, to: framing))
    }

    func testACarThatHasBarelyMovedDoesNotRestartTheAnimation() {
        let framing = LiveMapCamera.framing(car: car, trail: [car])
        // A tenth of the threshold: a reading or two of city driving.
        let nudged = LiveMapCamera.framing(
            car: CoordinateDTO(latitude: car.latitude + LiveMapCamera.recentreThreshold / 10, longitude: car.longitude),
            trail: [car]
        )
        XCTAssertFalse(LiveMapCamera.shouldMove(from: framing, to: nudged))
    }

    func testTheCameraFollowsOnceTheCarHasActuallyGoneSomewhere() {
        let framing = LiveMapCamera.framing(car: car, trail: [car])
        let moved = LiveMapCamera.framing(
            car: CoordinateDTO(latitude: car.latitude + LiveMapCamera.recentreThreshold * 10, longitude: car.longitude),
            trail: [car]
        )
        XCTAssertTrue(LiveMapCamera.shouldMove(from: framing, to: moved))
    }

    func testAChangeOfZoomAlwaysMoves() {
        var framing = LiveMapCamera.framing(car: car, trail: [car])
        var zoomedOut = framing
        zoomedOut.latitudeDelta += LiveMapCamera.spanStep
        XCTAssertTrue(LiveMapCamera.shouldMove(from: framing, to: zoomedOut))

        framing.longitudeDelta += LiveMapCamera.spanStep
        XCTAssertTrue(LiveMapCamera.shouldMove(from: zoomedOut, to: framing))
    }

    func testSpansAreSteppedAndBounded() {
        XCTAssertEqual(LiveMapCamera.stepped(0), LiveMapCamera.minimumSpan, "A stationary car still gets a readable frame")
        XCTAssertEqual(LiveMapCamera.stepped(10), LiveMapCamera.maximumSpan, "A cross-country route frames its recent miles")
        // Everything in between lands on a step, so the map zooms in notches
        // rather than breathing with every reading.
        for extent in stride(from: 0.0, through: 0.4, by: 0.003) {
            let span = LiveMapCamera.stepped(extent)
            let steps = span / LiveMapCamera.spanStep
            XCTAssertEqual(steps, steps.rounded(), accuracy: 1e-9, "Span \(span) is not on a step")
        }
    }

    func testTheFrameHoldsBothTheRouteAndTheCar() {
        let trail = (0..<20).map { CoordinateDTO(latitude: 37.5 + Double($0) * 0.001, longitude: -122.2) }
        let framing = LiveMapCamera.framing(car: trail[trail.count - 1], trail: trail)
        let north = framing.centerLatitude + framing.latitudeDelta / 2
        let south = framing.centerLatitude - framing.latitudeDelta / 2
        XCTAssertGreaterThanOrEqual(north, trail[trail.count - 1].latitude)
        XCTAssertLessThanOrEqual(south, trail[0].latitude)
    }

    func testALongRouteFramesTheRoadTheCarIsOnRatherThanTheWholeDrive() {
        // Two hundred kilometres of route, walked newest first: what falls out of
        // the frame is the beginning of the drive, not the road just travelled.
        let trail = (0..<2_000).map { CoordinateDTO(latitude: 37.5 + Double($0) * 0.001, longitude: -122.2) }
        let car = trail[trail.count - 1]
        let framing = LiveMapCamera.framing(car: car, trail: trail)
        XCTAssertLessThanOrEqual(framing.latitudeDelta, LiveMapCamera.maximumSpan)
        let south = framing.centerLatitude - framing.latitudeDelta / 2
        XCTAssertGreaterThan(south, trail[0].latitude, "The start of a very long drive is not framed")
        XCTAssertLessThan(abs(framing.centerLatitude - car.latitude), LiveMapCamera.maximumSpan)
    }
}
