import XCTest
@testable import Tessalytics

/// The line at the top of the home screen.
///
/// Two reported problems live here. "Driving" was all it said at a red light,
/// which is the moment a driver has both the attention to read the screen and the
/// least on it to read. And the place it named was a geofence from some earlier
/// drive rather than where the car actually was.
final class VehicleHeroSummaryTests: XCTestCase {
    private func status(
        state: String = "driving",
        shift: String? = "D",
        speed: Double? = 63,
        geofence: String? = nil,
        autopilot: String? = nil,
        engaged: Bool? = nil
    ) -> VehicleStatus {
        VehicleStatus(
            displayName: "Aurora",
            state: state,
            stateSince: nil,
            odometer: 18_000,
            carStatus: nil,
            carDetails: nil,
            carGeodata: CarGeodataDTO(
                geofence: geofence,
                location: CoordinateDTO(latitude: 37.3861, longitude: -122.0839)
            ),
            carVersions: nil,
            drivingDetails: DrivingDetailsDTO(
                shiftState: shift,
                power: 20,
                speed: speed,
                heading: 90,
                elevation: 30,
                autopilotState: autopilot,
                isAutopilotEngaged: engaged
            ),
            climateDetails: nil,
            batteryDetails: StatusBatteryDTO(
                estBatteryRange: 214, ratedBatteryRange: nil, idealBatteryRange: nil,
                batteryLevel: 71, usableBatteryLevel: 70
            ),
            chargingDetails: nil,
            tpmsDetails: nil
        )
    }

    private func summary(
        _ status: VehicleStatus,
        placeName: String? = nil
    ) -> VehicleHeroSummary {
        VehicleHeroSummary(status: status, units: .metricDefaults, placeName: placeName)
    }

    func testAMovingCarLeadsWithItsSpeed() {
        XCTAssertEqual(summary(status()).headline, "Driving · 63 km/h")
    }

    func testACarAtARedLightSaysItIsStopped() {
        // "Driving · 0 km/h" reads as a screen that has frozen.
        let stopped = summary(status(speed: 0))
        XCTAssertEqual(stopped.headline, "Stopped")
        XCTAssertEqual(stopped.stateNoun, "Stopped")
        XCTAssertTrue(stopped.isNotable, "It still gets the loud line: the journey has not ended")
        XCTAssertTrue(stopped.isStoppedInDrive)
    }

    func testAStoppedCarShowsWhereItIsStopped() {
        // The whole point of saying "Stopped": there is now room for the thing
        // the driver does not already know.
        XCTAssertEqual(
            summary(status(speed: 0), placeName: "1350 El Camino Real, Mountain View").placeText,
            "1350 El Camino Real, Mountain View"
        )
    }

    func testAMovingCarAlsoNamesTheRoadItIsOn() {
        XCTAssertEqual(summary(status(), placeName: "El Camino Real").placeText, "El Camino Real")
    }

    func testAGeofenceOutranksAResolvedAddress() {
        // "Home" is what the owner called the place. No geocoder improves on it.
        XCTAssertEqual(
            summary(status(state: "online", shift: "P", speed: 0, geofence: "Home"), placeName: "1 Elm Street").placeText,
            "Home"
        )
    }

    func testAParkedCarWithNoGeofenceStillKnowsWhereItIs() {
        // The reported bug, from the app's side: without a geofence there was
        // nothing to show, so the screen fell back to whatever it had last.
        let parked = summary(status(state: "online", shift: "P", speed: 0), placeName: "12 Crystal Drive")
        XCTAssertEqual(parked.headline, "12 Crystal Drive")
        XCTAssertEqual(parked.stateNoun, "Parked")
        XCTAssertFalse(parked.isNotable)
    }

    func testAParkedCarThatKnowsNothingSaysSoRatherThanGuessing() {
        let parked = summary(status(state: "online", shift: "P", speed: 0))
        XCTAssertEqual(parked.headline, "Parked")
        XCTAssertNil(parked.placeText)
    }

    func testReversingOutranksTheSpeed() {
        XCTAssertEqual(summary(status(shift: "R", speed: 4)).headline, "Reversing")
        XCTAssertEqual(summary(status(shift: "N", speed: 0)).headline, "In neutral")
    }

    func testTheSelfDrivingReadingIsCarriedOnlyWhenTheServerReportsIt() {
        XCTAssertNil(summary(status()).selfDriving, "No reading, no badge")
        XCTAssertEqual(
            summary(status(autopilot: "Full Self-Driving", engaged: true)).selfDriving,
            .fullSelfDriving
        )
        XCTAssertEqual(summary(status(autopilot: "off", engaged: false)).selfDriving, .off)
    }
}
