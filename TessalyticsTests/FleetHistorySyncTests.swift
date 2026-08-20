import SwiftData
import XCTest
@testable import Tessalytics

/// The two legs of a history sync must not share a fate.
///
/// A failing drive page used to abort `run` before the charge leg started, so an
/// unrelated network blip showed up in the UI as "No charges synced".
@MainActor
final class FleetHistorySyncTests: XCTestCase {
    private let serverID = UUID()

    func testChargesStillSyncWhenDrivesFail() async throws {
        let context = try makeContext()
        let sync = FleetHistorySync(context: context)
        let api = PartialAPI(drivesError: .backendUnavailable, charges: try fixture("charges", as: ChargesDataDTO.self))

        do {
            _ = try await sync.run(client: api, serverID: serverID, carID: 1, mode: .full)
            XCTFail("The drive failure must still surface")
        } catch {
            // The caller needs to know the pass was incomplete.
        }

        let charges = try context.fetch(FetchDescriptor<ChargeRecord>())
        XCTAssertEqual(charges.count, 2, "Charges must persist even though drives failed")
        XCTAssertEqual(try context.fetch(FetchDescriptor<DriveRecord>()).count, 0)
    }

    func testDrivesStillSyncWhenChargesFail() async throws {
        let context = try makeContext()
        let sync = FleetHistorySync(context: context)
        let api = PartialAPI(drives: try fixture("drives", as: DrivesDataDTO.self), chargesError: .backendUnavailable)

        _ = try? await sync.run(client: api, serverID: serverID, carID: 1, mode: .full)

        XCTAssertGreaterThan(try context.fetch(FetchDescriptor<DriveRecord>()).count, 0)
    }

    func testAPartialPassIsNotMarkedSynced() async throws {
        let context = try makeContext()
        let sync = FleetHistorySync(context: context)
        let api = PartialAPI(drivesError: .backendUnavailable, charges: try fixture("charges", as: ChargesDataDTO.self))

        _ = try? await sync.run(client: api, serverID: serverID, carID: 1, mode: .full)

        // Marking a partial pass would switch later runs to incremental and leave
        // the missing drives unfetched for good.
        XCTAssertEqual(sync.mode(serverID: serverID, carID: 1), .full)
    }

    func testACleanPassIsMarkedSynced() async throws {
        let context = try makeContext()
        let sync = FleetHistorySync(context: context)
        let api = PartialAPI(
            drives: try fixture("drives", as: DrivesDataDTO.self),
            charges: try fixture("charges", as: ChargesDataDTO.self)
        )

        let result = try await sync.run(client: api, serverID: serverID, carID: 1, mode: .full)

        XCTAssertTrue(result.completedFullSync)
        XCTAssertEqual(sync.mode(serverID: serverID, carID: 1), .incremental)
    }

    // MARK: - Helpers

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            ServerProfileRecord.self, VehicleRecord.self, DriveRecord.self,
            ChargeRecord.self, DetailCacheRecord.self, BatteryHealthRecord.self,
            FirmwareUpdateRecord.self, GlobalSettingsRecord.self, SyncMetadataRecord.self, TrackRecord.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func fixture<T: Decodable & Sendable>(_ name: String, as type: T.Type) throws -> T {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
                ?? bundle.url(forResource: name, withExtension: "json")
        )
        return try JSONDecoder.tessalytics.decode(Envelope<T>.self, from: Data(contentsOf: url)).data
    }
}

/// Succeeds or fails per leg, so a test can fail exactly one of them.
private struct PartialAPI: VehicleDataAPI {
    var drives: DrivesDataDTO?
    var drivesError: ClientError?
    var charges: ChargesDataDTO?
    var chargesError: ClientError?

    func ping() async throws {}
    func cars() async throws -> CarsDataDTO { throw ClientError.notFound }
    func car(carID: Int) async throws -> CarsDataDTO { throw ClientError.notFound }
    func status(carID: Int) async throws -> StatusDataDTO { throw ClientError.notFound }
    func drives(carID: Int, page: Int, show: Int, filter: DateRangeFilter) async throws -> DrivesDataDTO {
        if let drivesError { throw drivesError }
        return try XCTUnwrap(drives)
    }
    func drive(carID: Int, driveID: Int) async throws -> DriveDataDTO { throw ClientError.notFound }
    func charges(carID: Int, page: Int, show: Int, filter: DateRangeFilter) async throws -> ChargesDataDTO {
        if let chargesError { throw chargesError }
        return try XCTUnwrap(charges)
    }
    func charge(carID: Int, chargeID: Int) async throws -> ChargeDataDTO { throw ClientError.notFound }
    func currentCharge(carID: Int) async throws -> ChargeDataDTO { throw ClientError.notFound }
    func batteryHealth(carID: Int) async throws -> BatteryHealthDataDTO { throw ClientError.notFound }
    func updates(carID: Int) async throws -> UpdatesDataDTO { throw ClientError.notFound }
    func globalSettings() async throws -> GlobalSettingsDataDTO { throw ClientError.notFound }
}
