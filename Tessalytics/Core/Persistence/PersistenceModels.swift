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
    /// Left in place, unread: it recorded which API a server spoke, back when
    /// there were two. Removing a stored property needs a schema migration, and
    /// an unread column is cheaper than one.
    var kindRaw: String?

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
    /// Optional so the store migrates in place: this arrived after the schema
    /// did, and TeslaMateApi never reports it at all.
    var vin: String?
    /// The variant the owner confirmed for the pack lookup.
    ///
    /// Stored rather than re-inferred because the inference is a guess from a
    /// trim badge that is often absent or ambiguous, and the answer decides which
    /// pack capacity every health figure divides by.
    var packVariant: String?
    var totalDrives: Int?
    var totalCharges: Int?
    var totalUpdates: Int?
    var updatedAt: Date
    /// Owner-supplied pack capacity when new, kWh.
    ///
    /// The derived figure is the largest capacity the recorded history implies,
    /// which understates a car whose logging began after some degradation: a
    /// pack rated 84 kWh new reads as 74 if recording started at 15,000 miles.
    var capacityNewOverride: Double?
    /// Owner-supplied rated range at 100% when new, in the server's length unit.
    var maxRangeNewOverride: Double?
    init(vehicle: Vehicle) {
        cacheKey = Self.key(serverID: vehicle.serverID, carID: vehicle.id); serverID = vehicle.serverID.uuidString; carID = vehicle.id
        name = vehicle.name; model = vehicle.model; trim = vehicle.trim; vin = vehicle.vin
        totalDrives = vehicle.totalDrives
        totalCharges = vehicle.totalCharges; totalUpdates = vehicle.totalUpdates; updatedAt = .now
    }
    static func key(serverID: UUID, carID: Int) -> String { "\(serverID.uuidString):\(carID)" }
    func update(_ vehicle: Vehicle) {
        name = vehicle.name; model = vehicle.model; trim = vehicle.trim
        // A server that does not report a VIN must not erase one already known:
        // switching a profile from Tessalytics Backend to TeslaMateApi would
        // otherwise take the pack lookup with it.
        if let reported = vehicle.vin?.nilIfEmpty { vin = reported }
        totalDrives = vehicle.totalDrives; totalCharges = vehicle.totalCharges
        totalUpdates = vehicle.totalUpdates; updatedAt = .now
    }
    var vehicle: Vehicle { Vehicle(serverID: UUID(uuidString: serverID) ?? UUID(), id: carID, name: name, model: model, trim: trim, vin: vin, totalDrives: totalDrives, totalCharges: totalCharges, totalUpdates: totalUpdates) }
}

@Model
final class DriveRecord {
    @Attribute(.unique) var cacheKey: String; var serverID: String; var carID: Int; var driveID: Int
    var startDate: Date?; var endDate: Date?; var startAddress: String?; var endAddress: String?
    var distance: Double?; var durationMinutes: Int?; var speedMax: Double?; var speedAverage: Double?
    var energy: Double?; var efficiency: Double?; var updatedAt: Date
    // Added for fleet-wide statistics; optional so the store migrates in place.
    var odometerStart: Double?; var odometerEnd: Double?
    var startLevel: Int?; var endLevel: Int?
    var startRatedRange: Double?; var endRatedRange: Double?
    var outsideTemp: Double?
    var reducedRange: Bool?; var isSufficientlyPrecise: Bool?
    // Where the drive began and ended, for the places map. Optional so the store
    // migrates in place and a server that omits them stays usable.
    var startLatitude: Double?; var startLongitude: Double?
    var endLatitude: Double?; var endLongitude: Double?

    init(serverID: UUID, carID: Int, dto: DriveSummaryDTO) {
        cacheKey = Self.key(serverID: serverID, carID: carID, id: dto.driveId); self.serverID = serverID.uuidString; self.carID = carID; driveID = dto.driveId
        startDate = dto.startDate?.value; endDate = dto.endDate?.value; startAddress = dto.startAddress; endAddress = dto.endAddress
        distance = dto.odometerDetails?.odometerDistance; durationMinutes = dto.durationMin; speedMax = dto.speedMax; speedAverage = dto.speedAvg
        energy = dto.energyConsumedNet; efficiency = dto.consumptionNet; updatedAt = .now
        apply(dto)
    }

    func apply(_ dto: DriveSummaryDTO) {
        odometerStart = dto.odometerDetails?.odometerStart
        odometerEnd = dto.odometerDetails?.odometerEnd
        startLevel = dto.batteryDetails?.resolvedStartLevel
        endLevel = dto.batteryDetails?.resolvedEndLevel
        startRatedRange = dto.rangeRated?.startRange
        endRatedRange = dto.rangeRated?.endRange
        outsideTemp = dto.outsideTempAvg
        reducedRange = dto.batteryDetails?.reducedRange
        isSufficientlyPrecise = dto.batteryDetails?.isSufficientlyPrecise
        // Only overwrite with something: a later summary that omits coordinates
        // must not erase what an earlier one supplied.
        if let start = dto.startCoordinate {
            startLatitude = start.latitude
            startLongitude = start.longitude
        }
        if let end = dto.endCoordinate {
            endLatitude = end.latitude
            endLongitude = end.longitude
        }
    }

