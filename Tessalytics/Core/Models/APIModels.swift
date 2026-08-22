import Foundation

struct Envelope<T: Decodable & Sendable>: Decodable, Sendable { let data: T }

struct UnitsDTO: Codable, Hashable, Sendable {
    let unitOfLength: String?
    let unitOfPressure: String?
    let unitOfTemperature: String?
}

extension UnitsDTO {
    static let metricDefaults = UnitsDTO(
        unitOfLength: "km",
        unitOfPressure: "bar",
        unitOfTemperature: "C"
    )

    var lengthSymbol: String {
        unitOfLength?.lowercased() == "mi" ? "mi" : "km"
    }

    var speedSymbol: String {
        lengthSymbol == "mi" ? "mph" : "km/h"
    }

    var temperatureSymbol: String {
        unitOfTemperature?
            .replacingOccurrences(of: "°", with: "")
            .uppercased() == "F" ? "°F" : "°C"
    }

    var pressureSymbol: String {
        unitOfPressure?.lowercased() == "psi" ? "psi" : "bar"
    }

    var efficiencySymbol: String { "Wh/\(lengthSymbol)" }

    func length(_ value: Double?) -> Measurement<UnitLength>? {
        guard let value else { return nil }
        return Measurement(value: value, unit: lengthSymbol == "mi" ? .miles : .kilometers)
    }
    func speed(_ value: Double?) -> Measurement<UnitSpeed>? {
        guard let value else { return nil }
        return Measurement(value: value, unit: speedSymbol == "mph" ? .milesPerHour : .kilometersPerHour)
    }
    func temperature(_ value: Double?) -> Measurement<UnitTemperature>? {
        guard let value else { return nil }
        return Measurement(value: value, unit: temperatureSymbol == "°F" ? .fahrenheit : .celsius)
    }
    func pressure(_ value: Double?) -> Measurement<UnitPressure>? {
        guard let value else { return nil }
        return Measurement(value: value, unit: pressureSymbol == "psi" ? .poundsForcePerSquareInch : .bars)
    }
}

struct CarReferenceDTO: Decodable, Hashable, Sendable {
    let carId: Int
    let carName: String?
}

struct CarsDataDTO: Decodable, Sendable { let cars: [CarDTO] }
struct CarDTO: Decodable, Identifiable, Sendable {
    let carId: Int
    let name: String?
    let carDetails: CarDetailsDTO?
    let teslamateStats: TeslaMateStatsDTO?
    var id: Int { carId }
    func vehicle(serverID: UUID) -> Vehicle {
        Vehicle(serverID: serverID, id: carId, name: name, model: carDetails?.model,
                trim: carDetails?.trimBadging, totalDrives: teslamateStats?.totalDrives,
                totalCharges: teslamateStats?.totalCharges, totalUpdates: teslamateStats?.totalUpdates)
    }
}
struct CarDetailsDTO: Codable, Sendable { let model: String?; let trimBadging: String?; let efficiency: Double? }
struct TeslaMateStatsDTO: Decodable, Sendable { let totalCharges: Int?; let totalDrives: Int?; let totalUpdates: Int? }

struct StatusDataDTO: Decodable, Sendable { let car: CarReferenceDTO; let status: VehicleStatus; let units: UnitsDTO? }
struct VehicleStatus: Codable, Sendable {
    let displayName: String?
    let state: String?
    let stateSince: FlexibleDate?
    let odometer: Double?
    let carStatus: CarStatusDTO?
    let carDetails: CarDetailsDTO?
    let carGeodata: CarGeodataDTO?
    let carVersions: CarVersionsDTO?
    let drivingDetails: DrivingDetailsDTO?
    let climateDetails: ClimateDetailsDTO?
    let batteryDetails: StatusBatteryDTO?
    let chargingDetails: StatusChargingDTO?
    let tpmsDetails: TPMSDTO?
}
struct CarStatusDTO: Codable, Sendable {
    let healthy: Bool?; let locked: Bool?; let sentryMode: Bool?; let windowsOpen: Bool?; let doorsOpen: Bool?
    let trunkOpen: Bool?; let frunkOpen: Bool?
}
struct CarGeodataDTO: Codable, Sendable { let geofence: String?; let location: CoordinateDTO? }
struct CoordinateDTO: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double

    /// Whether this is a position rather than the null island a server reports
    /// when it has none.
    var isReported: Bool { abs(latitude) > 0.0001 || abs(longitude) > 0.0001 }
}
struct CarVersionsDTO: Codable, Sendable { let version: String?; let updateAvailable: Bool?; let updateVersion: String? }
/// The live driving block.
///
/// `autopilotState` and `isAutopilotEngaged` are reported only by servers whose
/// broker publishes them — TeslaMate itself does not — so both stay optional and
/// the app shows nothing at all rather than claiming a car is driving itself.
struct DrivingDetailsDTO: Codable, Sendable {
    let shiftState: String?
    let power: Double?
    let speed: Double?
    let heading: Double?
    let elevation: Double?
    /// What the car calls the system that is driving it, verbatim from the
    /// server: "Full Self-Driving", "Autosteer", "off".
    let autopilotState: String?
    /// Whether the server says a driving aid is currently steering.
    let isAutopilotEngaged: Bool?
    /// Whether anyone is in the car. The server reports it and the app used to
    /// discard it; it is the difference between a car parked with the family in
    /// it and one parked alone with the sentry on.
    let isUserPresent: Bool?

