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
    private let keychain: any CredentialStore
    private let ownerAPI: OwnerAPISession
    private let userDefaults: UserDefaults
    private var statusTask: Task<Void, Never>?
    private var pollingTarget: PollingTarget?
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
                offline: ProcessInfo.processInfo.arguments.contains("-ui-demo-offline")
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

    private func activateDemo(showDirectControls: Bool, offline: Bool = false) {
        stopStatusPolling()
        stopHistoryPolling()
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
        status = offline ? DemoExperience.offlineStatus() : DemoExperience.status()
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
    }

    func selectProfile(_ profile: ServerProfile) async {
        stopStatusPolling()
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
        recomputeFleetStatistics()
        startStatusPolling()
        startHistoryPolling()
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
        requestStatusRefresh()
    }

    func handleBackgroundEntry() {
        stopStatusPolling()
        stopHistoryPolling()
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
            VehicleStatusCache(context: container.mainContext).save(
                status: response.status,
                units: response.units,
                serverID: profile.id,
                carID: vehicle.id,
                fetchedAt: statusFetchedAt ?? .now
            )
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

    private func restoreCachedStatus(profile: ServerProfile, vehicle: Vehicle) {
        guard let cached = VehicleStatusCache(context: container.mainContext).load(serverID: profile.id, carID: vehicle.id) else {
            status = nil
            statusUnits = cachedSettings(serverID: profile.id)
            statusFetchedAt = nil
            statusUsesOwnerAPI = false
            return
        }
        status = cached.status
        statusUnits = cached.units ?? cachedSettings(serverID: profile.id)
        statusFetchedAt = cached.fetchedAt
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

private extension Error {
    var userFacingMessage: String {
        if let error = self as? ClientError { return error.localizedDescription }
        return "The server could not be reached. Cached history remains available."
    }
}
