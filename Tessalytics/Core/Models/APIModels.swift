import Foundation

struct Envelope<T: Decodable & Sendable>: Decodable, Sendable { let data: T }

struct UnitsDTO: Decodable, Hashable, Sendable {
    let unitOfLength: String?
    let unitOfPressure: String?
    let unitOfTemperature: String?
}

extension UnitsDTO {
    func length(_ value: Double?) -> Measurement<UnitLength>? {
        guard let value else { return nil }
        return Measurement(value: value, unit: unitOfLength?.lowercased() == "mi" ? .miles : .kilometers)
    }
    func speed(_ value: Double?) -> Measurement<UnitSpeed>? {
        guard let value else { return nil }
        return Measurement(value: value, unit: unitOfLength?.lowercased() == "mi" ? .milesPerHour : .kilometersPerHour)
    }
    func temperature(_ value: Double?) -> Measurement<UnitTemperature>? {
        guard let value else { return nil }
        return Measurement(value: value, unit: unitOfTemperature?.uppercased() == "F" ? .fahrenheit : .celsius)
    }
    func pressure(_ value: Double?) -> Measurement<UnitPressure>? {
        guard let value else { return nil }
        return Measurement(value: value, unit: unitOfPressure?.lowercased() == "psi" ? .poundsForcePerSquareInch : .bars)
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
struct CarDetailsDTO: Decodable, Sendable { let model: String?; let trimBadging: String?; let efficiency: Double? }
struct TeslaMateStatsDTO: Decodable, Sendable { let totalCharges: Int?; let totalDrives: Int?; let totalUpdates: Int? }

struct StatusDataDTO: Decodable, Sendable { let car: CarReferenceDTO; let status: VehicleStatus; let units: UnitsDTO? }
struct VehicleStatus: Decodable, Sendable {
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
struct CarStatusDTO: Decodable, Sendable {
    let healthy: Bool?; let locked: Bool?; let sentryMode: Bool?; let windowsOpen: Bool?; let doorsOpen: Bool?
    let trunkOpen: Bool?; let frunkOpen: Bool?
}
struct CarGeodataDTO: Decodable, Sendable { let geofence: String?; let location: CoordinateDTO? }
struct CoordinateDTO: Codable, Hashable, Sendable { let latitude: Double; let longitude: Double }
struct CarVersionsDTO: Decodable, Sendable { let version: String?; let updateAvailable: Bool?; let updateVersion: String? }
struct DrivingDetailsDTO: Decodable, Sendable { let shiftState: String?; let power: Double?; let speed: Double?; let heading: Double?; let elevation: Double? }
struct ClimateDetailsDTO: Decodable, Sendable { let isClimateOn: Bool?; let insideTemp: Double?; let outsideTemp: Double?; let isPreconditioning: Bool?; let climateKeeperMode: String? }
struct StatusBatteryDTO: Decodable, Sendable { let estBatteryRange: Double?; let ratedBatteryRange: Double?; let idealBatteryRange: Double?; let batteryLevel: Int?; let usableBatteryLevel: Int? }
struct StatusChargingDTO: Decodable, Sendable {
    let pluggedIn: Bool?; let chargingState: String?; let chargeEnergyAdded: Double?; let chargeLimitSoc: Int?
    let chargePortDoorOpen: Bool?; let chargerActualCurrent: Double?; let chargerPhases: Int?; let chargerPower: Double?
    let chargerVoltage: Int?; let scheduledChargingStartTime: FlexibleDate?; let timeToFullCharge: Double?
}
struct TPMSDTO: Decodable, Sendable {
    let tpmsPressureFl: Double?; let tpmsPressureFr: Double?; let tpmsPressureRl: Double?; let tpmsPressureRr: Double?
}

struct DrivesDataDTO: Decodable, Sendable { let car: CarReferenceDTO; let drives: [DriveSummaryDTO]; let units: UnitsDTO? }
struct DriveSummaryDTO: Codable, Identifiable, Sendable {
    let driveId: Int; let startDate: FlexibleDate?; let endDate: FlexibleDate?
    let startAddress: String?; let endAddress: String?; let odometerDetails: OdometerDetailsDTO?
    let durationMin: Int?; let durationStr: String?; let speedMax: Double?; let speedAvg: Double?
    let powerMax: Double?; let powerMin: Double?; let outsideTempAvg: Double?; let insideTempAvg: Double?
    let energyConsumedNet: Double?; let consumptionNet: Double?
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
struct ChargeSummaryDTO: Codable, Identifiable, Sendable {
    let chargeId: Int; let startDate: FlexibleDate?; let endDate: FlexibleDate?; let address: String?
    let chargeEnergyAdded: Double?; let chargeEnergyUsed: Double?; let cost: Double?; let durationMin: Int?
    let durationStr: String?; let outsideTempAvg: Double?; let odometer: Double?; let latitude: Double?; let longitude: Double?
    var id: Int { chargeId }
}
struct ChargeDataDTO: Decodable, Sendable { let car: CarReferenceDTO; let charge: ChargeDetailDTO; let units: UnitsDTO? }
struct ChargeDetailDTO: Codable, Identifiable, Sendable {
    let chargeId: Int; let startDate: FlexibleDate?; let endDate: FlexibleDate?; let isCharging: Bool?
    let address: String?; let chargeEnergyAdded: Double?; let chargeEnergyUsed: Double?; let cost: Double?
    let durationMin: Int?; let outsideTempAvg: Double?; let chargeDetails: [ChargePointDTO]
    var id: Int { chargeId }
}
struct ChargePointDTO: Codable, Identifiable, Sendable {
    let detailId: Int; let date: FlexibleDate?; let batteryLevel: Int?; let usableBatteryLevel: Int?
    let chargeEnergyAdded: Double?; let chargerDetails: ChargerDetailsDTO?; let outsideTemp: Double?
    let connChargeCable: String?; let fastChargerInfo: FastChargerInfoDTO?
    var id: Int { detailId }
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
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value { try container.encode(ISO8601DateFormatter().string(from: value)) } else { try container.encodeNil() }
    }
}

enum FlexibleDateParser {
    static func date(from string: String) -> Date? {
        guard let year = Int(string.prefix(4)), year >= 1900,
              !string.contains(":60"), !string.contains("-07:52") else { return nil }
        let fractional = ISO8601DateFormatter.configured([.withInternetDateTime, .withFractionalSeconds])
        let standard = ISO8601DateFormatter.configured([.withInternetDateTime])
        return fractional.date(from: string) ?? standard.date(from: string)
    }
}

private extension ISO8601DateFormatter {
    static func configured(_ options: ISO8601DateFormatter.Options) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = options; return formatter
    }
}
