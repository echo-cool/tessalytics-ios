import SwiftData
import XCTest
@testable import Tessalytics

/// The whole path, from a server writing bytes to the state the views read.
///
/// The unit tests covered every piece and the feature still delivered nothing for
/// two releases, so this drives the real object the screens observe:
/// `AppEnvironment`, against a real socket. If this passes, live mode works.
@MainActor
final class LiveStreamRefreshTests: XCTestCase {
    private var server: FakeEventStreamServer!
    private var environment: AppEnvironment!

    override func setUpWithError() throws {
        server = try FakeEventStreamServer()
        let schema = Schema([ServerProfileRecord.self, VehicleRecord.self, DriveRecord.self, ChargeRecord.self,
                             DetailCacheRecord.self, BatteryHealthRecord.self, FirmwareUpdateRecord.self,
                             GlobalSettingsRecord.self, SyncMetadataRecord.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        environment = AppEnvironment(container: container, keychain: NoCredentials())
        let profile = ServerProfile(
            id: UUID(),
            name: "Fake",
            baseURL: server.baseURL,
            authenticationMethod: .none,
            allowsLocalHTTP: true
        )
        environment.selectedProfile = profile
        environment.selectedVehicle = Vehicle(
            serverID: profile.id,
            id: 1,
            name: "Test",
            model: nil,
            trim: nil,
            totalDrives: nil,
            totalCharges: nil,
            totalUpdates: nil
        )
    }

    override func tearDown() {
        environment.stopLiveStream()
        environment = nil
        server.stop()
        server = nil
    }

    private static func body(speed: Double, level: Int = 71, latitude: Double = 37.36, longitude: Double = -121.98) -> String {
        """
        {"data":{"state":{"vehicle_id":1,"state":"driving","state_since":"2026-08-21T04:12:19Z",\
        "name":"wyy","location":{"latitude":\(latitude),"longitude":\(longitude),"heading":120},\
        "battery":{"level":\(level),"usable_level":\(level),"range":234.8},\
        "driving":{"shift_state":"D","speed":\(speed),"power":34.0,"odometer":33938.4}}},\
        "meta":{"source":"mixed","units":{"length":"mi","temperature":"C","pressure":"psi","range":"rated"}}}
        """
    }

    /// Opens the stream and waits for the socket, so a send has somewhere to go.
    private func connect() async throws {
        environment.startLiveStream()
        try await waitFor("the client to connect") { self.server.hasClient }
    }

    /// Waits for the app's own state to satisfy a condition, rather than sleeping
    /// a fixed amount and hoping.
    private func waitFor(
        _ description: String,
        timeout: TimeInterval = 10,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(40))
        }
        XCTFail("Timed out waiting for \(description)")
    }

    func testAStreamedReadingRefreshesTheStatusTheScreensRead() async throws {
        try await connect()
        server.send(state: Self.body(speed: 63))
        try await waitFor("the reading to land") { self.environment.status?.drivingDetails?.speed == 63 }

        XCTAssertTrue(environment.status?.isDriving == true)
        XCTAssertEqual(environment.status?.batteryDetails?.batteryLevel, 71)
        XCTAssertNotNil(environment.statusFetchedAt, "The reading carries a time, or the screen cannot age it")
        XCTAssertEqual(environment.statusUnits?.unitOfLength, "mi")
        XCTAssertFalse(environment.isOffline)
        XCTAssertTrue(environment.isStreamingLive, "A delivered reading means the badge says live")
        XCTAssertNil(environment.liveStreamMessage)
    }

    func testEachReadingMovesTheDisplayedValueAndItsTimestamp() async throws {
        // The complaint this whole path exists to answer: the number on screen has
        // to move as the car moves, not once every poll.
        try await connect()
        var stamps: [Date] = []
        for speed in [20.0, 40.0, 60.0] {
            server.send(state: Self.body(speed: speed))
            try await waitFor("speed \(speed)") { self.environment.status?.drivingDetails?.speed == speed }
            stamps.append(try XCTUnwrap(environment.statusFetchedAt))
        }
        XCTAssertEqual(stamps, stamps.sorted(), "Each reading is newer than the one before")
        XCTAssertGreaterThan(stamps.count, 2)
    }

