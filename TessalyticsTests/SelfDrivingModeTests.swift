import XCTest
@testable import Tessalytics

/// Whether a car is driving itself is not a thing to be wrong about in either
/// direction. TeslaMate publishes nothing about it, so the rule that matters most
/// here is the one about silence: no reading means no badge, never "manual".
final class SelfDrivingModeTests: XCTestCase {
    private func driving(state: String? = nil, engaged: Bool? = nil) -> DrivingDetailsDTO {
        DrivingDetailsDTO(
            shiftState: "D",
            power: 12,
            speed: 40,
            heading: 90,
            elevation: 10,
            autopilotState: state,
            isAutopilotEngaged: engaged
        )
    }

    func testAServerThatReportsNothingProducesNoBadge() {
        XCTAssertNil(driving().selfDrivingMode, "Silence is not 'driving manually'")
    }

    func testTheFullPackageIsRecognisedByEveryNameACarUses() {
        for name in ["FSD", "Full Self-Driving", "full self driving", "FSD Supervised"] {
            XCTAssertEqual(
                driving(state: name).selfDrivingMode,
                .fullSelfDriving,
                "\(name) should read as the full package"
            )
        }
    }

    func testALesserAidKeepsItsOwnName() {
        // The app does not know every name a car might use, and inventing one
        // for a reading it does not recognise would be worse than repeating it.
        XCTAssertEqual(driving(state: "Autosteer").selfDrivingMode, .assisted("Autosteer"))
        XCTAssertEqual(driving(state: "Autosteer").selfDrivingMode?.label, "Autosteer")
    }

    func testAReportedButDisengagedSystemSaysSo() {
        for name in ["off", "None", "disengaged", "manual", "standby"] {
            XCTAssertEqual(driving(state: name).selfDrivingMode, .off, "\(name) should read as disengaged")
        }
    }

    func testAFlagOnItsOwnIsEnough() {
        XCTAssertEqual(driving(engaged: true).selfDrivingMode, .fullSelfDriving)
        XCTAssertEqual(driving(engaged: false).selfDrivingMode, .off)
    }

    func testTheFlagOutranksAStaleName() {
        // Claiming a car is driving itself when it is not is the worse mistake,
        // so a `false` wins over a name that outlived it.
        XCTAssertEqual(driving(state: "Full Self-Driving", engaged: false).selfDrivingMode, .off)
    }

    func testEngagementIsOnlyReportedWhileDriving() {
        let parked = VehicleStatus(
            displayName: nil,
            state: "online",
            stateSince: nil,
            odometer: nil,
            carStatus: nil,
            carDetails: nil,
            carGeodata: nil,
            carVersions: nil,
            drivingDetails: DrivingDetailsDTO(
                shiftState: "P",
                power: 0,
                speed: 0,
                heading: nil,
                elevation: nil,
                autopilotState: "Full Self-Driving",
                isAutopilotEngaged: true
            ),
            climateDetails: nil,
            batteryDetails: nil,
            chargingDetails: nil,
            tpmsDetails: nil
        )
        // A parked car's last autopilot reading describes a journey that ended.
        XCTAssertNil(parked.selfDrivingMode)
    }

    func testABadgeIsBlueOnlyWhileSomethingIsSteering() {
        XCTAssertTrue(SelfDrivingMode.fullSelfDriving.isEngaged)
        XCTAssertTrue(SelfDrivingMode.assisted("Autosteer").isEngaged)
        XCTAssertFalse(SelfDrivingMode.off.isEngaged)
    }

    func testTheCompassNamesEveryQuadrant() {
        XCTAssertEqual(CompassPoint.name(for: 0), "N")
        XCTAssertEqual(CompassPoint.name(for: 44), "NE")
        XCTAssertEqual(CompassPoint.name(for: 90), "E")
        XCTAssertEqual(CompassPoint.name(for: 181), "S")
        XCTAssertEqual(CompassPoint.name(for: 359), "N", "Wrapping past north is still north")
        XCTAssertEqual(CompassPoint.name(for: -90), "W", "A negative bearing is still a bearing")
        XCTAssertNil(CompassPoint.name(for: nil))
    }
}
