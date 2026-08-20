import SwiftData
import SwiftUI

@main
struct TessalyticsApp: App {
    private let container: ModelContainer
    @State private var environment: AppEnvironment

    init() {
        let schema = Schema([
            ServerProfileRecord.self, VehicleRecord.self, DriveRecord.self,
            ChargeRecord.self, DetailCacheRecord.self, BatteryHealthRecord.self,
            FirmwareUpdateRecord.self, GlobalSettingsRecord.self, SyncMetadataRecord.self,
            TrackRecord.self
        ])
        let configuration = ModelConfiguration(
            "Tessalytics",
            schema: schema,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            self.container = container
            _environment = State(initialValue: AppEnvironment(container: container))
        } catch {
            fatalError("Unable to initialize protected local storage: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .task { await environment.start() }
        }
        .modelContainer(container)
    }
}
