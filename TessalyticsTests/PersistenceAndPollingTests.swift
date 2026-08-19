import SwiftData
import XCTest
@testable import Tessalytics

@MainActor
final class PersistenceAndPollingTests: XCTestCase {
    func testUpsertsPreventDuplicatesAndPartitionServersAndVehicles() async throws {
        let container = try makeContainer()
        let repository = DriveRepository(context: container.mainContext)
        let data = try drivesFixture()
        let api = RepositoryAPI(drivesValue: data)
        let serverA = UUID(), serverB = UUID()

        _ = try await repository.refresh(client: api, serverID: serverA, carID: 1, page: 1, filter: .init())
        _ = try await repository.refresh(client: api, serverID: serverA, carID: 1, page: 1, filter: .init())
        _ = try await repository.refresh(client: api, serverID: serverA, carID: 2, page: 1, filter: .init())
        _ = try await repository.refresh(client: api, serverID: serverB, carID: 1, page: 1, filter: .init())

        XCTAssertEqual(repository.cached(serverID: serverA, carID: 1).count, 2)
        XCTAssertEqual(repository.cached(serverID: serverA, carID: 2).count, 2)
        XCTAssertEqual(repository.cached(serverID: serverB, carID: 1).count, 2)
    }

    func testOfflineFailurePreservesCache() async throws {
        let container = try makeContainer()
        let repository = DriveRepository(context: container.mainContext)
        let server = UUID()
        _ = try await repository.refresh(client: RepositoryAPI(drivesValue: try drivesFixture()), serverID: server, carID: 1, page: 1, filter: .init())
        do { _ = try await repository.refresh(client: RepositoryAPI(error: .transport), serverID: server, carID: 1, page: 1, filter: .init()); XCTFail("Expected failure") } catch {}
        XCTAssertEqual(repository.cached(serverID: server, carID: 1).count, 2)
    }

    func testStatusPollingStartsAndCancels() throws {
        let container = try makeContainer()
        let environment = AppEnvironment(container: container, keychain: TestCredentialStore())
        let server = ServerProfile(id: UUID(), name: "Test", baseURL: URL(string: "https://example.invalid")!, authenticationMethod: .none, allowsLocalHTTP: false)
        environment.selectedProfile = server
        environment.selectedVehicle = Vehicle(serverID: server.id, id: 1, name: nil, model: nil, trim: nil, totalDrives: nil, totalCharges: nil, totalUpdates: nil)
        environment.startStatusPolling(); XCTAssertTrue(environment.isStatusPolling)
        environment.stopStatusPolling(); XCTAssertFalse(environment.isStatusPolling)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([ServerProfileRecord.self, VehicleRecord.self, DriveRecord.self, ChargeRecord.self,
                             DetailCacheRecord.self, BatteryHealthRecord.self, FirmwareUpdateRecord.self,
                             GlobalSettingsRecord.self, SyncMetadataRecord.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }
    private func drivesFixture() throws -> DrivesDataDTO {
        let bundle = Bundle(for: Self.self)
        let url = (bundle.url(forResource: "drives", withExtension: "json", subdirectory: "Fixtures") ?? bundle.url(forResource: "drives", withExtension: "json"))!
        return try JSONDecoder.tessalytics.decode(Envelope<DrivesDataDTO>.self, from: Data(contentsOf: url)).data
    }
}

private struct RepositoryAPI: TeslaMateAPI {
    var drivesValue: DrivesDataDTO?
    var error: ClientError?
    init(drivesValue: DrivesDataDTO? = nil, error: ClientError? = nil) { self.drivesValue = drivesValue; self.error = error }
    func ping() async throws {}
    func cars() async throws -> CarsDataDTO { throw error ?? .notFound }
    func car(carID: Int) async throws -> CarsDataDTO { throw error ?? .notFound }
    func status(carID: Int) async throws -> StatusDataDTO { throw error ?? .notFound }
    func drives(carID: Int, page: Int, show: Int, filter: DateRangeFilter) async throws -> DrivesDataDTO { if let error { throw error }; return drivesValue! }
    func drive(carID: Int, driveID: Int) async throws -> DriveDataDTO { throw error ?? .notFound }
    func charges(carID: Int, page: Int, show: Int, filter: DateRangeFilter) async throws -> ChargesDataDTO { throw error ?? .notFound }
    func charge(carID: Int, chargeID: Int) async throws -> ChargeDataDTO { throw error ?? .notFound }
    func currentCharge(carID: Int) async throws -> ChargeDataDTO { throw error ?? .notFound }
    func batteryHealth(carID: Int) async throws -> BatteryHealthDataDTO { throw error ?? .notFound }
    func updates(carID: Int) async throws -> UpdatesDataDTO { throw error ?? .notFound }
    func globalSettings() async throws -> GlobalSettingsDataDTO { throw error ?? .notFound }
}

private struct TestCredentialStore: CredentialStore {
    func save(_ credentials: StoredCredentials, profileID: UUID) throws {}
    func credentials(profileID: UUID) throws -> StoredCredentials? { nil }
    func delete(profileID: UUID) throws {}
}
