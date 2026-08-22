import XCTest
@testable import Tessalytics

final class LiveRoutePathTests: XCTestCase {
    private func line(from first: Double, to last: Double, step: Double = 0.001) -> [CoordinateDTO] {
        var points: [CoordinateDTO] = []
        var value = first
        while value <= last + step / 2 {
            points.append(CoordinateDTO(latitude: 37 + value, longitude: -122))
            value += step
        }
        return points
    }

    func testEitherSourceAloneIsTheWholeRoute() {
        let path = line(from: 0, to: 0.005)
        XCTAssertEqual(LiveRoutePath.joined(seed: path, live: []), path)
        XCTAssertEqual(LiveRoutePath.joined(seed: [], live: path), path)
        XCTAssertTrue(LiveRoutePath.joined(seed: [], live: []).isEmpty)
    }

    func testTheOverlapIsNotDrawnTwice() {
        // The app opened partway through what the server already had: the live
        // readings start behind the fetched path's end and continue past it.
        let seed = line(from: 0, to: 0.005)
        let live = line(from: 0.003, to: 0.008)
        let joined = LiveRoutePath.joined(seed: seed, live: live)

        XCTAssertEqual(joined.count, seed.count + 3, "Only the readings past the fetched path are appended")
        XCTAssertEqual(Array(joined.prefix(seed.count)), seed)
        // Monotonic: a doubled-back route is the failure this exists to avoid.
        for (previous, next) in zip(joined, joined.dropFirst()) {
            XCTAssertGreaterThan(next.latitude, previous.latitude)
        }
    }

    func testReadingsEntirelyBehindTheFetchedPathAreDropped() {
        let seed = line(from: 0, to: 0.005)
        let live = line(from: 0.001, to: 0.003)
        XCTAssertEqual(LiveRoutePath.joined(seed: seed, live: live), seed)
    }

    func testAStationaryCarJoinsAtTheFirstOfItsRepeatedReadings() {
        // Waiting at a light reports the same position over and over. The join has
        // to be the earliest of them, or the wait is erased from the route.
        let seed = line(from: 0, to: 0.002)
        let standing = Array(repeating: CoordinateDTO(latitude: 37.002, longitude: -122), count: 4)
        let live = standing + [CoordinateDTO(latitude: 37.003, longitude: -122)]
        let joined = LiveRoutePath.joined(seed: seed, live: live)
        XCTAssertEqual(joined.count, seed.count + 4)
    }

    func testTheCarsLatestPositionSurvivesTheJoin() {
        let seed = line(from: 0, to: 0.004)
        let live = line(from: 0.0035, to: 0.010)
        XCTAssertEqual(LiveRoutePath.joined(seed: seed, live: live).last, live.last)
    }
}
