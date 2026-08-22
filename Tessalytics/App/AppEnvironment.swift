import Foundation
import Observation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class AppEnvironment {
    enum Phase: Equatable { case loading, onboarding, ready }
    enum OwnerConnectionState: Equatable { case disconnected, connecting, connected, failed }

    var phase: Phase = .loading
    var profiles: [ServerProfile] = []
    var selectedProfile: ServerProfile?
    var vehicles: [Vehicle] = []
    var selectedVehicle: Vehicle?
    var status: VehicleStatus?
    var statusUnits: UnitsDTO?
    var statusFetchedAt: Date?
    /// The last status seen while the car was awake, and when.
    ///
    /// A sleeping car reports nothing about locks, doors or cabin temperature.
    /// Answering "unknown" was honest but useless: the last known state is the
    /// thing an owner wants precisely when the car cannot be asked.
    var lastLiveStatus: VehicleStatus?
    var lastLiveStatusAt: Date?
    /// Readings from the event stream, for the charts shown while driving.
    var liveTelemetry = LiveTelemetryBuffer()
    /// The path of the drive in progress, as the server already has it.
    ///
    /// The in-memory buffer only knows what has arrived since the app opened, so a
    /// drive joined halfway through drew a single pin and no route. Fetched once
    /// per drive; the streamed positions extend it from there.
    private(set) var liveRoute: [CoordinateDTO] = []
    /// The line the live map actually draws, assembled from the two sources above.
    ///
    /// Stored rather than derived in the view. Rebuilding it on every render meant
    /// a redraw of anything on the home screen redrew the route, and the thinning
    /// it used picked a different set of points each time the buffer grew — so the
    /// line jumped on every reading instead of growing by one point. This changes
    /// only when the route does.
    private(set) var liveMapRoute = LiveRouteTrail()
    /// Whether the event stream is currently connected.
    var isStreamingLive = false
    /// Why the stream is not connected, when it isn't.
    var liveStreamMessage: String?
    var statusUsesOwnerAPI = false
    var isOffline = false
    var lastError: String?
    var ownerConnectionState: OwnerConnectionState = .disconnected
    var hasOwnerCredentials = false
    var ownerVehicles: [OwnerVehicle] = []
    var selectedOwnerVehicle: OwnerVehicle?
    var ownerLastError: String?
    var isOwnerCommandRunning = false
    private(set) var isDemoMode = false

    /// Fleet-wide totals derived from the complete cached history.
    private(set) var fleet = FleetStatistics()
    /// Totals reported by Tessalytics Backend, when connected to one. Preferred
    /// over the locally summed figures because the server sees the whole history
    /// whether or not this device has paged it.
    private(set) var serverTotals: BackendTotals?
    private(set) var isSyncingHistory = false
    /// Bumped whenever history is written, so views can recompute off it.
    private(set) var historyRevision = 0

    private let container: ModelContainer
    /// The store the app writes through. Exposed so a test can read back what a
    /// streamed reading was supposed to have cached.
    var modelContext: ModelContext { container.mainContext }
    private let keychain: any CredentialStore
    private let ownerAPI: OwnerAPISession
    private let userDefaults: UserDefaults
    private var statusTask: Task<Void, Never>?
    private var pollingTarget: PollingTarget?
    private var liveStreamTask: Task<Void, Never>?
    private var liveStreamTarget: PollingTarget?
    private var liveRouteTask: Task<Void, Never>?
    private var liveRouteKey: LiveRouteKey?
    private var liveRouteFetchedAt: Date?
    /// The last streamed reading written to the cache, and when.
    private var lastStreamedPersistAt: Date?
    private var unpersistedStreamedStatus: PendingStatusWrite?
    private var statusRefreshTask: Task<Void, Never>?
    private var statusRefreshID: UUID?
    private var historyTask: Task<Void, Never>?
    private var historyRefreshTask: Task<Void, Never>?

    /// Poll cadences.
    ///
    /// Live status is cheap — one request — so it runs often while the app is on
    /// screen. History is many requests and changes only when a drive or charge
    /// completes, so it runs far less often. Both stop when the app leaves the
    /// foreground; nothing polls in the background.
    enum Cadence {
        static let statusForeground: Duration = .seconds(30)
        static let history: Duration = .seconds(300)
        /// How often a streamed reading is written to the on-disk cache.
        ///
        /// Not every reading. The stream delivers two or three a second while
        /// driving, and each write is an encode plus a fetch plus a save on the
        /// main context — enough main-thread work to starve the very updates it is
        /// recording, so the app fell further behind the car the longer it drove.
        /// The cache exists so a cold launch has something to show, and for that a
        /// reading every few seconds is indistinguishable from all of them.
        static let streamedStatusPersist: TimeInterval = 5
        /// How often the drive in progress has its route re-read from the server.
        ///
        /// Fetching once per drive was not enough. The live readings were meant to
        /// extend it, so a quiet stream — or a server without one — left the route
        /// frozen where the app joined the drive while the pin carried on ahead of
        /// it, which reads as a broken or disconnected route. The server always has
        /// the whole path; asking again is one small request.
        static let liveRoute: TimeInterval = 90
    }

    /// Identifies the drive a fetched route belongs to.
    private struct LiveRouteKey: Equatable {
        let profileID: UUID
        let carID: Int
        let since: Date?
    }

    /// A streamed reading that has not been written to the cache yet.
    private struct PendingStatusWrite {
        let status: VehicleStatus
        let units: UnitsDTO?
        let profileID: UUID
        let carID: Int
        let fetchedAt: Date
    }

    /// Identifies which server/vehicle pair the status poller is currently bound to.
    private struct PollingTarget: Equatable {
        let profileID: UUID
        let carID: Int
    }
    var isStatusPolling: Bool { statusTask != nil }
    var isStatusRefreshing: Bool { statusRefreshTask != nil }
    var isOwnerConnected: Bool { ownerConnectionState == .connected }

    init(
        container: ModelContainer,
        keychain: any CredentialStore = KeychainCredentialStore(),
        ownerCredentialStore: any OwnerCredentialStore = KeychainOwnerCredentialStore(),
        ownerTransport: any HTTPTransport = URLSession.shared,
        userDefaults: UserDefaults = .standard
    ) {
        self.container = container
        self.keychain = keychain
        self.userDefaults = userDefaults
        ownerAPI = OwnerAPISession(store: ownerCredentialStore, transport: ownerTransport)
    }

    func start() async {
        if ProcessInfo.processInfo.arguments.contains("-ui-onboarding") {
            phase = .onboarding
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-demo") {
            activateDemo(
                showDirectControls: !ProcessInfo.processInfo.arguments.contains("-ui-owner-disconnected"),
                offline: ProcessInfo.processInfo.arguments.contains("-ui-demo-offline"),
                driving: ProcessInfo.processInfo.arguments.contains("-ui-demo-driving")
            )
            return
        }
        #if DEBUG
        // End-to-end test harness. Seeds a real server from the environment so
        // UI tests can drive the app against a live backend without a credential
        // ever being typed into a field or committed to the repository.
        if ProcessInfo.processInfo.arguments.contains("-ui-live-server") {
            await seedLiveServerFromEnvironment()
            return
        }
        #endif
        if userDefaults.bool(forKey: Self.demoModeKey) {
            activateDemo(showDirectControls: false)
            return
        }
        await startConfiguredSession()
    }

    #if DEBUG
    /// Configures a server from `TESSALYTICS_LIVE_URL` / `TESSALYTICS_LIVE_TOKEN`.
    ///
    /// DEBUG only, and only when `-ui-live-server` is passed. The values come from
    /// the launching environment, never from the bundle.
    private func seedLiveServerFromEnvironment() async {
        let environment = ProcessInfo.processInfo.environment
        guard let rawURL = environment["TESSALYTICS_LIVE_URL"],
              let token = environment["TESSALYTICS_LIVE_TOKEN"],
              !token.isEmpty,
              URL(string: rawURL) != nil else {
            lastError = "Set TESSALYTICS_LIVE_URL and TESSALYTICS_LIVE_TOKEN to use -ui-live-server."
            phase = .onboarding
            return
        }

        // Start from nothing, so a run never inherits a previous one's cache.
        await eraseEverything()

        var draft = ProfileDraft()
        draft.name = "Live"
        draft.serverURL = rawURL
        draft.authenticationMethod = .bearer
        draft.token = token
        draft.allowsLocalHTTP = true

        do {
            let probe = try await ServerProbe.test(
                baseURL: try draft.profile().baseURL,
                authentication: .bearer(token)
            )
            try await saveProfile(draft)
            await refreshHistory()
        } catch {
            lastError = error.localizedDescription
            phase = .onboarding
        }
    }
    #endif

    func enterDemoMode() {
        userDefaults.set(true, forKey: Self.demoModeKey)
        activateDemo(showDirectControls: false)
    }

    func leaveDemoMode() async {
        userDefaults.set(false, forKey: Self.demoModeKey)
        resetSessionState()
        await startConfiguredSession()
    }

    private func startConfiguredSession() async {
        let context = container.mainContext
        let descriptor = FetchDescriptor<ServerProfileRecord>(sortBy: [SortDescriptor(\.name)])
        let records = (try? context.fetch(descriptor)) ?? []
        profiles = records.compactMap(\.profile)
        selectedProfile = profiles.first(where: \.isSelected) ?? profiles.first
        guard let selectedProfile else {
            phase = .onboarding
            return
        }

        vehicles = cachedVehicles(serverID: selectedProfile.id)
        selectedVehicle = vehicles.first
        if let selectedVehicle {
            restoreCachedStatus(profile: selectedProfile, vehicle: selectedVehicle)
        }
        phase = .ready

        startStatusPolling()
        recomputeFleetStatistics()
        Task { [weak self] in await self?.restoreOwnerConnection() }
        await refreshVehicles(profile: selectedProfile)
        if let selectedVehicle, status == nil {
            restoreCachedStatus(profile: selectedProfile, vehicle: selectedVehicle)
        }
        startHistoryPolling()
    }

    private func activateDemo(showDirectControls: Bool, offline: Bool = false, driving: Bool = false) {
        stopStatusPolling()
        stopHistoryPolling()
        stopLiveStream()
        liveRoute = []
        clearLiveMapRoute()
        isDemoMode = true
        isOffline = false
        lastError = nil
        let profile = DemoExperience.profile
        let vehicle = DemoExperience.vehicle
        DemoExperience.seed(in: container.mainContext, offline: offline)
        profiles = [profile]
        selectedProfile = profile
        vehicles = [vehicle]
        selectedVehicle = vehicle
        if driving {
            status = DemoExperience.drivingStatus()
            liveTelemetry = DemoExperience.drivingTelemetry()
            updateLiveMapRoute()
            isStreamingLive = true
        } else {
            status = offline ? DemoExperience.offlineStatus() : DemoExperience.status()
            liveTelemetry.reset()
            isStreamingLive = false
        }
        statusUnits = DemoExperience.units
        statusFetchedAt = .now
        ownerVehicles = []
        selectedOwnerVehicle = nil
        ownerConnectionState = .disconnected
        hasOwnerCredentials = false
        statusUsesOwnerAPI = false
        if showDirectControls {
            let ownerVehicle = OwnerVehicle(
                id: 987_654_321,
                vehicleId: 123_456_789,
                vin: "DEMO0000000000001",
                displayName: "Aurora",
                state: "online"
            )
            ownerVehicles = [ownerVehicle]
            selectedOwnerVehicle = ownerVehicle
            ownerConnectionState = .connected
            hasOwnerCredentials = true
            statusUsesOwnerAPI = true
        }
        phase = .ready
        // Demo data is seeded synchronously above, so the totals can be derived
        // from it immediately — nothing polls in demo mode.
        recomputeFleetStatistics(profile: profile, vehicle: vehicle)
    }

    private func resetSessionState() {
        stopStatusPolling()
        stopHistoryPolling()
        stopLiveStream()
        liveRoute = []
        clearLiveMapRoute()
        liveTelemetry.reset()
        historyRefreshTask = nil
        fleet = FleetStatistics()
        statusRefreshTask?.cancel()
        statusRefreshTask = nil
        statusRefreshID = nil
        isDemoMode = false
        serverTotals = nil
        profiles = []
        selectedProfile = nil
        vehicles = []
        selectedVehicle = nil
        status = nil
        statusUnits = nil
        statusFetchedAt = nil
        statusUsesOwnerAPI = false
        isOffline = false
        lastError = nil
        ownerVehicles = []
        selectedOwnerVehicle = nil
        ownerConnectionState = .disconnected
        hasOwnerCredentials = false
        phase = .loading
    }

    // MARK: - Removing a server, and starting over

    /// Deletes one server: its credentials, and every row synchronized from it.
    ///
    /// The Keychain entry goes first. If the store write fails the profile stays,
    /// which is the safer failure — an orphaned credential is worse than a
    /// profile that would not delete, because nothing in the UI would ever offer
    /// to remove it again.
    func deleteProfile(_ profile: ServerProfile) async throws {
        let wasSelected = selectedProfile?.id == profile.id
        if wasSelected {
            stopStatusPolling()
            stopHistoryPolling()
            historyRefreshTask = nil
        }

        try keychain.delete(profileID: profile.id)
        purgeRecords(serverID: profile.id)

        let context = container.mainContext
        let identifier = profile.id
        let descriptor = FetchDescriptor<ServerProfileRecord>(predicate: #Predicate { $0.id == identifier })
        for record in (try? context.fetch(descriptor)) ?? [] { context.delete(record) }
        try context.save()

        profiles = ((try? context.fetch(FetchDescriptor<ServerProfileRecord>())) ?? []).compactMap(\.profile)

        guard wasSelected else { return }

        // Promote whatever is left, or fall back to onboarding. Selecting the
        // replacement through the normal path means its cache and pollers are
        // set up exactly as they would be on a cold launch.
        vehicles = []
        selectedVehicle = nil
        status = nil
        statusUnits = nil
        statusFetchedAt = nil
        fleet = FleetStatistics()

        if let next = profiles.first {
            let record = try? context.fetch(FetchDescriptor<ServerProfileRecord>()).first { $0.id == next.id }
            record?.isSelected = true
            try? context.save()
            await selectProfile(next)
        } else {
            selectedProfile = nil
            phase = .onboarding
        }
    }

    /// Removes every server, every synchronized row, and all stored credentials.
    ///
    /// Used by "start over" in Settings. Deliberately thorough: someone reaching
    /// for this wants the app to look like a fresh install, and a leftover token
    /// or a stale odometer would undermine that.
    func eraseEverything() async {
        stopStatusPolling()
        stopHistoryPolling()
        historyRefreshTask = nil
        statusRefreshTask?.cancel()
        statusRefreshTask = nil
        statusRefreshID = nil

        // Owner API tokens live in their own Keychain entries, so the disconnect
        // has to run before the profiles that reference them are gone.
        if hasOwnerCredentials || isOwnerConnected {
            try? await ownerAPI.disconnect()
        }

        let context = container.mainContext
        let records = (try? context.fetch(FetchDescriptor<ServerProfileRecord>())) ?? []
        for record in records {
            if let profile = record.profile { try? keychain.delete(profileID: profile.id) }
            context.delete(record)
        }
        purgeAllRecords()
        try? context.save()

        userDefaults.set(false, forKey: Self.demoModeKey)
        resetSessionState()
        phase = .onboarding
    }

    /// Everything synchronized from one server.
    private func purgeRecords(serverID: UUID) {
        let context = container.mainContext
        let identifier = serverID.uuidString
        delete(FetchDescriptor<DriveRecord>(predicate: #Predicate { $0.serverID == identifier }), in: context)
        delete(FetchDescriptor<ChargeRecord>(predicate: #Predicate { $0.serverID == identifier }), in: context)
        delete(FetchDescriptor<DetailCacheRecord>(predicate: #Predicate { $0.serverID == identifier }), in: context)
        delete(FetchDescriptor<BatteryHealthRecord>(predicate: #Predicate { $0.serverID == identifier }), in: context)
        delete(FetchDescriptor<FirmwareUpdateRecord>(predicate: #Predicate { $0.serverID == identifier }), in: context)
        delete(FetchDescriptor<VehicleRecord>(predicate: #Predicate { $0.serverID == identifier }), in: context)
        delete(FetchDescriptor<GlobalSettingsRecord>(predicate: #Predicate { $0.serverID == identifier }), in: context)
        // Sync metadata is keyed by a composite string rather than a serverID
        // column, so it is filtered in memory.
        let metadata = (try? context.fetch(FetchDescriptor<SyncMetadataRecord>())) ?? []
        for record in metadata where record.cacheKey.hasPrefix(identifier) { context.delete(record) }
        try? context.save()
    }

    private func purgeAllRecords() {
        let context = container.mainContext
        delete(FetchDescriptor<DriveRecord>(), in: context)
        delete(FetchDescriptor<ChargeRecord>(), in: context)
        delete(FetchDescriptor<DetailCacheRecord>(), in: context)
        delete(FetchDescriptor<BatteryHealthRecord>(), in: context)
        delete(FetchDescriptor<FirmwareUpdateRecord>(), in: context)
        delete(FetchDescriptor<VehicleRecord>(), in: context)
        delete(FetchDescriptor<GlobalSettingsRecord>(), in: context)
        delete(FetchDescriptor<SyncMetadataRecord>(), in: context)
        try? context.save()
    }

    private func delete<T: PersistentModel>(_ descriptor: FetchDescriptor<T>, in context: ModelContext) {
        for record in (try? context.fetch(descriptor)) ?? [] { context.delete(record) }
    }

    /// Drops the synchronized history for the selected server, keeping the
    /// server itself. The next refresh re-syncs from scratch.
    func resyncFromScratch() async {
        guard let profile = selectedProfile else { return }
        stopHistoryPolling()
        historyRefreshTask = nil
        purgeRecords(serverID: profile.id)
        fleet = FleetStatistics()
        historyRevision += 1
        await refreshVehicles(profile: profile)
        startHistoryPolling()
    }

    /// The client for a server.
    ///
    /// Returned behind `VehicleDataAPI` so repositories and views stay testable
    /// against a stub, not because a second implementation is expected.
    func client(for profile: ServerProfile) throws -> any VehicleDataAPI {
        try backendClient(for: profile)
    }

    /// The concrete client, for the endpoints that sit outside the shared
    /// protocol — lifetime totals and the aggregated track.
    func backendClient(for profile: ServerProfile) throws -> TessalyticsBackendClient {
        let credentials = try keychain.credentials(profileID: profile.id)
        return TessalyticsBackendClient(
            baseURL: profile.baseURL,
            authentication: credentials?.authentication ?? .none
        )
    }

    func saveProfile(_ draft: ProfileDraft) async throws {
        let profile = try draft.profile()
        if let credentials = draft.credentials { try keychain.save(credentials, profileID: profile.id) }
        userDefaults.set(false, forKey: Self.demoModeKey)
        isDemoMode = false
        ownerVehicles = []
        selectedOwnerVehicle = nil
        ownerConnectionState = .disconnected
        hasOwnerCredentials = false
        statusUsesOwnerAPI = false
        let context = container.mainContext
        let existing = try context.fetch(FetchDescriptor<ServerProfileRecord>())
        existing.forEach { $0.isSelected = false }
        context.insert(ServerProfileRecord(profile: profile, isSelected: true))
        try context.save()
        profiles = (try context.fetch(FetchDescriptor<ServerProfileRecord>())).compactMap(\.profile)
        selectedProfile = profile
        phase = .ready
        // Fetch the vehicle list, then let refreshVehicles start the status poller.
        // Without this the dashboard sat on "Status not available yet" until the
        // user changed vehicle or backgrounded the app.
        await refreshVehicles(profile: profile)
        startHistoryPolling()
        Task { [weak self] in await self?.restoreOwnerConnection() }
    }

    /// Renames a server without touching its credentials or synchronized data.
    ///
    /// The name is only a label, so this deliberately does not re-verify the
    /// connection or re-sync: a typo in "Home" should not cost 800 drives.
    func renameProfile(_ profile: ServerProfile, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ClientError.invalidConfiguration }
        let id = profile.id
        let context = container.mainContext
        var descriptor = FetchDescriptor<ServerProfileRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else { return }
        record.name = trimmed
        try context.save()
        profiles = (try context.fetch(FetchDescriptor<ServerProfileRecord>())).compactMap(\.profile)
        if selectedProfile?.id == id {
            selectedProfile = profiles.first { $0.id == id }
        }
    }

    func refreshVehicles(profile: ServerProfile? = nil) async {
        guard let profile = profile ?? selectedProfile else { return }
        let previouslySelectedID = selectedVehicle?.id
        if vehicles.isEmpty {
            vehicles = cachedVehicles(serverID: profile.id)
            selectedVehicle = vehicles.first(where: { $0.id == previouslySelectedID }) ?? vehicles.first
            if let selectedVehicle { restoreCachedStatus(profile: profile, vehicle: selectedVehicle) }
        }
        do {
            let response = try await client(for: profile).cars()
            vehicles = response.cars.map { $0.vehicle(serverID: profile.id) }
            selectedVehicle = vehicles.first(where: { $0.id == previouslySelectedID }) ?? vehicles.first
            isOffline = false
            persistVehicles(vehicles)
            if let settings = try? await client(for: profile).globalSettings() {
                persistSettings(settings, serverID: profile.id)
            }
        } catch {
            isOffline = true
            lastError = error.userFacingMessage
            vehicles = cachedVehicles(serverID: profile.id)
            selectedVehicle = vehicles.first(where: { $0.id == previouslySelectedID }) ?? vehicles.first
        }
        // A vehicle may have appeared, or a different one may now be selected, so
        // make sure the status poller is running against the current selection.
        startStatusPolling()
        // And the stream, which is what makes the numbers move. It used to start
        // only on a foreground transition, so the first run after a server was
        // saved — and every vehicle switch — fell back to the thirty-second poll
        // with no sign that anything was wrong.
        startLiveStream()
    }

    func selectProfile(_ profile: ServerProfile) async {
        stopStatusPolling()
        stopLiveStream()
        selectedProfile = profile
        vehicles = []
        selectedVehicle = nil
        await refreshVehicles(profile: profile)
    }

    func selectVehicle(_ vehicle: Vehicle) {
        stopStatusPolling()
        statusRefreshTask?.cancel()
        statusRefreshTask = nil
        statusRefreshID = nil
        selectedVehicle = vehicle
        if let profile = selectedProfile { restoreCachedStatus(profile: profile, vehicle: vehicle) }
        else { status = nil; statusUnits = nil; statusFetchedAt = nil }
        if isOwnerConnected { selectedOwnerVehicle = matchingOwnerVehicle() ?? selectedOwnerVehicle }
        stopHistoryPolling()
        liveRoute = []
        clearLiveMapRoute()
        recomputeFleetStatistics()
        startStatusPolling()
        startHistoryPolling()
        startLiveStream()
    }

    /// Called whenever the app becomes active, and on first appearance.
    ///
    /// The app used to rely on the 60-second poll timer and a manual pull to
    /// refresh, so opening it showed whatever was in the cache — including a
    /// "latest drive" that was not the latest. Opening the app now always asks
    /// the server.
    func handleForegroundEntry() {
        guard !isDemoMode else { return }
        startStatusPolling()
        startHistoryPolling()
        startLiveStream()
        requestStatusRefresh()
    }

    func handleBackgroundEntry() {
        stopStatusPolling()
        stopHistoryPolling()
        // The stream is the expensive one: it holds a connection open and wakes on
        // every published reading. Nothing is on screen to show it.
        stopLiveStream()
    }

    /// Opens the event stream for the selected vehicle.
    ///
    /// Runs whenever the app is in the foreground rather than only while driving:
    /// the point of the stream is that the transition into driving arrives without
    /// waiting for a poll, and a parked car publishes almost nothing, so an idle
    /// stream costs a held connection and no traffic.
    func startLiveStream() {
        guard !isDemoMode, let profile = selectedProfile, let vehicle = selectedVehicle else { return }
        let target = PollingTarget(profileID: profile.id, carID: vehicle.id)
        if liveStreamTask != nil, liveStreamTarget == target { return }
        stopLiveStream()
        guard let client = try? backendClient(for: profile) else { return }

        liveStreamTarget = target
        let stream = LiveStateStream(baseURL: profile.baseURL, authentication: client.authentication)
        liveStreamTask = Task { [weak self] in
            for await event in stream.events(carID: vehicle.id) {
                guard let self, !Task.isCancelled else { return }
                switch event {
                case .connected:
                    isStreamingLive = true
                    liveStreamMessage = nil
                    // Whatever happened while the stream was down is on the server
                    // but not in the buffer, so the route is fetched again rather
                    // than left with a gap where the outage was.
                    liveRouteKey = nil
                case .interrupted(let message):
                    isStreamingLive = false
                    liveStreamMessage = message
                case .state(let payload):
                    // A reading is itself proof the stream is alive: the buffer
                    // keeps only the newest events, so a `connected` that was
                    // dropped to make room must not leave the badge saying
                    // reconnecting during a working drive.
                    isStreamingLive = true
                    liveStreamMessage = nil
                    apply(streamed: payload, profile: profile, vehicle: vehicle)
                }
            }
            self?.isStreamingLive = false
        }
    }

    func stopLiveStream() {
        liveStreamTask?.cancel()
        liveStreamTask = nil
        liveStreamTarget = nil
        isStreamingLive = false
        liveRouteTask?.cancel()
        liveRouteTask = nil
        liveRouteKey = nil
        // The throttle above means the newest reading is usually still only in
        // memory. Write it now, or closing the app loses the freshest thing it saw.
        flushStreamedStatus()
    }

    /// Records a reading in the live buffer the charts and the route draw from.
    ///
    /// Called from both the stream and the poll. It used to be the stream only,
    /// so a stream that was quiet — or a server without one — left the live charts
    /// empty and the route frozen at wherever it was when the app opened, with the
    /// pin moving on ahead of it. A reading every thirty seconds is a poor route,
    /// but it is a route.
    private func recordLive(_ status: VehicleStatus) {
        guard status.isDriving else {
            if !liveTelemetry.samples.isEmpty {
                // The journey is over; the next one starts from empty rather than
                // continuing a chart across a stop.
                liveTelemetry.reset()
            }
            clearLiveMapRoute()
            return
        }
        liveTelemetry.append(
            speed: status.liveSpeed,
            power: status.livePower,
            level: status.batteryDetails?.batteryLevel.map(Double.init),
            odometer: status.odometer,
            latitude: status.carGeodata?.location?.latitude,
            longitude: status.carGeodata?.location?.longitude,
            elevation: status.drivingDetails?.elevation
        )
        updateLiveMapRoute()
    }

    /// Rebuilds the drawn route, and writes it back only when it changed.
    ///
    /// The write is what matters. Observation notifies on assignment, not on
    /// difference, so assigning an identical route on every reading would invite
    /// exactly the redraw this exists to avoid.
    private func updateLiveMapRoute() {
        var next = liveMapRoute
        next.update(seed: liveRoute, live: liveTelemetry.routePath)
        if next != liveMapRoute { liveMapRoute = next }
    }

    private func clearLiveMapRoute() {
        guard !liveMapRoute.isEmpty else { return }
        var next = liveMapRoute
        next.reset()
        liveMapRoute = next
    }

    /// Folds a streamed reading into the same state the poller writes.
    ///
    /// Kept on one path deliberately: a second way for status to arrive is a
    /// second set of rules about what counts as fresh.
    private func apply(streamed payload: StatusDataDTO, profile: ServerProfile, vehicle: Vehicle) {
        guard selectedProfile?.id == profile.id, selectedVehicle?.id == vehicle.id else { return }
        let previousState = status?.state
        status = payload.status
        statusUnits = payload.units ?? statusUnits
        statusFetchedAt = .now
        statusUsesOwnerAPI = false
        isOffline = false

        if payload.status.reportsLiveTelemetry {
            lastLiveStatus = payload.status
            lastLiveStatusAt = statusFetchedAt
        }

        recordLive(payload.status)
        refreshLiveRoute(profile: profile, vehicle: vehicle, status: payload.status)

        // A change of state is the one reading worth writing immediately: it is
        // what a cold launch reads back, and "driving" turning into "parked" is
        // not something to leave sitting in memory for the throttle.
        persistStreamed(
            status: payload.status,
            units: payload.units,
            profile: profile,
            vehicle: vehicle,
            immediately: previousState != payload.status.state
        )
    }

    /// Writes a streamed reading to the cache, at most every few seconds.
    private func persistStreamed(
        status: VehicleStatus,
        units: UnitsDTO?,
        profile: ServerProfile,
        vehicle: Vehicle,
        immediately: Bool
    ) {
        let fetchedAt = statusFetchedAt ?? .now
        let pending = PendingStatusWrite(
            status: status,
            units: units,
            profileID: profile.id,
            carID: vehicle.id,
            fetchedAt: fetchedAt
        )
        if !immediately, let last = lastStreamedPersistAt,
           fetchedAt.timeIntervalSince(last) < Cadence.streamedStatusPersist {
            unpersistedStreamedStatus = pending
            return
        }
        writeStatusCache(pending)
    }

    /// Writes whatever the throttle is still holding, if anything.
    private func flushStreamedStatus() {
        guard let pending = unpersistedStreamedStatus else { return }
        writeStatusCache(pending)
    }

    private func writeStatusCache(_ pending: PendingStatusWrite) {
        unpersistedStreamedStatus = nil
        lastStreamedPersistAt = pending.fetchedAt
        VehicleStatusCache(context: container.mainContext).save(
            status: pending.status,
            units: pending.units,
            serverID: pending.profileID,
            carID: pending.carID,
            fetchedAt: pending.fetchedAt
        )
    }

    /// Fetches the path of the drive in progress, once per drive.
    ///
    /// The map draws this behind the live samples so the route is whole from the
    /// moment the app opens, rather than starting at whatever the phone happened
    /// to be awake for.
    private func refreshLiveRoute(profile: ServerProfile, vehicle: Vehicle, status: VehicleStatus) {
        guard status.isDriving else {
            liveRouteTask?.cancel()
            liveRouteTask = nil
            liveRouteKey = nil
            liveRouteFetchedAt = nil
            if !liveRoute.isEmpty { liveRoute = [] }
            clearLiveMapRoute()
            return
        }
        let key = LiveRouteKey(profileID: profile.id, carID: vehicle.id, since: status.stateSince?.value)
        // Called on every reading, so the common case has to be these two
        // comparisons and nothing else.
        let isNewDrive = key != liveRouteKey
        let isStale = liveRouteFetchedAt.map { Date.now.timeIntervalSince($0) >= Cadence.liveRoute } ?? true
        guard isNewDrive || isStale else { return }
        // A running fetch is left alone when it is only the age that has expired:
        // cancelling it would restart the same request every reading.
        if !isNewDrive, liveRouteTask != nil { return }
        liveRouteKey = key
        liveRouteFetchedAt = .now
        liveRouteTask?.cancel()
        liveRouteTask = Task { [weak self] in
            guard let self, let client = try? backendClient(for: profile) else { return }
            // Without a state timestamp, assume no drive has been running longer
            // than a couple of hours; the server segments per drive and only the
            // last segment is used, so an over-wide window costs bytes, not
            // correctness.
            let start = key.since ?? Date.now.addingTimeInterval(-2 * 3_600)
            let segments = try? await client.track(
                carID: vehicle.id,
                every: 5,
                maxPoints: 2_000,
                filter: DateRangeFilter(start: start),
                minimumSegmentPoints: 2
            )
            guard !Task.isCancelled, liveRouteKey == key,
                  selectedProfile?.id == profile.id, selectedVehicle?.id == vehicle.id else { return }
            // Segments are one per drive, oldest first: the drive in progress is
            // the last of them. A failed fetch leaves the previous route in place
            // rather than blanking the map.
            if let latest = segments?.last, !latest.isEmpty {
                liveRoute = latest
                updateLiveMapRoute()
            }
            liveRouteFetchedAt = .now
            liveRouteTask = nil
        }
    }

    func startStatusPolling() {
        guard !isDemoMode, let profile = selectedProfile, let vehicle = selectedVehicle else { return }
        let target = PollingTarget(profileID: profile.id, carID: vehicle.id)
        // Already polling this exact vehicle: leave the running task alone.
        if statusTask != nil, pollingTarget == target { return }
        // Otherwise the selection changed (or a vehicle only just became known,
        // as happens right after a server is saved) and the poller must retarget.
        stopStatusPolling()
        pollingTarget = target
        statusTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshStatus(profile: profile, vehicle: vehicle)
                do { try await Task.sleep(for: Cadence.statusForeground) } catch { return }
            }
        }
    }

    func stopStatusPolling() {
        statusTask?.cancel()
        statusTask = nil
        pollingTarget = nil
    }

    func startHistoryPolling() {
        guard !isDemoMode, historyTask == nil, selectedProfile != nil, selectedVehicle != nil else { return }
        historyTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshHistory()
                do { try await Task.sleep(for: Cadence.history) } catch { return }
            }
        }
    }

    func stopHistoryPolling() {
        historyTask?.cancel()
        historyTask = nil
    }

    /// Syncs drive and charge history and recomputes the fleet totals.
    ///
    /// The first run for a vehicle pages the entire history so the totals are
    /// exact; later runs pull only the newest page.
    func refreshHistory() async {
        guard !isDemoMode, let profile = selectedProfile, let vehicle = selectedVehicle else { return }
        // Coalesce: a pull-to-refresh landing on top of the timer should join the
        // running sync rather than starting a second one.
        if let historyRefreshTask {
            await historyRefreshTask.value
            return
        }
        let task = Task { [weak self] () -> Void in
            await self?.performHistorySync(profile: profile, vehicle: vehicle)
        }
        historyRefreshTask = task
        await task.value
        historyRefreshTask = nil
    }

    private func performHistorySync(profile: ServerProfile, vehicle: Vehicle) async {
        let sync = FleetHistorySync(context: container.mainContext)
        let mode = sync.mode(serverID: profile.id, carID: vehicle.id)
        isSyncingHistory = true
        defer { isSyncingHistory = false }

        do {
            let client = try client(for: profile)
            _ = try await sync.run(client: client, serverID: profile.id, carID: vehicle.id, mode: mode)
            await refreshBatteryHealth(profile: profile, vehicle: vehicle, client: client)
            // Tessalytics Backend computes lifetime totals in one query. Taking
            // them from the server is both faster and exact: the local sums are
            // only as complete as whatever history has been paged so far.
            serverTotals = try? await backendClient(for: profile).totals(carID: vehicle.id)
            await refreshTrack(profile: profile, vehicle: vehicle)
            isOffline = false
        } catch {
            if error is CancellationError { return }
            isOffline = true
            lastError = error.userFacingMessage
        }
        // Recompute from whatever landed, so a partial sync still improves things.
        recomputeFleetStatistics(profile: profile, vehicle: vehicle)
        historyRevision += 1
    }

    private func refreshBatteryHealth(profile: ServerProfile, vehicle: Vehicle, client: any VehicleDataAPI) async {
        guard let dto = try? await client.batteryHealth(carID: vehicle.id).batteryHealth else { return }
        let context = container.mainContext
        let record = BatteryHealthRecord(serverID: profile.id, carID: vehicle.id, dto: dto)
        let key = record.cacheKey
        let descriptor = FetchDescriptor<BatteryHealthRecord>(predicate: #Predicate { $0.cacheKey == key })
        // The key is day-based, so overwrite today's observation rather than
        // inserting a duplicate against a unique constraint.
        if let existing = try? context.fetch(descriptor).first {
            existing.maxRange = dto.maxRange
            existing.currentRange = dto.currentRange
            existing.maxCapacity = dto.maxCapacity
            existing.currentCapacity = dto.currentCapacity
            existing.healthPercent = dto.batteryHealthPercentage
            existing.ratedEfficiency = dto.ratedEfficiency
            existing.observedAt = .now
        } else {
            context.insert(record)
        }
        try? context.save()
    }

    func recomputeFleetStatistics(profile: ServerProfile? = nil, vehicle: Vehicle? = nil) {
        guard let profile = profile ?? selectedProfile, let vehicle = vehicle ?? selectedVehicle else {
            fleet = FleetStatistics()
            return
        }
        let context = container.mainContext
        let sync = FleetHistorySync(context: context)
        let lastFullSync = sync.lastFullSync(serverID: profile.id, carID: vehicle.id)
        var computed = FleetStatisticsBuilder.build(
            drives: DriveRepository(context: context).cached(serverID: profile.id, carID: vehicle.id),
            charges: ChargeRepository(context: context).cached(serverID: profile.id, carID: vehicle.id),
            batteryHealth: latestBatteryHealth(serverID: profile.id, carID: vehicle.id),
            odometer: status?.odometer,
            lastFullSync: lastFullSync,
            isComplete: lastFullSync != nil,
            specification: specification(serverID: profile.id, carID: vehicle.id)
        )
        if let serverTotals { computed.applyServerTotals(serverTotals) }
        fleet = computed
    }

    /// Fetches the driven path, but only when there is something new to draw.
    ///
    /// The server does the aggregation, so this is one request for the whole
    /// history — but it is still hundreds of kilobytes, and redrawing an
    /// unchanged path on every sync would be pure waste.
    private func refreshTrack(profile: ServerProfile, vehicle: Vehicle) async {
        guard let client = try? backendClient(for: profile) else { return }
        let context = container.mainContext
        let key = TrackRecord.key(serverID: profile.id, carID: vehicle.id)
        var descriptor = FetchDescriptor<TrackRecord>(predicate: #Predicate { $0.cacheKey == key })
        descriptor.fetchLimit = 1
        let existing = try? context.fetch(descriptor).first

        let newestDrive = DriveRepository(context: context)
            .cached(serverID: profile.id, carID: vehicle.id)
            .compactMap(\.startDate)
            .max()
        if let existing, let newestDrive, let covered = existing.coversUntil, covered >= newestDrive {
            return
        }

        guard let segments = try? await client.track(carID: vehicle.id), !segments.isEmpty else { return }
        if let existing {
            existing.update(segments: segments, coversUntil: newestDrive)
        } else {
            context.insert(TrackRecord(serverID: profile.id, carID: vehicle.id, segments: segments, coversUntil: newestDrive))
        }
        try? context.save()
        historyRevision += 1
    }

    /// The owner's own figures for the selected car, if they supplied any.
    func specification(serverID: UUID, carID: Int) -> VehicleSpecification {
        guard let record = vehicleRecord(serverID: serverID, carID: carID) else { return .empty }
        return VehicleSpecification.sanitised(
            capacityNew: record.capacityNewOverride,
            maxRangeNew: record.maxRangeNewOverride
        )
    }

    var selectedSpecification: VehicleSpecification {
        guard let profile = selectedProfile, let vehicle = selectedVehicle else { return .empty }
        return specification(serverID: profile.id, carID: vehicle.id)
    }

    /// Stores the owner's figures and recomputes everything derived from them.
    ///
    /// Passing nil for a field clears it, which is how the derived value is
    /// restored — there is no separate reset path to keep in step.
    func saveSpecification(_ specification: VehicleSpecification) {
        guard let profile = selectedProfile, let vehicle = selectedVehicle,
              let record = vehicleRecord(serverID: profile.id, carID: vehicle.id) else { return }
        let clean = VehicleSpecification.sanitised(
            capacityNew: specification.capacityNew,
            maxRangeNew: specification.maxRangeNew
        )
        record.capacityNewOverride = clean.capacityNew
        record.maxRangeNewOverride = clean.maxRangeNew
        try? container.mainContext.save()
        recomputeFleetStatistics(profile: profile, vehicle: vehicle)
        historyRevision += 1
    }

    private func vehicleRecord(serverID: UUID, carID: Int) -> VehicleRecord? {
        let key = VehicleRecord.key(serverID: serverID, carID: carID)
        var descriptor = FetchDescriptor<VehicleRecord>(predicate: #Predicate { $0.cacheKey == key })
        descriptor.fetchLimit = 1
        return try? container.mainContext.fetch(descriptor).first
    }

    func latestBatteryHealth(serverID: UUID, carID: Int) -> BatteryHealthRecord? {
        let server = serverID.uuidString
        var descriptor = FetchDescriptor<BatteryHealthRecord>(
            predicate: #Predicate { $0.serverID == server && $0.carID == carID },
            sortBy: [SortDescriptor(\.observedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? container.mainContext.fetch(descriptor).first
    }

    func refreshStatus(profile: ServerProfile? = nil, vehicle: Vehicle? = nil) async {
        guard !isDemoMode else { return }
        guard let profile = profile ?? selectedProfile, let vehicle = vehicle ?? selectedVehicle else { return }
        if let statusRefreshTask {
            await statusRefreshTask.value
            return
        }
        let task = Task { [weak self] () -> Void in
            guard let self else { return }
            await self.performStatusRefresh(profile: profile, vehicle: vehicle)
        }
        let refreshID = UUID()
        statusRefreshID = refreshID
        statusRefreshTask = task
        await task.value
        if statusRefreshID == refreshID {
            statusRefreshTask = nil
            statusRefreshID = nil
        }
    }

    func requestStatusRefresh() {
        Task { [weak self] in await self?.refreshStatus() }
    }

    private func performStatusRefresh(profile: ServerProfile, vehicle: Vehicle) async {
        var notificationStatus: VehicleStatus?
        do {
            let response = try await client(for: profile).status(carID: vehicle.id)
            guard selectedProfile?.id == profile.id, selectedVehicle?.id == vehicle.id else { return }
            status = response.status
            statusUnits = response.units
            statusFetchedAt = .now
            statusUsesOwnerAPI = false
            isOffline = false
            notificationStatus = response.status
            // The odometer feeds the logged-versus-actual distance figures.
            recomputeFleetStatistics(profile: profile, vehicle: vehicle)
            // Also from here, not only from the stream: a server without an event
            // stream still has the route of the drive in progress, and the map
            // should show it there too.
            recordLive(response.status)
            refreshLiveRoute(profile: profile, vehicle: vehicle, status: response.status)
            VehicleStatusCache(context: container.mainContext).save(
                status: response.status,
                units: response.units,
                serverID: profile.id,
                carID: vehicle.id,
                fetchedAt: statusFetchedAt ?? .now
            )
            if response.status.reportsLiveTelemetry {
                lastLiveStatus = response.status
                lastLiveStatusAt = statusFetchedAt ?? .now
            }
        } catch {
            if error is CancellationError { return }
            isOffline = true
            lastError = error.userFacingMessage
        }

        // Direct live state remains useful when the separate TeslaMate history server is offline.
        if isOwnerConnected {
            await refreshOwnerStatus()
            if statusUsesOwnerAPI { notificationStatus = status }
        }

        let preferences = IntelligenceNotificationPreferences.stored()
        if preferences.enabled, let notificationStatus {
            await IntelligenceNotificationService.shared.updateStatusNotifications(
                status: notificationStatus,
                vehicleName: vehicle.name ?? "Your Tesla",
                preferences: preferences
            )
        }
    }

    func connectOwnerAPI(accessToken: String, refreshToken: String, region: OwnerAPIRegion) async throws {
        ownerConnectionState = .connecting
        hasOwnerCredentials = !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ownerLastError = nil
        do {
            ownerVehicles = try await ownerAPI.configure(accessToken: accessToken, refreshToken: refreshToken, region: region)
            selectedOwnerVehicle = matchingOwnerVehicle() ?? ownerVehicles.first
            ownerConnectionState = .connected
            await refreshOwnerStatus()
        } catch {
            hasOwnerCredentials = await ownerAPI.isConfigured()
            ownerConnectionState = .failed
            ownerLastError = error.localizedDescription
            throw error
        }
    }

    func disconnectOwnerAPI() async {
        do { try await ownerAPI.disconnect() }
        catch { ownerLastError = error.localizedDescription }
        ownerVehicles = []
        selectedOwnerVehicle = nil
        ownerConnectionState = .disconnected
        hasOwnerCredentials = false
        statusUsesOwnerAPI = false
        await refreshStatus()
    }

    func refreshOwnerVehicles() async {
        guard !isDemoMode, isOwnerConnected else { return }
        do {
            ownerVehicles = try await ownerAPI.vehicles()
            if selectedOwnerVehicle == nil || !ownerVehicles.contains(where: { $0.id == selectedOwnerVehicle?.id }) {
                selectedOwnerVehicle = matchingOwnerVehicle() ?? ownerVehicles.first
            }
            ownerLastError = nil
            await refreshOwnerStatus()
        } catch {
            ownerLastError = error.localizedDescription
        }
    }

    func selectOwnerVehicle(_ vehicle: OwnerVehicle) async {
        selectedOwnerVehicle = vehicle
        await refreshOwnerStatus()
    }

    func performOwnerCommand(_ command: OwnerVehicleCommand) async throws {
        guard let vehicle = selectedOwnerVehicle else { throw OwnerAPIError.vehicleUnavailable }
        guard !isDemoMode else { return }
        isOwnerCommandRunning = true
        defer { isOwnerCommandRunning = false }
        do {
            try await ownerAPI.send(command, vehicleID: vehicle.id)
            ownerLastError = nil
            await refreshOwnerStatus()
        } catch {
            ownerLastError = error.localizedDescription
            throw error
        }
    }

    private func restoreOwnerConnection() async {
        hasOwnerCredentials = await ownerAPI.isConfigured()
        guard hasOwnerCredentials else {
            ownerConnectionState = .disconnected
            return
        }
        ownerConnectionState = .connecting
        do {
            ownerVehicles = try await ownerAPI.vehicles()
            selectedOwnerVehicle = matchingOwnerVehicle() ?? ownerVehicles.first
            ownerConnectionState = .connected
        } catch {
            ownerConnectionState = .failed
            ownerLastError = error.localizedDescription
        }
    }

    private func refreshOwnerStatus() async {
        guard !isDemoMode, let vehicle = selectedOwnerVehicle else { return }
        do {
            let live = try await ownerAPI.vehicleData(vehicleID: vehicle.id)
            status = live.tessalyticsStatus
            statusUnits = live.tessalyticsUnits
            statusFetchedAt = .now
            statusUsesOwnerAPI = true
            ownerLastError = nil
            if let profile = selectedProfile, let selectedVehicle {
                VehicleStatusCache(context: container.mainContext).save(
                    status: live.tessalyticsStatus,
                    units: live.tessalyticsUnits,
                    serverID: profile.id,
                    carID: selectedVehicle.id,
                    fetchedAt: statusFetchedAt ?? .now
                )
            }
        } catch {
            statusUsesOwnerAPI = false
            ownerLastError = error.localizedDescription
        }
    }

    private func matchingOwnerVehicle() -> OwnerVehicle? {
        guard let name = selectedVehicle?.name?.lowercased() else { return nil }
        return ownerVehicles.first { $0.displayName?.lowercased() == name }
    }


    private func persistVehicles(_ values: [Vehicle]) {
        let context = container.mainContext
        for vehicle in values {
            let key = VehicleRecord.key(serverID: vehicle.serverID, carID: vehicle.id)
            let descriptor = FetchDescriptor<VehicleRecord>(predicate: #Predicate { $0.cacheKey == key })
            if let record = try? context.fetch(descriptor).first { record.update(vehicle) }
            else { context.insert(VehicleRecord(vehicle: vehicle)) }
        }
        try? context.save()
    }

    private func cachedVehicles(serverID: UUID) -> [Vehicle] {
        let id = serverID.uuidString
        let descriptor = FetchDescriptor<VehicleRecord>(predicate: #Predicate { $0.serverID == id })
        return ((try? container.mainContext.fetch(descriptor)) ?? []).map(\.vehicle)
    }

    private func restoreLastLiveStatus(profile: ServerProfile, vehicle: Vehicle) {
        let cached = VehicleStatusCache(context: container.mainContext)
            .loadLastLive(serverID: profile.id, carID: vehicle.id)
        lastLiveStatus = cached?.status
        lastLiveStatusAt = cached?.fetchedAt
    }

    private func restoreCachedStatus(profile: ServerProfile, vehicle: Vehicle) {
        guard let cached = VehicleStatusCache(context: container.mainContext).load(serverID: profile.id, carID: vehicle.id) else {
            status = nil
            statusUnits = cachedSettings(serverID: profile.id)
            statusFetchedAt = nil
            statusUsesOwnerAPI = false
            restoreLastLiveStatus(profile: profile, vehicle: vehicle)
            return
        }
        status = cached.status
        statusUnits = cached.units ?? cachedSettings(serverID: profile.id)
        statusFetchedAt = cached.fetchedAt
        restoreLastLiveStatus(profile: profile, vehicle: vehicle)
        statusUsesOwnerAPI = false
    }

    private func cachedSettings(serverID: UUID) -> UnitsDTO? {
        let id = serverID.uuidString
        let descriptor = FetchDescriptor<GlobalSettingsRecord>(predicate: #Predicate { $0.serverID == id })
        guard let record = try? container.mainContext.fetch(descriptor).first else { return nil }
        return UnitsDTO(
            unitOfLength: record.lengthUnit,
            unitOfPressure: record.pressureUnit,
            unitOfTemperature: record.temperatureUnit
        )
    }

    private func persistSettings(_ value: GlobalSettingsDataDTO, serverID: UUID) {
        let id = serverID.uuidString
        let descriptor = FetchDescriptor<GlobalSettingsRecord>(predicate: #Predicate { $0.serverID == id })
        if let record = try? container.mainContext.fetch(descriptor).first {
            record.lengthUnit = value.settings.teslamateUnits?.unitOfLength
            record.pressureUnit = value.settings.teslamateUnits?.unitOfPressure
            record.temperatureUnit = value.settings.teslamateUnits?.unitOfTemperature
            record.updatedAt = .now
        } else {
            container.mainContext.insert(GlobalSettingsRecord(serverID: serverID, units: value.settings.teslamateUnits))
        }
        try? container.mainContext.save()
    }

    private static let demoModeKey = "tessalytics.demo-mode.enabled"
}

