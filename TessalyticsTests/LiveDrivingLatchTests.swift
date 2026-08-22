import SwiftData
import XCTest
@testable import Tessalytics

/// The reported bug: the map on the hero card flashed red to black and back,
/// several times a minute, for the whole of a drive.
///
/// The mechanism, once it was reproduced: one reading that arrived without a
/// position — or that simply failed to say the car was in gear — took the map out
/// of the view tree. A `Map` that leaves the tree is an `MKMapView` torn down, and
/// the one built to replace it renders as an empty surface until its tiles come
/// back. The card's tint is what showed through in between.
///
/// So these hold the invariant the fix rests on: a gap in a reading changes
/// nothing about the shape of the screen. Only a statement does.
@MainActor
final class LiveDrivingLatchTests: XCTestCase {
    private var environment: AppEnvironment!

    override func setUpWithError() throws {
        let schema = Schema([ServerProfileRecord.self, VehicleRecord.self, DriveRecord.self, ChargeRecord.self,
                             DetailCacheRecord.self, BatteryHealthRecord.self, FirmwareUpdateRecord.self,
                             GlobalSettingsRecord.self, SyncMetadataRecord.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        environment = AppEnvironment(container: container, keychain: NoStoredCredentials())
    }

    override func tearDown() {
        environment = nil
    }

    private func reading(
        state: String? = "driving",
        shift: String? = "D",
        speed: Double? = 40,
        coordinate: CoordinateDTO? = CoordinateDTO(latitude: 37.36, longitude: -121.98)
    ) -> VehicleStatus {
        VehicleStatus(
            displayName: "Car",
            state: state,
            stateSince: nil,
            odometer: 1_000,
            carStatus: nil,
            carDetails: nil,
            carGeodata: CarGeodataDTO(geofence: nil, location: coordinate),
            carVersions: nil,
            drivingDetails: DrivingDetailsDTO(
                shiftState: shift, power: 12, speed: speed, heading: 90, elevation: 12
            ),
            climateDetails: nil,
            batteryDetails: StatusBatteryDTO(
                estBatteryRange: 200, ratedBatteryRange: nil, idealBatteryRange: nil,
                batteryLevel: 70, usableBatteryLevel: 70
            ),
            chargingDetails: nil,
            tpmsDetails: nil
        )
    }

    /// Feeds a reading down the same path the stream and the poll both use.
    private func apply(_ status: VehicleStatus, at now: Date = .now) {
        environment.status = status
        environment.applyLiveReadingForTesting(status, now: now)
    }

    func testADrivingReadingLatchesTheScreenLive() {
        apply(reading())
        XCTAssertTrue(environment.isLiveDriving)
        XCTAssertEqual(environment.liveCoordinate, CoordinateDTO(latitude: 37.36, longitude: -121.98))
    }

    func testAReadingWithoutAPositionKeepsTheLastOne() {
        // This is the flash, exactly. The map is drawn at `liveCoordinate`, and a
        // nil here is what used to remove it from the screen for one frame.
        apply(reading())
        let held = environment.liveCoordinate
        apply(reading(coordinate: nil))
        XCTAssertEqual(environment.liveCoordinate, held, "A gap in a reading is not the car disappearing")
        XCTAssertTrue(environment.isLiveDriving)
    }

    func testAReadingThatSimplyFailsToMentionTheGearKeepsTheDriveOnScreen() {
        apply(reading())
        // No state, no shift: the reading says nothing either way.
        apply(reading(state: nil, shift: nil))
        XCTAssertTrue(environment.isLiveDriving, "Silence is not the end of a journey")
        XCTAssertFalse(environment.liveTelemetry.samples.isEmpty, "And the charts keep their history")
    }

    func testShiftingIntoParkEndsTheDriveImmediately() {
        apply(reading())
        apply(reading(state: "online", shift: "P", speed: 0))
        XCTAssertFalse(environment.isLiveDriving, "P is a statement, not a silence")
        XCTAssertNil(environment.liveCoordinate)
        XCTAssertTrue(environment.liveTelemetry.samples.isEmpty)
    }

    func testGoingToSleepEndsTheDriveImmediately() {
        apply(reading())
        apply(reading(state: "asleep", shift: nil, speed: nil))
        XCTAssertFalse(environment.isLiveDriving)
    }

    func testChargingEndsTheDriveImmediately() {
        // Driving straight into a charge is a real sequence, and it must not sit
        // latched in "driving" waiting for a grace to expire.
        apply(reading())
        apply(reading(state: "charging", shift: nil, speed: 0))
        XCTAssertFalse(environment.isLiveDriving)
    }

    func testAnAmbiguousReadingEndsTheDriveOnceTheGraceHasPassed() {
        let start = Date(timeIntervalSince1970: 1_000)
        apply(reading(), at: start)
        apply(reading(state: nil, shift: nil), at: start + 1)
        XCTAssertTrue(environment.isLiveDriving, "Inside the grace")

        apply(reading(state: nil, shift: nil), at: start + AppEnvironment.drivingGrace + 1)
        XCTAssertFalse(environment.isLiveDriving, "A drive cannot stay latched on silence forever")
    }

    func testAStoppedCarIsStillOnTheDrive() {
        // At a red light: speed zero, gear D. The drive has not ended, and the
        // screen must not be rebuilt as if it had.
        apply(reading(speed: 0))
        XCTAssertTrue(environment.isLiveDriving)
        XCTAssertTrue(environment.status?.isStoppedInDrive == true)
        XCTAssertNotNil(environment.liveCoordinate)
    }

    func testAPositionAtNullIslandIsNotAPosition() {
        apply(reading(coordinate: CoordinateDTO(latitude: 0, longitude: 0)))
        XCTAssertNil(environment.liveCoordinate, "0,0 is a server with no reading, not the Gulf of Guinea")
    }
}

private struct NoStoredCredentials: CredentialStore {
    func save(_ credentials: StoredCredentials, profileID: UUID) throws {}
    func credentials(profileID: UUID) throws -> StoredCredentials? { nil }
    func delete(profileID: UUID) throws {}
}
