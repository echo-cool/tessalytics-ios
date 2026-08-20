import XCTest
@testable import Tessalytics

final class VisitedPlacesTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func endpoint(_ minutes: Int, _ latitude: Double, _ longitude: Double, label: String? = nil) -> VisitedEndpoint {
        VisitedEndpoint(
            date: base.addingTimeInterval(Double(minutes) * 60),
            label: label,
            latitude: latitude,
            longitude: longitude
        )
    }

    func testRepeatedVisitsToOneSpotBecomeASinglePlace() {
        // A car that parks in the same driveway nightly must not stack a marker
        // per night on the same pin.
        let endpoints = (0..<20).map { endpoint($0 * 60, 37.3584 + Double($0) * 0.00001, -121.9848, label: "Home") }
        let places = VisitedPlacesModel.places(from: endpoints)
        XCTAssertEqual(places.count, 1)
        XCTAssertEqual(places.first?.visits, 20)
        XCTAssertEqual(places.first?.name, "Home")
        XCTAssertTrue(places.first?.isFrequent == true)
    }

    func testDistinctSpotsStaySeparate() {
        let places = VisitedPlacesModel.places(from: [
            endpoint(0, 37.3584, -121.9848, label: "Work"),
            endpoint(60, 37.4100, -122.0500, label: "Shops")
        ])
        XCTAssertEqual(Set(places.map(\.name)), ["Work", "Shops"])
    }

    func testTheMostRecentLabelWins() {
        // A geofence the owner added later is a better name than the raw address
        // recorded before it existed.
        let places = VisitedPlacesModel.places(from: [
            endpoint(0, 37.3584, -121.9848, label: "San Tomas Aquino Creek Trail"),
            endpoint(600, 37.3584, -121.9848, label: "Polaris Wireless")
        ])
        XCTAssertEqual(places.first?.name, "Polaris Wireless")
    }

    func testTheNullIslandIsRejected() {
        // A missing reading serialises as zero, which otherwise plants a marker
        // in the Atlantic and drags the map region with it.
        let places = VisitedPlacesModel.places(from: [
            endpoint(0, 0, 0),
            endpoint(60, 37.3584, -121.9848, label: "Real")
        ])
        XCTAssertEqual(places.count, 1)
        XCTAssertEqual(places.first?.name, "Real")
    }

    func testOutOfRangeCoordinatesAreRejected() {
        XCTAssertTrue(VisitedPlacesModel.places(from: [endpoint(0, 91, 0), endpoint(1, 0, 181)]).isEmpty)
    }

    func testPlacesAreRankedByVisits() {
        var endpoints = (0..<5).map { endpoint($0, 37.10, -121.10, label: "Often") }
        endpoints.append(endpoint(600, 37.50, -121.50, label: "Once"))
        XCTAssertEqual(VisitedPlacesModel.places(from: endpoints).map(\.name), ["Often", "Once"])
    }

    func testTheLimitKeepsTheMostVisited() {
        var endpoints: [VisitedEndpoint] = []
        for spot in 0..<10 {
            // Spot 9 is visited most, spot 0 least.
            for visit in 0...spot {
                endpoints.append(endpoint(spot * 100 + visit, 37.0 + Double(spot) * 0.5, -121.0, label: "Spot \(spot)"))
            }
        }
        let places = VisitedPlacesModel.places(from: endpoints, limit: 3)
        XCTAssertEqual(places.map(\.name), ["Spot 9", "Spot 8", "Spot 7"])
    }

    func testAPlaceWithoutALabelIsStillNamed() {
        XCTAssertEqual(VisitedPlacesModel.places(from: [endpoint(0, 37.1, -121.1)]).first?.name, "Unnamed place")
    }

    func testEmptyInputProducesNothing() {
        XCTAssertTrue(VisitedPlacesModel.places(from: []).isEmpty)
    }
}

final class VehicleSpecificationTests: XCTestCase {
    func testAPlausibleRatingIsKept() {
        let specification = VehicleSpecification.sanitised(capacityNew: 84, maxRangeNew: 358)
        XCTAssertEqual(specification.capacityNew, 84)
        XCTAssertEqual(specification.maxRangeNew, 358)
        XCTAssertFalse(specification.isEmpty)
    }

    func testAnImplausibleRatingIsDiscardedRatherThanStored() {
        // A typo here would poison health, capacity lost, range lost and cycles.
        XCTAssertNil(VehicleSpecification.sanitised(capacityNew: 8400, maxRangeNew: nil).capacityNew)
        XCTAssertNil(VehicleSpecification.sanitised(capacityNew: 0, maxRangeNew: nil).capacityNew)
        XCTAssertNil(VehicleSpecification.sanitised(capacityNew: nil, maxRangeNew: 99_000).maxRangeNew)
    }

    func testNothingSuppliedIsEmpty() {
        XCTAssertTrue(VehicleSpecification.sanitised(capacityNew: nil, maxRangeNew: nil).isEmpty)
    }

    func testAnOwnerRatingReplacesTheDerivedFigureAndRecomputesHealth() {
        // The reported figure is 97.4% against a derived 74.4 kWh; against the
        // real 84 kWh pack the same 72.5 kWh is 86.3%.
        let health = FleetStatistics.BatteryHealth(
            capacityNew: 84,
            capacityNow: 72.5,
            maxRangeNew: 358,
            maxRangeNow: 331,
            derivedCapacityNew: 74.4,
            derivedMaxRangeNew: 340,
            isSpecificationOverridden: true,
            reportedHealthPercent: 97.4,
            ratedEfficiency: nil,
            observedAt: nil
        )
        XCTAssertEqual(try XCTUnwrap(health.healthPercent), 86.31, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(health.capacityLost), 11.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(health.rangeLost), 27, accuracy: 0.001)
    }

    func testTheServerFigureIsUsedWhenNoCapacitiesAreKnown() {
        let health = FleetStatistics.BatteryHealth(
            capacityNew: nil,
            capacityNow: nil,
            maxRangeNew: nil,
            maxRangeNow: nil,
            reportedHealthPercent: 91.5,
            ratedEfficiency: nil,
            observedAt: nil
        )
        XCTAssertEqual(health.healthPercent, 91.5)
    }

    func testHealthNeverExceedsOneHundredPercent() {
        // A pack that measures slightly above its rating is a modelling artefact,
        // not a battery that grew.
        let health = FleetStatistics.BatteryHealth(
            capacityNew: 74,
            capacityNow: 75.2,
            maxRangeNew: nil,
            maxRangeNow: nil,
            reportedHealthPercent: nil,
            ratedEfficiency: nil,
            observedAt: nil
        )
        XCTAssertEqual(health.healthPercent, 100)
    }
}