    func testReadingsBuildTheLiveChartsAndTheRoute() async throws {
        try await connect()
        // Moving, so the positions are distinct points on a route. Spaced out
        // because the buffer deliberately folds readings that share an instant —
        // two marks on one x position is not a chart — and a real stream arrives
        // every 0.4s, not three times in a millisecond.
        for (index, speed) in [30.0, 35.0, 40.0].enumerated() {
            server.send(state: Self.body(
                speed: speed,
                latitude: 37.36 + Double(index) * 0.001,
                longitude: -121.98 + Double(index) * 0.001
            ))
            try await waitFor("sample \(index)") { self.environment.liveTelemetry.samples.count > index }
            try await Task.sleep(for: .milliseconds(320))
        }

        XCTAssertGreaterThanOrEqual(environment.liveTelemetry.samples.count, 3)
        XCTAssertEqual(environment.liveTelemetry.latest?.speed, 40)
        XCTAssertGreaterThanOrEqual(environment.liveTelemetry.trail.count, 3, "The hero map draws these")
        XCTAssertEqual(environment.liveTelemetry.maximumSpeed, 40)
        XCTAssertGreaterThanOrEqual(environment.liveMapRoute.coordinates.count, 3, "The line the map draws")
    }

    func testARepeatedPositionDoesNotRedrawTheRouteOnTheMap() async throws {
        // The reported bug: the route flashed on every refresh because it was
        // rebuilt from scratch each time anything arrived. A car sitting at a
        // light streams readings without moving, and the line must not react.
        try await connect()
        server.send(state: Self.body(speed: 30, latitude: 37.36, longitude: -121.98))
        try await waitFor("the first position") { !self.environment.liveMapRoute.isEmpty }
        try await Task.sleep(for: .milliseconds(320))
        server.send(state: Self.body(speed: 20, latitude: 37.362, longitude: -121.982))
        try await waitFor("a route with a second point") { self.environment.liveMapRoute.coordinates.count > 1 }

        let drawn = environment.liveMapRoute.revision
        for speed in [10.0, 5.0, 0.0] {
            try await Task.sleep(for: .milliseconds(320))
            server.send(state: Self.body(speed: speed, latitude: 37.362, longitude: -121.982))
            try await waitFor("speed \(speed)") { self.environment.status?.drivingDetails?.speed == speed }
        }

        XCTAssertGreaterThan(environment.liveTelemetry.samples.count, 2, "Readings did keep arriving")
        XCTAssertEqual(
            environment.liveMapRoute.revision,
            drawn,
            "Readings from a stationary car redrew the route"
        )
    }

    func testParkingClearsTheDriveBuffer() async throws {
        try await connect()
        server.send(state: Self.body(speed: 30))
        try await waitFor("a driving reading") { !self.environment.liveTelemetry.samples.isEmpty }

        let parked = Self.body(speed: 0)
            .replacingOccurrences(of: "\"state\":\"driving\"", with: "\"state\":\"online\"")
            .replacingOccurrences(of: "\"shift_state\":\"D\"", with: "\"shift_state\":\"P\"")
        server.send(state: parked)
        try await waitFor("the drive to end") { self.environment.liveTelemetry.samples.isEmpty }

        XCTAssertTrue(environment.liveRoute.isEmpty, "A finished drive leaves no route behind on the hero")
        XCTAssertTrue(environment.liveMapRoute.isEmpty, "And no line on the map")
    }

    func testTheLastReadingSurvivesTheAppGoingAway() async throws {
        // Persistence is throttled, so the newest reading is usually only in
        // memory. Backgrounding has to write it or a cold launch shows an older
        // one than the app had.
        try await connect()
        server.send(state: Self.body(speed: 51, level: 64))
        try await waitFor("the reading to land") { self.environment.status?.drivingDetails?.speed == 51 }

        environment.handleBackgroundEntry()
        let profile = try XCTUnwrap(environment.selectedProfile)
        let cached = VehicleStatusCache(context: environment.modelContext)
            .load(serverID: profile.id, carID: 1)
        XCTAssertEqual(cached?.status.batteryDetails?.batteryLevel, 64)
        XCTAssertFalse(environment.isStreamingLive, "Backgrounding closes the stream")
    }
}

private struct NoCredentials: CredentialStore {
    func save(_ credentials: StoredCredentials, profileID: UUID) throws {}
    func credentials(profileID: UUID) throws -> StoredCredentials? { nil }
    func delete(profileID: UUID) throws {}
}
