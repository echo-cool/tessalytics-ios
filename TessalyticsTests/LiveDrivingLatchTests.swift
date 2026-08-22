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

/// Where the car is, in words.
///
/// Two reports shaped this. The hero kept showing a home address — the app was
/// preferring TeslaMate's geofence, which names the last place a *drive* ended
/// inside one an owner had drawn, so a car parked or driving anywhere else got an
/// address it had left days ago. And a sleeping car reports no position at all,
/// which left the line blank for the state a car spends most of its life in.
@MainActor
final class LivePlaceResolutionTests: XCTestCase {
    private var environment: AppEnvironment!

    /// Answers with the coordinate it was asked about, so a test can see which
    /// position the app chose to name.
    private final class EchoingNames: PlaceNaming, @unchecked Sendable {
        private(set) var asked: [CoordinateDTO] = []

        func name(for coordinate: CoordinateDTO, precision: PlacePrecision) async -> String? {
            asked.append(coordinate)
            return "\(coordinate.latitude), \(coordinate.longitude)"
        }
    }

    private var names: EchoingNames!

    override func setUpWithError() throws {
        let schema = Schema([ServerProfileRecord.self, VehicleRecord.self, DriveRecord.self, ChargeRecord.self,
                             DetailCacheRecord.self, BatteryHealthRecord.self, FirmwareUpdateRecord.self,
                             GlobalSettingsRecord.self, SyncMetadataRecord.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        environment = AppEnvironment(container: container, keychain: NoStoredCredentials())
        names = EchoingNames()
        environment.usePlaceNamesForTesting(names)
    }

    override func tearDown() {
        environment = nil
        names = nil
    }

    private func reading(
        state: String?,
        shift: String?,
        speed: Double?,
        geofence: String? = nil,
        coordinate: CoordinateDTO?
    ) -> VehicleStatus {
        VehicleStatus(
            displayName: "Car",
            state: state,
            stateSince: nil,
            odometer: 1_000,
            carStatus: nil,
            carDetails: nil,
            carGeodata: CarGeodataDTO(geofence: geofence, location: coordinate),
            carVersions: nil,
            drivingDetails: DrivingDetailsDTO(shiftState: shift, power: 0, speed: speed, heading: nil, elevation: nil),
            climateDetails: nil,
            batteryDetails: nil,
            chargingDetails: nil,
            tpmsDetails: nil
        )
    }

    private func settle() async {
        for _ in 0..<60 where environment.livePlace.name == nil {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func testADrivingCarIsNamedByItsOwnPositionAndNotByAGeofence() async {
        // The reported bug, in live mode: the card said "Home" for a car that was
        // driving somewhere else entirely.
        let onTheRoad = CoordinateDTO(latitude: 37.4062, longitude: -122.0723)
        environment.applyLiveReadingForTesting(
            reading(state: "driving", shift: "D", speed: 55, geofence: "Home", coordinate: onTheRoad)
        )
        await settle()
        XCTAssertEqual(names.asked.last, onTheRoad)
        XCTAssertEqual(environment.livePlace.name, "37.4062, -122.0723")
    }

    func testAParkedCarWithNoPositionUsesTheLastOneItReported() async {
        // A sleeping car reports nothing. It has not moved since, so the last
        // reading taken while it was awake is still where it is.
        let driveway = CoordinateDTO(latitude: 51.5007, longitude: -0.1246)
        environment.lastLiveStatus = reading(state: "online", shift: "P", speed: 0, coordinate: driveway)
        environment.applyLiveReadingForTesting(
            reading(state: "asleep", shift: nil, speed: nil, coordinate: nil)
        )
        await settle()
        XCTAssertEqual(names.asked.last, driveway, "The last known position is where it is")
    }

    func testAParkedCarPrefersItsOwnReadingOverTheLastKnownOne() async {
        let stale = CoordinateDTO(latitude: 51.5007, longitude: -0.1246)
        let current = CoordinateDTO(latitude: 48.8584, longitude: 2.2945)
        environment.lastLiveStatus = reading(state: "online", shift: "P", speed: 0, coordinate: stale)
        environment.applyLiveReadingForTesting(
            reading(state: "online", shift: "P", speed: 0, coordinate: current)
        )
        await settle()
        XCTAssertEqual(names.asked.last, current)
    }

    func testNullIslandIsNotAFallbackEither() async {
        // A server with no reading publishes 0,0. Naming it would put the car in
        // the Gulf of Guinea.
        environment.lastLiveStatus = reading(
            state: "online", shift: "P", speed: 0, coordinate: CoordinateDTO(latitude: 0, longitude: 0)
        )
        environment.applyLiveReadingForTesting(
            reading(state: "asleep", shift: nil, speed: nil, coordinate: nil)
        )
        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertTrue(names.asked.isEmpty)
        XCTAssertNil(environment.livePlace.name, "Hidden rather than wrong")
    }

    func testAGapMidDriveKeepsNamingTheLastPositionRatherThanFallingBack() async {
        let onTheRoad = CoordinateDTO(latitude: 37.4062, longitude: -122.0723)
        let home = CoordinateDTO(latitude: 51.5007, longitude: -0.1246)
        environment.lastLiveStatus = reading(state: "online", shift: "P", speed: 0, coordinate: home)
        environment.applyLiveReadingForTesting(
            reading(state: "driving", shift: "D", speed: 55, coordinate: onTheRoad)
        )
        await settle()

        environment.applyLiveReadingForTesting(
            reading(state: "driving", shift: "D", speed: 55, coordinate: nil)
        )
        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(
            names.asked.last,
            onTheRoad,
            "A gap mid-drive must not send the car home"
        )
    }
}
