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
    var ownerVehicles: [OwnerVehicle] = []
    var selectedOwnerVehicle: OwnerVehicle?
    var ownerLastError: String?
    var isOwnerCommandRunning = false
    private(set) var isDemoMode = false

    private let container: ModelContainer
    private let keychain: any CredentialStore
    private let ownerAPI: OwnerAPISession
    private var statusTask: Task<Void, Never>?
    var isStatusPolling: Bool { statusTask != nil }
    var isOwnerConnected: Bool { ownerConnectionState == .connected }

    init(
        container: ModelContainer,
        keychain: any CredentialStore = KeychainCredentialStore(),
        ownerCredentialStore: any OwnerCredentialStore = KeychainOwnerCredentialStore(),
        ownerTransport: any HTTPTransport = URLSession.shared
    ) {
        self.container = container
        self.keychain = keychain
        ownerAPI = OwnerAPISession(store: ownerCredentialStore, transport: ownerTransport)
    }

    func start() async {
        if ProcessInfo.processInfo.arguments.contains("-ui-onboarding") {
            phase = .onboarding
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-demo") {
            isDemoMode = true
            let profile = ServerProfile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Demo Server", baseURL: URL(string: "https://demo.invalid")!, authenticationMethod: .none, allowsLocalHTTP: false, isSelected: true)
            profiles = [profile]; selectedProfile = profile
            let vehicle = Vehicle(serverID: profile.id, id: 1, name: "Demo Vehicle", model: "Model Y", trim: "Long Range", totalDrives: 248, totalCharges: 61, totalUpdates: 12)
            vehicles = [vehicle]
            selectedVehicle = vehicle
            status = .demo
            statusUnits = UnitsDTO(unitOfLength: "mi", unitOfPressure: "psi", unitOfTemperature: "C")
            statusFetchedAt = .now
            if !ProcessInfo.processInfo.arguments.contains("-ui-owner-disconnected") {
                let ownerVehicle = OwnerVehicle(id: 987_654_321, vehicleId: 123_456_789, vin: "DEMO0000000000001", displayName: "Demo Vehicle", state: "online")
                ownerVehicles = [ownerVehicle]
                selectedOwnerVehicle = ownerVehicle
                ownerConnectionState = .connected
                statusUsesOwnerAPI = true
            }
            phase = .ready
            return
        }
        let context = container.mainContext
        let descriptor = FetchDescriptor<ServerProfileRecord>(sortBy: [SortDescriptor(\.name)])
        let records = (try? context.fetch(descriptor)) ?? []
        profiles = records.compactMap(\.profile)
        selectedProfile = profiles.first(where: \.isSelected) ?? profiles.first
        guard let selectedProfile else {
            phase = .onboarding
            return
        }
        phase = .ready
        await restoreOwnerConnection()
        await refreshVehicles(profile: selectedProfile)
    }

    func client(for profile: ServerProfile) throws -> TeslaMateAPIClient {
        let credentials = try keychain.credentials(profileID: profile.id)
        return TeslaMateAPIClient(baseURL: profile.baseURL, authentication: credentials?.authentication ?? .none)
    }

    func saveProfile(_ draft: ProfileDraft) async throws {
        let profile = try draft.profile()
        if let credentials = draft.credentials { try keychain.save(credentials, profileID: profile.id) }
        let context = container.mainContext
        let existing = try context.fetch(FetchDescriptor<ServerProfileRecord>())
        existing.forEach { $0.isSelected = false }
        context.insert(ServerProfileRecord(profile: profile, isSelected: true))
        try context.save()
        profiles = (try context.fetch(FetchDescriptor<ServerProfileRecord>())).compactMap(\.profile)
        selectedProfile = profile
        phase = .ready
        await refreshVehicles(profile: profile)
    }

    func refreshVehicles(profile: ServerProfile? = nil) async {
        guard let profile = profile ?? selectedProfile else { return }
        do {
            let response = try await client(for: profile).cars()
            vehicles = response.cars.map { $0.vehicle(serverID: profile.id) }
            selectedVehicle = vehicles.first
            isOffline = false
            persistVehicles(vehicles)
            if let settings = try? await client(for: profile).globalSettings() {
                persistSettings(settings, serverID: profile.id)
            }
        } catch {
            isOffline = true
            lastError = error.userFacingMessage
            vehicles = cachedVehicles(serverID: profile.id)
            selectedVehicle = vehicles.first
        }
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
        selectedVehicle = vehicle
        status = nil
        statusUnits = nil
        if isOwnerConnected {
            selectedOwnerVehicle = matchingOwnerVehicle() ?? selectedOwnerVehicle
            Task { await refreshOwnerStatus() }
        }
    }

    func startStatusPolling() {
        guard !isDemoMode, statusTask == nil, let profile = selectedProfile, let vehicle = selectedVehicle else { return }
        statusTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshStatus(profile: profile, vehicle: vehicle)
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
    }

    func stopStatusPolling() {
        statusTask?.cancel()
        statusTask = nil
    }

    func refreshStatus(profile: ServerProfile? = nil, vehicle: Vehicle? = nil) async {
        guard !isDemoMode else { return }
        guard let profile = profile ?? selectedProfile, let vehicle = vehicle ?? selectedVehicle else { return }
        var notificationStatus: VehicleStatus?
        do {
            let response = try await client(for: profile).status(carID: vehicle.id)
            status = response.status
            statusUnits = response.units
            statusFetchedAt = .now
            statusUsesOwnerAPI = false
            isOffline = false
            notificationStatus = response.status
        } catch {
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
        ownerLastError = nil
        do {
            ownerVehicles = try await ownerAPI.configure(accessToken: accessToken, refreshToken: refreshToken, region: region)
            selectedOwnerVehicle = matchingOwnerVehicle() ?? ownerVehicles.first
            ownerConnectionState = .connected
            await refreshOwnerStatus()
        } catch {
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
        guard await ownerAPI.isConfigured() else {
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
}

private extension VehicleStatus {
    static let demo = VehicleStatus(
        displayName: "Demo Vehicle",
        state: "online",
        stateSince: FlexibleDate(.now.addingTimeInterval(-1_800)),
        odometer: 18_642,
        carStatus: CarStatusDTO(
            healthy: true,
            locked: true,
            sentryMode: false,
            windowsOpen: false,
            doorsOpen: false,
            trunkOpen: false,
            frunkOpen: false
        ),
        carDetails: CarDetailsDTO(model: "Model Y", trimBadging: "Long Range", efficiency: 0.158),
        carGeodata: CarGeodataDTO(geofence: "Home", location: nil),
        carVersions: CarVersionsDTO(version: "2026.20.3", updateAvailable: false, updateVersion: nil),
        drivingDetails: DrivingDetailsDTO(shiftState: nil, power: 0, speed: 0, heading: nil, elevation: nil),
        climateDetails: ClimateDetailsDTO(isClimateOn: false, insideTemp: 21.5, outsideTemp: 18.0, isPreconditioning: false, climateKeeperMode: "off"),
        batteryDetails: StatusBatteryDTO(estBatteryRange: 238, ratedBatteryRange: 229, idealBatteryRange: 245, batteryLevel: 78, usableBatteryLevel: 77),
        chargingDetails: StatusChargingDTO(
            pluggedIn: false,
            chargingState: "Disconnected",
            chargeEnergyAdded: 0,
            chargeLimitSoc: 80,
            chargePortDoorOpen: false,
            chargerActualCurrent: 0,
            chargerPhases: nil,
            chargerPower: 0,
            chargerVoltage: 0,
            scheduledChargingStartTime: nil,
            timeToFullCharge: nil
        ),
        tpmsDetails: TPMSDTO(tpmsPressureFl: 2.9, tpmsPressureFr: 2.9, tpmsPressureRl: 3.0, tpmsPressureRr: 3.0)
    )
}

private extension Error {
    var userFacingMessage: String {
        if let error = self as? ClientError { return error.localizedDescription }
        return "The server could not be reached. Cached history remains available."
    }
}
