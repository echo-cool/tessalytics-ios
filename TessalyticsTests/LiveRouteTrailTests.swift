import XCTest
@testable import Tessalytics

/// The route on the hero map used to be rebuilt from scratch on every reading,
/// and thinned by taking every *n*th sample — where *n* grew with the buffer, so
/// one extra reading could replace every point on the map with a different one.
/// At two or three readings a second, that reads as a flashing route.
///
/// These tests hold the two properties that stopped it: a point once drawn stays
/// where it was put, and the route reports a change only when it has changed.
final class LiveRouteTrailTests: XCTestCase {
    private func line(from first: Double, to last: Double, step: Double = 0.0005) -> [CoordinateDTO] {
        var points: [CoordinateDTO] = []
        var value = first
        while value <= last + step / 2 {
            points.append(CoordinateDTO(latitude: 37 + value, longitude: -122))
            value += step
        }
        return points
    }

    func testARepeatedReadingDoesNotRedrawTheRoute() {
        var trail = LiveRouteTrail()
        let live = line(from: 0, to: 0.01)
        trail.update(seed: [], live: live)
        let drawn = trail.revision

        // The car is at a light: the stream keeps delivering, the position does not
        // change. Nothing about the line has changed, so nothing should be redrawn.
        trail.update(seed: [], live: live)
        trail.update(seed: [], live: live)
        XCTAssertEqual(trail.revision, drawn, "An unchanged route must not report a change")
    }

    func testTheDrawnRouteOnlyEverGrowsAtItsEnd() {
        // The failure this replaces: index striding reshuffled every point in the
        // line each time the sample count crossed a multiple of the limit.
        var trail = LiveRouteTrail()
        var previous: [CoordinateDTO] = []

        for count in stride(from: 20, through: 1_200, by: 20) {
            let live = (0..<count).map { CoordinateDTO(latitude: 37 + Double($0) * 0.0002, longitude: -122) }
            trail.update(seed: [], live: live)
            let drawn = trail.coordinates
            // The last point tracks the car and is allowed to move; everything
            // before it is road already travelled and must stay put.
            let settled = previous.dropLast()
            if !settled.isEmpty {
                XCTAssertTrue(
                    drawn.starts(with: settled),
                    "Points already drawn moved at \(count) readings, which is what the flashing route looked like"
                )
            }
            previous = drawn
        }
    }

    func testAnOverlongRouteIsRebuiltOnlyWhenItOutgrowsTheBudget() {
        // Past the drawing budget the line has to be coarsened, and coarsening does
        // move points. It takes a doubling of the route's length to do it, so this
        // happens a handful of times in a drive rather than several times a second.
        var trail = LiveRouteTrail()
        var previous: [CoordinateDTO] = []
        var updates = 0
        var rebuilds = 0

        for count in stride(from: 100, through: 40_000, by: 100) {
            let live = (0..<count).map { CoordinateDTO(latitude: 37 + Double($0) * 0.0002, longitude: -122) }
            trail.update(seed: [], live: live)
            updates += 1
            let settled = previous.dropLast()
            if !settled.isEmpty, !trail.coordinates.starts(with: settled) { rebuilds += 1 }
            previous = trail.coordinates
        }

        XCTAssertGreaterThan(updates, 300)
        XCTAssertLessThanOrEqual(rebuilds, 8, "A coarsening per doubling, not one per reading")
    }

    func testTheRouteStaysWithinItsDrawingBudget() {
        var trail = LiveRouteTrail()
        // A long motorway drive: far more positions than any map can draw.
        let live = (0..<40_000).map { CoordinateDTO(latitude: 37 + Double($0) * 0.00005, longitude: -122) }
        trail.update(seed: [], live: live)
        XCTAssertLessThanOrEqual(trail.coordinates.count, LiveRouteTrail.maximumPoints)
        XCTAssertGreaterThan(trail.coordinates.count, 100, "Still enough points to be a road rather than a chord")
    }

    func testTheCarsLatestPositionIsAlwaysTheEndOfTheLine() {
        var trail = LiveRouteTrail()
        // A last reading a metre past the previous one is still where the car is,
        // and a line that stops short of the pin reads as a broken route.
        let live = line(from: 0, to: 0.01) + [CoordinateDTO(latitude: 37.010005, longitude: -122)]
        trail.update(seed: [], live: live)
        XCTAssertEqual(trail.coordinates.last, live.last)
    }

    func testAppendingOnePositionAdvancesTheRouteByOneRevision() {
        var trail = LiveRouteTrail()
        var live = line(from: 0, to: 0.005)
        trail.update(seed: [], live: live)
        let drawn = trail.revision

        live.append(CoordinateDTO(latitude: 37.006, longitude: -122))
        trail.update(seed: [], live: live)
        XCTAssertEqual(trail.revision, drawn + 1)
        XCTAssertEqual(trail.coordinates.last, live.last)
    }

    func testTheFetchedPathAndTheStreamedPositionsAreOneRoute() {
        var trail = LiveRouteTrail()
        let seed = line(from: 0, to: 0.005)
        let live = line(from: 0.004, to: 0.010)
        trail.update(seed: seed, live: live)

        XCTAssertEqual(trail.coordinates.first, seed.first)
        XCTAssertEqual(trail.coordinates.last, live.last)
        // Monotonic: a doubled-back route is the join going wrong.
        for (previous, next) in zip(trail.coordinates, trail.coordinates.dropFirst()) {
            XCTAssertGreaterThan(next.latitude, previous.latitude)
        }
    }

    func testDecimationKeepsTheEndsAndDropsOnlyTheCrowdedMiddle() {
        let crowded = Array(repeating: CoordinateDTO(latitude: 37, longitude: -122), count: 50)
            + [CoordinateDTO(latitude: 37.01, longitude: -122)]
        let decimated = LiveRouteTrail.decimated(crowded)
        XCTAssertEqual(decimated.count, 2, "Fifty readings from one parking space are one point")
        XCTAssertEqual(decimated.first, crowded.first)
        XCTAssertEqual(decimated.last, crowded.last)
    }

    func testResetClearsTheLineAndSaysSoOnce() {
        var trail = LiveRouteTrail()
        trail.update(seed: [], live: line(from: 0, to: 0.005))
        let drawn = trail.revision

        trail.reset()
        XCTAssertTrue(trail.isEmpty)
        XCTAssertEqual(trail.revision, drawn + 1)

        // Parked, and staying parked: nothing more to report.
        trail.reset()
        XCTAssertEqual(trail.revision, drawn + 1)
    }

    func testAnEmptyRouteIsNotAChange() {
        var trail = LiveRouteTrail()
        trail.update(seed: [], live: [])
        XCTAssertEqual(trail.revision, 0)
        XCTAssertTrue(trail.isEmpty)
    }
}