    /// Spelled out rather than left to the memberwise initialiser so the two
    /// autopilot fields can be omitted at the many call sites that predate them.
    init(
        shiftState: String?,
        power: Double?,
        speed: Double?,
        heading: Double?,
        elevation: Double?,
        autopilotState: String? = nil,
        isAutopilotEngaged: Bool? = nil,
        isUserPresent: Bool? = nil
    ) {
        self.shiftState = shiftState
        self.power = power
        self.speed = speed
        self.heading = heading
        self.elevation = elevation
        self.autopilotState = autopilotState
        self.isAutopilotEngaged = isAutopilotEngaged
        self.isUserPresent = isUserPresent
    }
}
struct ClimateDetailsDTO: Codable, Sendable { let isClimateOn: Bool?; let insideTemp: Double?; let outsideTemp: Double?; let isPreconditioning: Bool?; let climateKeeperMode: String? }
struct StatusBatteryDTO: Codable, Sendable {
    let estBatteryRange: Double?
    let ratedBatteryRange: Double?
    let idealBatteryRange: Double?
    let batteryLevel: Int?
    let usableBatteryLevel: Int?
    /// The cold-weather buffer in percentage points, as the server computed it.
    /// Preferred over subtracting the two levels here, because the server can
    /// answer when only one of them reached this device.
    let bufferLevel: Int?

    init(
        estBatteryRange: Double?,
        ratedBatteryRange: Double?,
        idealBatteryRange: Double?,
        batteryLevel: Int?,
        usableBatteryLevel: Int?,
        bufferLevel: Int? = nil
    ) {
        self.estBatteryRange = estBatteryRange
        self.ratedBatteryRange = ratedBatteryRange
        self.idealBatteryRange = idealBatteryRange
        self.batteryLevel = batteryLevel
        self.usableBatteryLevel = usableBatteryLevel
        self.bufferLevel = bufferLevel
    }
}
struct StatusChargingDTO: Codable, Sendable {
    let pluggedIn: Bool?; let chargingState: String?; let chargeEnergyAdded: Double?; let chargeLimitSoc: Int?
    let chargePortDoorOpen: Bool?; let chargerActualCurrent: Double?; let chargerPhases: Int?; let chargerPower: Double?
    let chargerVoltage: Int?; let scheduledChargingStartTime: FlexibleDate?; let timeToFullCharge: Double?
}
/// Tyre pressures, and the car's own judgement on each of them.
///
/// The warning flags are the car's, not a threshold this app invented: a correct
/// cold pressure for one wheel and load is a soft warning on another. They were
/// arriving from the server and being dropped on the floor, which is a poor thing
/// to do with the one live reading that is about safety.
struct TPMSDTO: Codable, Sendable {
    let tpmsPressureFl: Double?
    let tpmsPressureFr: Double?
    let tpmsPressureRl: Double?
    let tpmsPressureRr: Double?
    let tpmsWarningFl: Bool?
    let tpmsWarningFr: Bool?
    let tpmsWarningRl: Bool?
    let tpmsWarningRr: Bool?

