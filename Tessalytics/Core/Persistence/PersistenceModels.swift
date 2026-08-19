import Foundation
import SwiftData

@Model
final class ServerProfileRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var baseURLString: String
    var authenticationMethodRaw: String
    var allowsLocalHTTP: Bool
    var isSelected: Bool
    var createdAt: Date

    init(profile: ServerProfile, isSelected: Bool) {
        id = profile.id; name = profile.name; baseURLString = profile.baseURL.absoluteString
        authenticationMethodRaw = profile.authenticationMethod.rawValue
        allowsLocalHTTP = profile.allowsLocalHTTP; self.isSelected = isSelected; createdAt = .now
    }
    var profile: ServerProfile? {
        guard let url = URL(string: baseURLString), let method = AuthenticationMethod(rawValue: authenticationMethodRaw) else { return nil }
        return ServerProfile(id: id, name: name, baseURL: url, authenticationMethod: method,
                             allowsLocalHTTP: allowsLocalHTTP, isSelected: isSelected)
    }
}

@Model
final class VehicleRecord {
    @Attribute(.unique) var cacheKey: String
    var serverID: String
    var carID: Int
    var name: String?
    var model: String?
    var trim: String?
    var totalDrives: Int?
    var totalCharges: Int?
    var totalUpdates: Int?
    var updatedAt: Date
    init(vehicle: Vehicle) {
        cacheKey = Self.key(serverID: vehicle.serverID, carID: vehicle.id); serverID = vehicle.serverID.uuidString; carID = vehicle.id
        name = vehicle.name; model = vehicle.model; trim = vehicle.trim; totalDrives = vehicle.totalDrives
        totalCharges = vehicle.totalCharges; totalUpdates = vehicle.totalUpdates; updatedAt = .now
    }
    static func key(serverID: UUID, carID: Int) -> String { "\(serverID.uuidString):\(carID)" }
    func update(_ vehicle: Vehicle) { name = vehicle.name; model = vehicle.model; trim = vehicle.trim; totalDrives = vehicle.totalDrives; totalCharges = vehicle.totalCharges; totalUpdates = vehicle.totalUpdates; updatedAt = .now }
    var vehicle: Vehicle { Vehicle(serverID: UUID(uuidString: serverID) ?? UUID(), id: carID, name: name, model: model, trim: trim, totalDrives: totalDrives, totalCharges: totalCharges, totalUpdates: totalUpdates) }
}

@Model
final class DriveRecord {
    @Attribute(.unique) var cacheKey: String; var serverID: String; var carID: Int; var driveID: Int
    var startDate: Date?; var endDate: Date?; var startAddress: String?; var endAddress: String?
    var distance: Double?; var durationMinutes: Int?; var speedMax: Double?; var speedAverage: Double?
    var energy: Double?; var efficiency: Double?; var updatedAt: Date
    init(serverID: UUID, carID: Int, dto: DriveSummaryDTO) {
        cacheKey = Self.key(serverID: serverID, carID: carID, id: dto.driveId); self.serverID = serverID.uuidString; self.carID = carID; driveID = dto.driveId
        startDate = dto.startDate?.value; endDate = dto.endDate?.value; startAddress = dto.startAddress; endAddress = dto.endAddress
        distance = dto.odometerDetails?.odometerDistance; durationMinutes = dto.durationMin; speedMax = dto.speedMax; speedAverage = dto.speedAvg
        energy = dto.energyConsumedNet; efficiency = dto.consumptionNet; updatedAt = .now
    }
    static func key(serverID: UUID, carID: Int, id: Int) -> String { "\(serverID.uuidString):\(carID):drive:\(id)" }
}

@Model
final class ChargeRecord {
    @Attribute(.unique) var cacheKey: String; var serverID: String; var carID: Int; var chargeID: Int
    var startDate: Date?; var endDate: Date?; var address: String?; var energyAdded: Double?; var energyUsed: Double?
    var cost: Double?; var durationMinutes: Int?; var updatedAt: Date
    init(serverID: UUID, carID: Int, dto: ChargeSummaryDTO) {
        cacheKey = Self.key(serverID: serverID, carID: carID, id: dto.chargeId); self.serverID = serverID.uuidString; self.carID = carID; chargeID = dto.chargeId
        startDate = dto.startDate?.value; endDate = dto.endDate?.value; address = dto.address; energyAdded = dto.chargeEnergyAdded
        energyUsed = dto.chargeEnergyUsed; cost = dto.cost; durationMinutes = dto.durationMin; updatedAt = .now
    }
    static func key(serverID: UUID, carID: Int, id: Int) -> String { "\(serverID.uuidString):\(carID):charge:\(id)" }
}

@Model
final class DetailCacheRecord {
    @Attribute(.unique) var cacheKey: String; var serverID: String; var carID: Int; var kind: String; var backendID: Int
    @Attribute(.externalStorage) var payload: Data; var completed: Bool; var cachedAt: Date
    init(key: String, serverID: UUID, carID: Int, kind: String, backendID: Int, payload: Data, completed: Bool) {
        cacheKey = key; self.serverID = serverID.uuidString; self.carID = carID; self.kind = kind; self.backendID = backendID
        self.payload = payload; self.completed = completed; cachedAt = .now
    }
}

@Model
final class BatteryHealthRecord {
    @Attribute(.unique) var cacheKey: String; var serverID: String; var carID: Int; var observedAt: Date
    var maxRange: Double?; var currentRange: Double?; var maxCapacity: Double?; var currentCapacity: Double?; var healthPercent: Double?
    init(serverID: UUID, carID: Int, dto: BatteryHealthDTO, date: Date = .now) {
        cacheKey = "\(serverID.uuidString):\(carID):\(Calendar.current.startOfDay(for: date).timeIntervalSince1970)"
        self.serverID = serverID.uuidString; self.carID = carID; observedAt = date; maxRange = dto.maxRange; currentRange = dto.currentRange
        maxCapacity = dto.maxCapacity; currentCapacity = dto.currentCapacity; healthPercent = dto.batteryHealthPercentage
    }
}

@Model
final class FirmwareUpdateRecord {
    @Attribute(.unique) var cacheKey: String; var serverID: String; var carID: Int; var updateID: Int
    var startDate: Date?; var endDate: Date?; var version: String?
    init(serverID: UUID, carID: Int, dto: FirmwareUpdateDTO) {
        cacheKey = "\(serverID.uuidString):\(carID):update:\(dto.updateId)"; self.serverID = serverID.uuidString; self.carID = carID; updateID = dto.updateId
        startDate = dto.startDate?.value; endDate = dto.endDate?.value; version = dto.version
    }
}

@Model
final class GlobalSettingsRecord {
    @Attribute(.unique) var serverID: String
    var lengthUnit: String?
    var pressureUnit: String?
    var temperatureUnit: String?
    var updatedAt: Date
    init(serverID: UUID, units: UnitsDTO?) {
        self.serverID = serverID.uuidString; lengthUnit = units?.unitOfLength
        pressureUnit = units?.unitOfPressure; temperatureUnit = units?.unitOfTemperature; updatedAt = .now
    }
}

@Model
final class SyncMetadataRecord {
    @Attribute(.unique) var cacheKey: String; var lastSuccess: Date?; var latestPage: Int; var hasMore: Bool
    init(key: String, lastSuccess: Date? = nil, latestPage: Int = 0, hasMore: Bool = true) { cacheKey = key; self.lastSuccess = lastSuccess; self.latestPage = latestPage; self.hasMore = hasMore }
}
