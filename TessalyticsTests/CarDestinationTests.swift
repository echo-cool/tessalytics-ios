import CoreLocation
import XCTest
@testable import Tessalytics

/// The shortlist is the whole feature: what gets sent to a car depends entirely
/// on which ten rows the owner is shown and in what order.
final class DestinationShortlistTests: XCTestCase {
    private func place(
        _ name: String,
        visits: Int,
        daysAgo: Int,
        latitude: Double = 37.3861,
        longitude: Double = -122.0839
    ) -> VisitedPlace {
        VisitedPlace(
            id: name,
            name: name,
            latitude: latitude,
            longitude: longitude,
            visits: visits,
            lastVisit: Date(timeIntervalSince1970: 1_700_000_000 - Double(daysAgo) * 86_400)
        )
    }

    private var places: [VisitedPlace] {
        [
            place("Office", visits: 40, daysAgo: 1, latitude: 37.40, longitude: -122.10),
            place("Supercharger", visits: 12, daysAgo: 30, latitude: 37.50, longitude: -122.20),
            place("Trailhead", visits: 12, daysAgo: 2, latitude: 37.60, longitude: -122.30),
            place("Airport", visits: 3, daysAgo: 0, latitude: 37.62, longitude: -122.38)
        ]
    }

    func testMostVisitedLeadsWithTheMostVisited() {
        let shortlist = DestinationShortlist.make(from: places, order: .mostVisited)
        XCTAssertEqual(shortlist.first?.name, "Office")
    }

    func testATieOnVisitsIsBrokenByRecency() {
        // Otherwise two places visited twelve times each swap position on every
        // rebuild, and the row under a finger moves as it lands.
        let shortlist = DestinationShortlist.make(from: places, order: .mostVisited)
        XCTAssertEqual(shortlist.map(\.name), ["Office", "Trailhead", "Supercharger", "Airport"])
    }

    func testRecentLeadsWithTheLastPlaceTheCarWent() {
        let shortlist = DestinationShortlist.make(from: places, order: .recent)
        XCTAssertEqual(shortlist.first?.name, "Airport")
    }

    func testNearestIsMeasuredFromWhereTheCarIs() {
        let origin = CLLocationCoordinate2D(latitude: 37.61, longitude: -122.37)
        let shortlist = DestinationShortlist.make(from: places, order: .nearest, origin: origin)
        XCTAssertEqual(shortlist.first?.name, "Airport")
        XCTAssertEqual(shortlist.last?.name, "Office")
    }

    func testNearestWithNowhereToMeasureFromFallsBackRatherThanInventingAnOrder() {
        // A car that has never reported a position has no "nearest", and an
        // arbitrary order presented under that heading is a lie.
        let shortlist = DestinationShortlist.make(from: places, order: .nearest, origin: nil)
        XCTAssertEqual(shortlist.map(\.name), DestinationShortlist.make(from: places, order: .mostVisited).map(\.name))
    }

    func testFilteringMatchesPartOfANameRegardlessOfCase() {
        let shortlist = DestinationShortlist.make(from: places, order: .mostVisited, filter: "charg")
        XCTAssertEqual(shortlist.map(\.name), ["Supercharger"])
    }

    func testTheShortlistIsCappedSoTheHomeScreenStaysAHomeScreen() {
        let many = (0..<40).map { place("Place \($0)", visits: 40 - $0, daysAgo: $0) }
        XCTAssertEqual(DestinationShortlist.make(from: many, order: .mostVisited).count, 10)
    }

    func testAFilterThatMatchesNothingIsEmptyRatherThanEverything() {
        XCTAssertTrue(DestinationShortlist.make(from: places, order: .recent, filter: "zzz").isEmpty)
    }
}

final class CarDestinationLinkTests: XCTestCase {
    /// The car re-geocodes whatever it is handed. A name would be re-resolved to
    /// whichever "Whole Foods" the car's own search prefers; a coordinate cannot
    /// be misread.
    func testTheLinkCarriesTheCoordinateRatherThanTheName() {
        let destination = CarDestination(
            id: "1",
            name: "Whole Foods Market",
            latitude: 37.386052,
            longitude: -122.083851,
            visits: 9,
            lastVisit: .now
        )
        XCTAssertEqual(destination.shareText, "https://maps.google.com/?q=37.386052,-122.083851")
        XCTAssertFalse(destination.shareText.contains("Whole Foods"))
    }

    func testASouthernAndWesternCoordinateKeepsItsSign() {
        let destination = CarDestination(
            id: "2",
            name: "Somewhere",
            latitude: -33.868820,
            longitude: 151.209290,
            visits: 1,
            lastVisit: .now
        )
        XCTAssertEqual(destination.shareText, "https://maps.google.com/?q=-33.868820,151.209290")
    }
}