    init(
        tpmsPressureFl: Double?,
        tpmsPressureFr: Double?,
        tpmsPressureRl: Double?,
        tpmsPressureRr: Double?,
        tpmsWarningFl: Bool? = nil,
        tpmsWarningFr: Bool? = nil,
        tpmsWarningRl: Bool? = nil,
        tpmsWarningRr: Bool? = nil
    ) {
        self.tpmsPressureFl = tpmsPressureFl
        self.tpmsPressureFr = tpmsPressureFr
        self.tpmsPressureRl = tpmsPressureRl
        self.tpmsPressureRr = tpmsPressureRr
        self.tpmsWarningFl = tpmsWarningFl
        self.tpmsWarningFr = tpmsWarningFr
        self.tpmsWarningRl = tpmsWarningRl
        self.tpmsWarningRr = tpmsWarningRr
    }
}

struct DrivesDataDTO: Decodable, Sendable { let car: CarReferenceDTO; let drives: [DriveSummaryDTO]; let units: UnitsDTO? }
struct DriveSummaryDTO: Codable, Identifiable, Sendable {
    let driveId: Int; let startDate: FlexibleDate?; let endDate: FlexibleDate?
    let startAddress: String?; let endAddress: String?; let odometerDetails: OdometerDetailsDTO?
    let durationMin: Int?; let durationStr: String?; let speedMax: Double?; let speedAvg: Double?
    let powerMax: Double?; let powerMin: Double?; let outsideTempAvg: Double?; let insideTempAvg: Double?
    let energyConsumedNet: Double?; let consumptionNet: Double?
    let batteryDetails: LevelWindowDTO?
    let rangeRated: RangeWindowDTO?
    let rangeIdeal: RangeWindowDTO?
    /// Where the drive began and ended. TeslaMateApi omits these, so they stay
    /// optional and the places map simply has fewer points on that server.
    var startCoordinate: CoordinateDTO?
    var endCoordinate: CoordinateDTO?
    var id: Int { driveId }
}
struct OdometerDetailsDTO: Codable, Sendable { let odometerStart: Double?; let odometerEnd: Double?; let odometerDistance: Double? }
struct DriveDataDTO: Decodable, Sendable { let car: CarReferenceDTO; let drive: DriveDetailDTO; let units: UnitsDTO? }
struct DriveDetailDTO: Codable, Identifiable, Sendable {
    let driveId: Int; let startDate: FlexibleDate?; let endDate: FlexibleDate?
    let startAddress: String?; let endAddress: String?; let odometerDetails: OdometerDetailsDTO?
    let durationMin: Int?; let durationStr: String?; let speedMax: Double?; let speedAvg: Double?
    let energyConsumedNet: Double?; let consumptionNet: Double?; let driveDetails: [DrivePointDTO]
    var id: Int { driveId }
}
struct DrivePointDTO: Codable, Identifiable, Sendable {
    let detailId: Int; let date: FlexibleDate?; let latitude: Double; let longitude: Double
    let speed: Double?; let power: Double?; let odometer: Double?; let batteryLevel: Int?; let elevation: Double?
    let climateInfo: DriveClimateDTO?
    var id: Int { detailId }
    var coordinate: CoordinateDTO { CoordinateDTO(latitude: latitude, longitude: longitude) }
}
struct DriveClimateDTO: Codable, Sendable { let insideTemp: Double?; let outsideTemp: Double? }

struct ChargesDataDTO: Decodable, Sendable { let car: CarReferenceDTO; let charges: [ChargeSummaryDTO]; let units: UnitsDTO? }

/// Battery level at the two ends of a session.
struct LevelWindowDTO: Codable, Sendable {
    let startBatteryLevel: Int?
    let endBatteryLevel: Int?
    let startUsableBatteryLevel: Int?
    let endUsableBatteryLevel: Int?
    /// The pack was range-limited (cold, or a reduced-power state), so range
    /// deltas across this session are not comparable with normal ones.
    var reducedRange: Bool?
    /// TeslaMateApi's own judgement on whether this session's range figures are
    /// precise enough to derive consumption from.
    var isSufficientlyPrecise: Bool?