    static func key(serverID: UUID, carID: Int, id: Int) -> String { "\(serverID.uuidString):\(carID):drive:\(id)" }
}

@Model
final class ChargeRecord {
    @Attribute(.unique) var cacheKey: String; var serverID: String; var carID: Int; var chargeID: Int
    var startDate: Date?; var endDate: Date?; var address: String?; var energyAdded: Double?; var energyUsed: Double?
    var cost: Double?; var durationMinutes: Int?; var updatedAt: Date
    // Added for capacity modelling and the charging map; optional so the store
    // migrates in place.
    var odometer: Double?; var latitude: Double?; var longitude: Double?
    var startLevel: Int?; var endLevel: Int?
    var startRatedRange: Double?; var endRatedRange: Double?
    var outsideTemp: Double?

    init(serverID: UUID, carID: Int, dto: ChargeSummaryDTO) {
        cacheKey = Self.key(serverID: serverID, carID: carID, id: dto.chargeId); self.serverID = serverID.uuidString; self.carID = carID; chargeID = dto.chargeId
        startDate = dto.startDate?.value; endDate = dto.endDate?.value; address = dto.address; energyAdded = dto.chargeEnergyAdded
        energyUsed = dto.chargeEnergyUsed; cost = dto.cost; durationMinutes = dto.durationMin; updatedAt = .now
        apply(dto)
    }

    func apply(_ dto: ChargeSummaryDTO) {
        odometer = dto.odometer
        latitude = dto.latitude
        longitude = dto.longitude
        startLevel = dto.batteryDetails?.resolvedStartLevel
        endLevel = dto.batteryDetails?.resolvedEndLevel
        startRatedRange = dto.rangeRated?.startRange
        endRatedRange = dto.rangeRated?.endRange
        outsideTemp = dto.outsideTempAvg
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
    /// kWh per 100 km, as TeslaMateApi reports it. Needed to turn a rated range
    /// reading back into pack capacity.
    var ratedEfficiency: Double?

    init(serverID: UUID, carID: Int, dto: BatteryHealthDTO, date: Date = .now) {
        cacheKey = "\(serverID.uuidString):\(carID):\(Calendar.current.startOfDay(for: date).timeIntervalSince1970)"
        self.serverID = serverID.uuidString; self.carID = carID; observedAt = date; maxRange = dto.maxRange; currentRange = dto.currentRange
        maxCapacity = dto.maxCapacity; currentCapacity = dto.currentCapacity; healthPercent = dto.batteryHealthPercentage
        ratedEfficiency = dto.ratedEfficiency
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

/// The cached driven path for one vehicle.
///
/// Stored as one encoded blob rather than a row per coordinate: twenty thousand
/// SwiftData rows to draw a polyline would cost more to fetch than the request it
/// replaces.
@Model
final class TrackRecord {
    @Attribute(.unique) var cacheKey: String
    var serverID: String
    var carID: Int
    /// JSON `[[ [lat, lon], ... ], ...]` — one array per journey.
    var encodedSegments: Data
    var pointCount: Int
    /// The newest drive the path covers, so a refresh is only made when there is
    /// something new to draw.
    var coversUntil: Date?
    var fetchedAt: Date

    init(serverID: UUID, carID: Int, segments: [[CoordinateDTO]], coversUntil: Date?) {
        cacheKey = Self.key(serverID: serverID, carID: carID)
        self.serverID = serverID.uuidString
        self.carID = carID
        encodedSegments = Self.encode(segments)
        pointCount = segments.reduce(0) { $0 + $1.count }
        self.coversUntil = coversUntil
        fetchedAt = .now
    }

    func update(segments: [[CoordinateDTO]], coversUntil: Date?) {
        encodedSegments = Self.encode(segments)
        pointCount = segments.reduce(0) { $0 + $1.count }
        self.coversUntil = coversUntil
        fetchedAt = .now
    }

    var segments: [[CoordinateDTO]] {
        guard let pairs = try? JSONDecoder().decode([[[Double]]].self, from: encodedSegments) else { return [] }
        return pairs.map { segment in
            segment.compactMap { pair in
                guard pair.count == 2 else { return nil }
                return CoordinateDTO(latitude: pair[0], longitude: pair[1])
            }
        }
    }

    private static func encode(_ segments: [[CoordinateDTO]]) -> Data {
        let pairs = segments.map { $0.map { [$0.latitude, $0.longitude] } }
        return (try? JSONEncoder().encode(pairs)) ?? Data()
    }

    static func key(serverID: UUID, carID: Int) -> String { "\(serverID.uuidString):\(carID):track" }
}
