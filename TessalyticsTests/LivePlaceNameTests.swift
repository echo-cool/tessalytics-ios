import XCTest
@testable import Tessalytics

/// The reported bug: the app kept showing an address the car had not parked at.
///
/// Two causes, one on each side. The server answered with the last drive that
/// ended *in a geofence*, skipping past every drive that ended somewhere unnamed —
/// fixed in the backend. And the app had nothing else to fall back on, so a car
/// standing anywhere without a geofence had no place at all. This is the second
/// half: a name resolved from the coordinate the car is actually at.
@MainActor
final class LivePlaceNameTests: XCTestCase {
    /// Counts what it is asked, so the throttle can be observed rather than
    /// inferred.
    private final class CountingNames: PlaceNaming, @unchecked Sendable {
        private(set) var requests: [(CoordinateDTO, PlacePrecision)] = []
        var answer = "Somewhere"

        func name(for coordinate: CoordinateDTO, precision: PlacePrecision) async -> String? {
            requests.append((coordinate, precision))
            return answer
        }
    }

    private let start = Date(timeIntervalSince1970: 1_000)
    private let mountainView = CoordinateDTO(latitude: 37.3861, longitude: -122.0839)

    /// A coordinate `metres` due north of another.
    private func north(of coordinate: CoordinateDTO, metres: Double) -> CoordinateDTO {
        CoordinateDTO(latitude: coordinate.latitude + metres / 111_320, longitude: coordinate.longitude)
    }

    private func resolve(_ place: LivePlaceName) async {
        // The lookup runs in a task; let it land.
        for _ in 0..<50 where place.name == nil {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func testItResolvesTheFirstPositionItIsGiven() async {
        let names = CountingNames()
        let place = LivePlaceName(resolver: names)
        place.update(for: mountainView, precision: .street, now: start)
        await resolve(place)
        XCTAssertEqual(place.name, "Somewhere")
        XCTAssertEqual(names.requests.count, 1)
    }

    func testAMovingCarIsOnARoadAndAStoppedOneIsAtAnAddress() async {
        let names = CountingNames()
        let place = LivePlaceName(resolver: names)
        place.update(for: mountainView, precision: .street, now: start)
        await resolve(place)
        // Coming to a stop is worth a second look, whatever the throttle says:
        // the road the car was on becomes the address it is standing at.
        place.update(for: mountainView, precision: .address, now: start + 1)
        for _ in 0..<50 where names.requests.count < 2 { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(names.requests.map(\.1), [.street, .address])
    }

    func testACarThatHasBarelyMovedIsNotAskedAgain() {
        let place = LivePlaceName(resolver: CountingNames())
        // Nothing resolved yet, so the first is always worth asking.
        XCTAssertTrue(place.shouldLookUp(mountainView, precision: .street, now: start))
    }

    func testTheThrottleHoldsBothDistanceAndTime() async {
        let names = CountingNames()
        let place = LivePlaceName(resolver: names)
        place.update(for: mountainView, precision: .street, now: start)
        await resolve(place)

        let nearby = north(of: mountainView, metres: 20)
        XCTAssertFalse(
            place.shouldLookUp(nearby, precision: .street, now: start + 60),
            "Twenty metres is the same road, however long ago it was asked"
        )

        let farther = north(of: mountainView, metres: 400)
        XCTAssertFalse(
            place.shouldLookUp(farther, precision: .street, now: start + 2),
            "Far enough, but two seconds after the last request — the geocoder is rate limited"
        )
        XCTAssertTrue(
            place.shouldLookUp(farther, precision: .street, now: start + LivePlaceName.minimumInterval + 1),
            "Far enough and long enough"
        )
    }

    func testAFailedLookupLeavesTheLastNameStanding() async {
        // A car in a tunnel is still on the road it was on.
        final class Failing: PlaceNaming {
            func name(for coordinate: CoordinateDTO, precision: PlacePrecision) async -> String? { nil }
        }
        let names = CountingNames()
        let place = LivePlaceName(resolver: names)
        place.update(for: mountainView, precision: .street, now: start)
        await resolve(place)
        XCTAssertEqual(place.name, "Somewhere")

        let failing = LivePlaceName(resolver: Failing())
        failing.update(for: mountainView, precision: .street, now: start)
        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertNil(failing.name, "Nothing was ever resolved, so there is nothing to keep")
    }

    func testClearingForgetsEverything() async {
        let place = LivePlaceName(resolver: CountingNames())
        place.update(for: mountainView, precision: .street, now: start)
        await resolve(place)
        place.clear()
        XCTAssertNil(place.name)
        XCTAssertNil(place.resolvedAt)
    }

    func testAMissingCoordinateClearsTheName() async {
        let place = LivePlaceName(resolver: CountingNames())
        place.update(for: mountainView, precision: .street, now: start)
        await resolve(place)
        place.update(for: nil, precision: .street, now: start + 1)
        XCTAssertNil(place.name)
    }

    func testDistanceIsInMetres() {
        // A degree of latitude is about 111 km, so a thousandth is about 111 m.
        let moved = LivePlaceName.distance(from: mountainView, to: north(of: mountainView, metres: 500))
        XCTAssertEqual(moved, 500, accuracy: 5)
    }
}