    init(
        startBatteryLevel: Int?,
        endBatteryLevel: Int?,
        startUsableBatteryLevel: Int?,
        endUsableBatteryLevel: Int?,
        reducedRange: Bool? = nil,
        isSufficientlyPrecise: Bool? = nil
    ) {
        self.startBatteryLevel = startBatteryLevel
        self.endBatteryLevel = endBatteryLevel
        self.startUsableBatteryLevel = startUsableBatteryLevel
        self.endUsableBatteryLevel = endUsableBatteryLevel
        self.reducedRange = reducedRange
        self.isSufficientlyPrecise = isSufficientlyPrecise
    }

    /// The usable level is the one worth modelling from — it excludes the cold
    /// buffer — but TeslaMateApi omits it on charge summaries, so fall back.
    var resolvedEndLevel: Int? { endUsableBatteryLevel ?? endBatteryLevel }
    var resolvedStartLevel: Int? { startUsableBatteryLevel ?? startBatteryLevel }
}

/// Range at the two ends of a session, in the server's configured length unit.
struct RangeWindowDTO: Codable, Sendable {
    let startRange: Double?
    let endRange: Double?
    let rangeDiff: Double?
}

struct ChargeSummaryDTO: Codable, Identifiable, Sendable {
    let chargeId: Int; let startDate: FlexibleDate?; let endDate: FlexibleDate?; let address: String?
    let chargeEnergyAdded: Double?; let chargeEnergyUsed: Double?; let cost: Double?; let durationMin: Int?
    let durationStr: String?; let outsideTempAvg: Double?; let odometer: Double?; let latitude: Double?; let longitude: Double?
    let batteryDetails: LevelWindowDTO?
    let rangeRated: RangeWindowDTO?
    let rangeIdeal: RangeWindowDTO?
    var id: Int { chargeId }
}
struct ChargeDataDTO: Decodable, Sendable { let car: CarReferenceDTO; let charge: ChargeDetailDTO; let units: UnitsDTO? }
struct ChargeDetailDTO: Codable, Identifiable, Sendable {
    let chargeId: Int; let startDate: FlexibleDate?; let endDate: FlexibleDate?; let isCharging: Bool?
    let address: String?; let chargeEnergyAdded: Double?; let chargeEnergyUsed: Double?; let cost: Double?
    let durationMin: Int?; let outsideTempAvg: Double?; let chargeDetails: [ChargePointDTO]
    let odometer: Double?; let latitude: Double?; let longitude: Double?
    let batteryDetails: LevelWindowDTO?
    let rangeRated: RangeWindowDTO?
    var id: Int { chargeId }
}
struct ChargePointDTO: Codable, Identifiable, Sendable {
    let detailId: Int; let date: FlexibleDate?; let batteryLevel: Int?; let usableBatteryLevel: Int?
    let chargeEnergyAdded: Double?; let chargerDetails: ChargerDetailsDTO?; let outsideTemp: Double?
    let connChargeCable: String?; let fastChargerInfo: FastChargerInfoDTO?
    let batteryInfo: ChargeBatteryInfoDTO?
    var id: Int { detailId }
}

/// Range readings attached to a charge sample. `ratedBatteryRange` paired with
/// `usableBatteryLevel` is what pack capacity is modelled from.
struct ChargeBatteryInfoDTO: Codable, Sendable {
    let idealBatteryRange: Double?
    let ratedBatteryRange: Double?
    let batteryHeater: Bool?
    let batteryHeaterOn: Bool?
}
struct FastChargerInfoDTO: Codable, Sendable { let fastChargerPresent: Bool?; let fastChargerBrand: String?; let fastChargerType: String? }
struct ChargerDetailsDTO: Codable, Sendable {
    let chargerActualCurrent: Double?; let chargerPhases: Int?; let chargerPilotCurrent: Double?
    let chargerPower: Double?; let chargerVoltage: Double?
}

struct BatteryHealthDataDTO: Decodable, Sendable { let car: CarReferenceDTO; let batteryHealth: BatteryHealthDTO; let units: UnitsDTO? }
struct BatteryHealthDTO: Codable, Sendable {
    let maxRange: Double?; let currentRange: Double?; let maxCapacity: Double?; let currentCapacity: Double?
    let ratedEfficiency: Double?; let batteryHealthPercentage: Double?
}
struct UpdatesDataDTO: Decodable, Sendable { let car: CarReferenceDTO; let updates: [FirmwareUpdateDTO] }
struct FirmwareUpdateDTO: Codable, Identifiable, Sendable {
    let updateId: Int; let startDate: FlexibleDate?; let endDate: FlexibleDate?; let version: String?
    var id: Int { updateId }
}
struct GlobalSettingsDataDTO: Decodable, Sendable { let settings: GlobalSettingsDTO }
struct GlobalSettingsDTO: Decodable, Sendable { let teslamateUnits: UnitsDTO? }

