import SwiftData
import SwiftUI

@main
struct TessalyticsApp: App {
    private let container: ModelContainer
    @State private var environment: AppEnvironment

    init() {
        // Before anything else, and before the app finishes launching: a
        // notification that fires while the app is in front is not shown at all
        // unless something has claimed the delegate. See NotificationPresenter.
        NotificationPresenter.install()

        let schema = Schema([
            ServerProfileRecord.self, VehicleRecord.self, DriveRecord.self,
            ChargeRecord.self, DetailCacheRecord.self, BatteryHealthRecord.self,
            FirmwareUpdateRecord.self, GlobalSettingsRecord.self, SyncMetadataRecord.self,
            TrackRecord.self
        ])
        // One local store, as before. Server profiles follow the owner's Apple
        // Account through `ServerProfileSync` and the credentials through iCloud
        // Keychain — neither needs this store to be mirrored, and mirroring it
        // would mean dropping the nine `@Attribute(.unique)` cache keys the
        // history dedupe is built on.
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
                // The chosen language, or the phone's when nothing was chosen.
                // Everything that resolves a string reads this, so a change here
                // redraws the whole interface in the new language at once.
                .environment(\.locale, environment.languageLocale ?? Locale.autoupdatingCurrent)
                .task { await environment.start() }
        }
        .modelContainer(container)
    }
}