struct FlexibleDate: Codable, Hashable, Sendable {
    let value: Date?
    init(_ value: Date?) { self.value = value }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let raw = try? container.decode(String.self) else { value = nil; return }
        value = FlexibleDateParser.date(from: raw)
    }
    /// Encodes with sub-second precision, because details round-trip through the
    /// local cache.
    ///
    /// A default `ISO8601DateFormatter` writes whole seconds. Position samples
    /// arrive several times a second, so encoding a cached drive and reading it
    /// back collapsed 747 distinct instants onto 211 — enough to make a chart
    /// drop marks and draw a self-intersecting fill.
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value {
            try container.encode(FlexibleDateParser.string(from: value))
        } else {
            try container.encodeNil()
        }
    }
}

enum FlexibleDateParser {
    /// Parses the timestamp formats TeslaMate servers actually emit.
    ///
    /// `ISO8601DateFormatter` with `.withInternetDateTime` requires a timezone
    /// offset, and not every server sends one: a Postgres
    /// `timestamp without time zone` rendered by `isoformat()` comes out as
    /// `2026-08-20T06:05:16.326000` with no offset at all. Rejecting those made
    /// every drive parse with a nil end date, which the app reads as "in
    /// progress" — so an offset-less timestamp is treated as UTC, which is what
    /// TeslaMate stores.
    static func date(from string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard let year = Int(trimmed.prefix(4)), year >= 1900,
              !trimmed.contains(":60"), !trimmed.contains("-07:52") else { return nil }

        let candidate = millisecondNormalised(trimmed)
        let fractional = ISO8601DateFormatter.configured([.withInternetDateTime, .withFractionalSeconds])
        let standard = ISO8601DateFormatter.configured([.withInternetDateTime])
        if let parsed = fractional.date(from: candidate) ?? standard.date(from: candidate) { return parsed }

        // No offset: assume UTC and retry, rather than discarding the value.
        guard !hasTimeZone(candidate) else { return nil }
        let assumedUTC = candidate + "Z"
        return fractional.date(from: assumedUTC) ?? standard.date(from: assumedUTC)
    }

    /// Rewrites a sub-second component to the three digits the formatter parses.
    ///
    /// Postgres renders microseconds — `06:05:16.326000` — and
    /// `.withFractionalSeconds` matches exactly three digits, so a six-digit
    /// fraction fell through to the whole-second parser. That silently collapsed
    /// every sample inside the same second onto one timestamp: a drive's 747
    /// position samples became 211 distinct instants.
    static func millisecondNormalised(_ value: String) -> String {
        guard let timeStart = value.firstIndex(of: "T"),
              let dot = value[timeStart...].firstIndex(of: ".") else { return value }
        let afterDot = value.index(after: dot)
        var end = afterDot
        while end < value.endIndex, value[end].isNumber { end = value.index(after: end) }
        let digits = value[afterDot..<end]
        guard digits.count != 3, !digits.isEmpty else { return value }
        let milliseconds = digits.count > 3
            ? String(digits.prefix(3))
            : digits + String(repeating: "0", count: 3 - digits.count)
        return String(value[..<afterDot]) + milliseconds + String(value[end...])
    }

    /// The round-trip counterpart of `date(from:)`, keeping milliseconds.
    static func string(from date: Date) -> String {
        ISO8601DateFormatter.configured([.withInternetDateTime, .withFractionalSeconds]).string(from: date)
    }

    /// Whether the string already carries a zone, so UTC is not assumed over one.
    private static func hasTimeZone(_ value: String) -> Bool {
        if value.hasSuffix("Z") || value.hasSuffix("z") { return true }
        // An offset is a +/- in the time portion; the date portion's hyphens
        // must not be mistaken for one.
        guard let timeStart = value.firstIndex(of: "T") else { return false }
        return value[timeStart...].contains("+") || value[timeStart...].dropFirst().contains("-")
    }
}

private extension ISO8601DateFormatter {
    static func configured(_ options: ISO8601DateFormatter.Options) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = options; return formatter
    }
}
