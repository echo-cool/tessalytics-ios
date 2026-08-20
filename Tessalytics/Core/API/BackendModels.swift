import Foundation

/// Wire types for Tessalytics Backend, and their mapping onto the app's models.
///
/// The backend nests related fields (`battery`, `range`, `security`) rather than
/// flattening them, and reports a missing reading as `null` rather than `false`
/// or `0`. Every property here is therefore optional, and the mappings below
/// preserve the distinction instead of substituting defaults — that is the whole
/// reason for moving off TeslaMateApi.

// MARK: - Envelope

struct BackendEnvelope<T: Decodable & Sendable>: Decodable, Sendable {
    let data: T
    let meta: BackendMeta?
}

struct BackendMeta: Decodable, Sendable {
    let generatedAt: String?
    let source: String?
    let units: BackendUnits?
    let page: BackendPage?
    let freshness: BackendFreshness?
}

struct BackendUnits: Decodable, Sendable {
    let length: String?
    let temperature: String?
    let pressure: String?
    let range: String?

    var unitsDTO: UnitsDTO {
        UnitsDTO(unitOfLength: length, unitOfPressure: pressure, unitOfTemperature: temperature)
    }
}

struct BackendPage: Decodable, Sendable {
    let limit: Int?
    let returned: Int?
    let hasMore: Bool?
    let next: String?
}

struct BackendFreshness: Decodable, Sendable {
    let observedAt: String?
    let ageSeconds: Double?
    let stale: Bool?
}

struct BackendProblemDTO: Decodable, Sendable {
    let type: String?
    let title: String?
    let status: Int?
    let detail: String?
}

struct BackendPingDTO: Decodable, Sendable { let message: String? }

// MARK: - Discovery

struct BackendDiscoveryDTO: Decodable, Sendable { let data: BackendCapabilities }

struct BackendCapabilities: Decodable, Sendable {
    let service: String?
    let version: String?
    let capabilities: Details?

    struct Details: Decodable, Sendable {
        let resources: [String]?
        let analytics: Analytics?
        let actions: Actions?
        let liveState: LiveState?
        let units: [String]?

        struct Analytics: Decodable, Sendable { let queries: Int? }
        struct Actions: Decodable, Sendable { let enabled: Bool?; let upstream: String? }
        struct LiveState: Decodable, Sendable { let enabled: Bool?; let connected: Bool? }
    }

    /// Whether vehicle commands can be sent through this deployment.
    var supportsActions: Bool { capabilities?.actions?.enabled ?? false }
    /// Whether lock, sentry and openings will have real values.
    var supportsLiveState: Bool { capabilities?.liveState?.enabled ?? false }
    var analyticsQueryCount: Int { capabilities?.analytics?.queries ?? 0 }
}

// MARK: - Vehicles

struct BackendVehicleListDTO: Decodable, Sendable { let vehicles: [BackendVehicle] }
struct BackendVehicleWrapperDTO: Decodable, Sendable { let vehicle: BackendVehicle }

struct BackendVehicle: Decodable, Sendable {
    let id: Int
    let name: String?
    let model: String?
    let modelName: String?
    let trim: String?
    let vin: String?
    let ratedConsumption: Double?
    let coverage: Coverage?

    struct Coverage: Decodable, Sendable {
        let drives: Int?
        let charges: Int?
        let updates: Int?
        let positions: Int?
        let odometer: Double?
    }

    var carDTO: CarDTO {
        CarDTO(
            carId: id,
            name: name,
            carDetails: CarDetailsDTO(
                model: model,
                trimBadging: trim,
                // The app expects kWh per unit distance; the backend reports Wh.
                efficiency: ratedConsumption.map { $0 / 1000 }
            ),
            teslamateStats: TeslaMateStatsDTO(
                totalCharges: coverage?.charges,
                totalDrives: coverage?.drives,
                totalUpdates: coverage?.updates
            )
        )
    }
}

// MARK: - Live state

struct BackendStateWrapperDTO: Decodable, Sendable { let state: BackendState }

struct BackendState: Decodable, Sendable {
    let vehicleId: Int?
    let state: String?
    let stateSince: String?
    let name: String?
    let healthy: Bool?
    let location: Location?
    let battery: Battery?
    let climate: Climate?
    let driving: Driving?
    let charging: Charging?
    let security: Security?
    let tyres: Tyres?
    let software: Software?

    struct Location: Decodable, Sendable {
        let latitude: Double?
        let longitude: Double?
        let geofence: String?
        let heading: Double?
        let elevation: Double?
    }

    struct Battery: Decodable, Sendable {
        let level: Int?
        let usableLevel: Int?
        let buffer: Int?
        let range: Double?
        let rangeRated: Double?
        let rangeIdeal: Double?
        let rangeEstimated: Double?
    }

    struct Climate: Decodable, Sendable {
        let insideTemperature: Double?
        let outsideTemperature: Double?
        let isOn: Bool?
        let isPreconditioning: Bool?
        let keeperMode: String?
    }

    struct Driving: Decodable, Sendable {
        let shiftState: String?
        let speed: Double?
        let power: Double?
        let odometer: Double?
        let isUserPresent: Bool?
    }

    struct Charging: Decodable, Sendable {
        let pluggedIn: Bool?
        let state: String?
        let energyAdded: Double?
        let chargeLimit: Double?
        let power: Double?
        let voltage: Double?
        let current: Double?
        let portOpen: Bool?
        let hoursToFull: Double?
    }

    struct Security: Decodable, Sendable {
        let locked: Bool?
        let sentryMode: Bool?
        let windowsOpen: Bool?
        let doorsOpen: Bool?
        let trunkOpen: Bool?
        let frunkOpen: Bool?
    }

    struct Tyres: Decodable, Sendable {
        let frontLeft: Tyre?
        let frontRight: Tyre?
        let rearLeft: Tyre?
        let rearRight: Tyre?

        struct Tyre: Decodable, Sendable {
            let pressure: Double?
            let warning: Bool?
        }
    }

    struct Software: Decodable, Sendable {
        let version: String?
        let installedAt: String?
    }

    /// Maps onto the app's status model.
    ///
    /// Nils are carried straight through. The app already treats an absent lock
    /// reading as unknown rather than "unlocked", so the backend's honesty and
    /// the app's caution line up exactly.
    var vehicleStatus: VehicleStatus {
        VehicleStatus(
            displayName: name,
            state: state,
            stateSince: stateSince.flatMap { FlexibleDate(FlexibleDateParser.date(from: $0)) },
            odometer: driving?.odometer,
            carStatus: CarStatusDTO(
                healthy: healthy,
                locked: security?.locked,
                sentryMode: security?.sentryMode,
                windowsOpen: security?.windowsOpen,
                doorsOpen: security?.doorsOpen,
                trunkOpen: security?.trunkOpen,
                frunkOpen: security?.frunkOpen
            ),
            carDetails: nil,
            carGeodata: CarGeodataDTO(
                geofence: location?.geofence,
                location: location.flatMap { spot in
                    guard let latitude = spot.latitude, let longitude = spot.longitude else { return nil }
                    return CoordinateDTO(latitude: latitude, longitude: longitude)
                }
            ),
            carVersions: CarVersionsDTO(version: software?.version, updateAvailable: nil, updateVersion: nil),
            drivingDetails: DrivingDetailsDTO(
                shiftState: driving?.shiftState,
                power: driving?.power,
                speed: driving?.speed,
                heading: location?.heading,
                elevation: location?.elevation
            ),
            climateDetails: ClimateDetailsDTO(
                isClimateOn: climate?.isOn,
                insideTemp: climate?.insideTemperature,
                outsideTemp: climate?.outsideTemperature,
                isPreconditioning: climate?.isPreconditioning,
                climateKeeperMode: climate?.keeperMode
            ),
            batteryDetails: StatusBatteryDTO(
                // The backend already resolved the owner's preferred range, so
                // `range` is the one to show; the specific estimates follow.
                estBatteryRange: battery?.rangeEstimated ?? battery?.range,
                ratedBatteryRange: battery?.rangeRated,
                idealBatteryRange: battery?.rangeIdeal,
                batteryLevel: battery?.level,
                usableBatteryLevel: battery?.usableLevel
            ),
            chargingDetails: StatusChargingDTO(
                pluggedIn: charging?.pluggedIn,
                chargingState: charging?.state,
                chargeEnergyAdded: charging?.energyAdded,
                chargeLimitSoc: charging?.chargeLimit.map { Int($0.rounded()) },
                chargePortDoorOpen: charging?.portOpen,
                chargerActualCurrent: charging?.current,
                chargerPhases: nil,
                chargerPower: charging?.power,
                chargerVoltage: charging?.voltage.map { Int($0.rounded()) },
                scheduledChargingStartTime: nil,
                timeToFullCharge: charging?.hoursToFull
            ),
            tpmsDetails: TPMSDTO(
                tpmsPressureFl: tyres?.frontLeft?.pressure,
                tpmsPressureFr: tyres?.frontRight?.pressure,
                tpmsPressureRl: tyres?.rearLeft?.pressure,
                tpmsPressureRr: tyres?.rearRight?.pressure
            )
        )
    }
}

// MARK: - Drives

struct BackendDriveListDTO: Decodable, Sendable { let drives: [BackendDrive] }
struct BackendDriveWrapperDTO: Decodable, Sendable { let drive: BackendDrive }

struct BackendDrive: Decodable, Sendable {
    let id: Int
    let startDate: String?
    let endDate: String?
    let durationMinutes: Int?
    let distance: Double?
    let odometer: Window?
    let speed: SpeedBlock?
    let power: PowerBlock?
    let elevation: ElevationBlock?
    let temperature: TemperatureBlock?
    let battery: BatteryBlock?
    let range: RangeBlock?
    let energy: EnergyBlock?
    let start: Endpoint?
    let end: Endpoint?
    let samples: [BackendPosition]?

    struct Window: Decodable, Sendable { let start: Double?; let end: Double? }
    struct SpeedBlock: Decodable, Sendable { let max: Double?; let average: Double? }
    struct PowerBlock: Decodable, Sendable { let max: Double?; let min: Double? }
    struct ElevationBlock: Decodable, Sendable { let ascent: Double?; let descent: Double? }
    struct TemperatureBlock: Decodable, Sendable { let outsideAverage: Double?; let insideAverage: Double? }
    struct BatteryBlock: Decodable, Sendable {
        let startLevel: Int?
        let endLevel: Int?
        let startUsableLevel: Int?
        let endUsableLevel: Int?
    }
    struct RangeBlock: Decodable, Sendable { let start: Double?; let end: Double?; let consumed: Double? }
    /// Inferred by the server from range consumed and the car's efficiency;
    /// TeslaMate stores no energy figure per drive.
    struct EnergyBlock: Decodable, Sendable { let used: Double?; let consumption: Double? }
    struct Endpoint: Decodable, Sendable {
        let address: String?
        let geofence: String?
        let latitude: Double?
        let longitude: Double?
        /// A geofence name is what the owner called the place, so prefer it.
        var label: String? { geofence?.nilIfEmpty ?? address?.nilIfEmpty }

        var coordinate: CoordinateDTO? {
            guard let latitude, let longitude else { return nil }
            return CoordinateDTO(latitude: latitude, longitude: longitude)
        }
    }

    private var levels: LevelWindowDTO {
        LevelWindowDTO(
            startBatteryLevel: battery?.startLevel,
            endBatteryLevel: battery?.endLevel,
            startUsableBatteryLevel: battery?.startUsableLevel,
            endUsableBatteryLevel: battery?.endUsableLevel
        )
    }

    private var ratedRange: RangeWindowDTO {
        RangeWindowDTO(startRange: range?.start, endRange: range?.end, rangeDiff: range?.consumed)
    }

    var summaryDTO: DriveSummaryDTO {
        DriveSummaryDTO(
            driveId: id,
            startDate: FlexibleDate(FlexibleDateParser.date(from: startDate ?? "")),
            endDate: endDate.flatMap { FlexibleDate(FlexibleDateParser.date(from: $0)) },
            startAddress: start?.label,
            endAddress: end?.label,
            odometerDetails: OdometerDetailsDTO(
                odometerStart: odometer?.start,
                odometerEnd: odometer?.end,
                odometerDistance: distance
            ),
            durationMin: durationMinutes,
            durationStr: nil,
            speedMax: speed?.max,
            speedAvg: speed?.average,
            powerMax: power?.max,
            powerMin: power?.min,
            outsideTempAvg: temperature?.outsideAverage,
            insideTempAvg: temperature?.insideAverage,
            energyConsumedNet: energy?.used,
            consumptionNet: energy?.consumption,
            batteryDetails: levels,
            rangeRated: ratedRange,
            rangeIdeal: nil,
            startCoordinate: start?.coordinate,
            endCoordinate: end?.coordinate
        )
    }

    var detailDTO: DriveDetailDTO {
        DriveDetailDTO(
            driveId: id,
            startDate: FlexibleDate(FlexibleDateParser.date(from: startDate ?? "")),
            endDate: endDate.flatMap { FlexibleDate(FlexibleDateParser.date(from: $0)) },
            startAddress: start?.label,
            endAddress: end?.label,
            odometerDetails: OdometerDetailsDTO(
                odometerStart: odometer?.start,
                odometerEnd: odometer?.end,
                odometerDistance: distance
            ),
            durationMin: durationMinutes,
            durationStr: nil,
            speedMax: speed?.max,
            speedAvg: speed?.average,
            energyConsumedNet: energy?.used,
            consumptionNet: energy?.consumption,
            driveDetails: (samples ?? []).enumerated().compactMap { index, sample in
                sample.drivePointDTO(id: id * 100_000 + index)
            }
        )
    }
}

struct BackendPosition: Decodable, Sendable {
    let date: String?
    let latitude: Double?
    let longitude: Double?
    let speed: Double?
    let power: Double?
    let odometer: Double?
    let elevation: Double?
    let batteryLevel: Int?
    let usableBatteryLevel: Int?
    let range: Double?
    let outsideTemperature: Double?
    let insideTemperature: Double?

    /// A sample without coordinates cannot be drawn on a route, so it is dropped
    /// rather than plotted at the origin.
    func drivePointDTO(id: Int) -> DrivePointDTO? {
        guard let latitude, let longitude else { return nil }
        return DrivePointDTO(
            detailId: id,
            date: date.flatMap { FlexibleDate(FlexibleDateParser.date(from: $0)) },
            latitude: latitude,
            longitude: longitude,
            speed: speed,
            power: power,
            odometer: odometer,
            batteryLevel: batteryLevel,
            elevation: elevation,
            climateInfo: DriveClimateDTO(insideTemp: insideTemperature, outsideTemp: outsideTemperature)
        )
    }
}

// MARK: - Charges

struct BackendChargeListDTO: Decodable, Sendable { let charges: [BackendCharge] }
struct BackendChargeWrapperDTO: Decodable, Sendable { let charge: BackendCharge }
struct BackendOptionalChargeDTO: Decodable, Sendable { let charge: BackendCharge? }

struct BackendCharge: Decodable, Sendable {
    let id: Int
    let startDate: String?
    let endDate: String?
    let durationMinutes: Int?
    let energy: EnergyBlock?
    let cost: CostBlock?
    let power: PowerBlock?
    let battery: BatteryBlock?
    let range: RangeBlock?
    let temperature: TemperatureBlock?
    let location: LocationBlock?
    let samples: [BackendChargeSample]?

    struct EnergyBlock: Decodable, Sendable { let added: Double?; let used: Double?; let efficiency: Double? }
    struct CostBlock: Decodable, Sendable { let total: Double?; let perKwh: Double? }
    struct PowerBlock: Decodable, Sendable { let average: Double? }
    struct BatteryBlock: Decodable, Sendable { let startLevel: Int?; let endLevel: Int? }
    struct RangeBlock: Decodable, Sendable { let start: Double?; let end: Double?; let added: Double? }
    struct TemperatureBlock: Decodable, Sendable { let outsideAverage: Double? }
    struct LocationBlock: Decodable, Sendable {
        let address: String?
        let geofence: String?
        let latitude: Double?
        let longitude: Double?
        let odometer: Double?
        var label: String? { geofence?.nilIfEmpty ?? address?.nilIfEmpty }
    }

    var summaryDTO: ChargeSummaryDTO {
        ChargeSummaryDTO(
            chargeId: id,
            startDate: FlexibleDate(FlexibleDateParser.date(from: startDate ?? "")),
            endDate: endDate.flatMap { FlexibleDate(FlexibleDateParser.date(from: $0)) },
            address: location?.label,
            chargeEnergyAdded: energy?.added,
            chargeEnergyUsed: energy?.used,
            cost: cost?.total,
            durationMin: durationMinutes,
            durationStr: nil,
            outsideTempAvg: temperature?.outsideAverage,
            odometer: location?.odometer,
            latitude: location?.latitude,
            longitude: location?.longitude,
            batteryDetails: LevelWindowDTO(
                startBatteryLevel: battery?.startLevel,
                endBatteryLevel: battery?.endLevel,
                startUsableBatteryLevel: nil,
                endUsableBatteryLevel: nil
            ),
            rangeRated: RangeWindowDTO(startRange: range?.start, endRange: range?.end, rangeDiff: range?.added),
            rangeIdeal: nil
        )
    }

    var detailDTO: ChargeDetailDTO {
        ChargeDetailDTO(
            chargeId: id,
            startDate: FlexibleDate(FlexibleDateParser.date(from: startDate ?? "")),
            endDate: endDate.flatMap { FlexibleDate(FlexibleDateParser.date(from: $0)) },
            isCharging: endDate == nil,
            address: location?.label,
            chargeEnergyAdded: energy?.added,
            chargeEnergyUsed: energy?.used,
            cost: cost?.total,
            durationMin: durationMinutes,
            outsideTempAvg: temperature?.outsideAverage,
            chargeDetails: (samples ?? []).enumerated().map { index, sample in
                sample.chargePointDTO(id: id * 100_000 + index)
            },
            odometer: location?.odometer,
            latitude: location?.latitude,
            longitude: location?.longitude,
            batteryDetails: LevelWindowDTO(
                startBatteryLevel: battery?.startLevel,
                endBatteryLevel: battery?.endLevel,
                startUsableBatteryLevel: nil,
                endUsableBatteryLevel: nil
            ),
            rangeRated: RangeWindowDTO(startRange: range?.start, endRange: range?.end, rangeDiff: range?.added)
        )
    }
}

struct BackendChargeSample: Decodable, Sendable {
    let date: String?
    let batteryLevel: Int?
    let usableBatteryLevel: Int?
    let energyAdded: Double?
    let power: Double?
    let voltage: Double?
    let current: Double?
    let phases: Int?
    let range: Double?
    let outsideTemperature: Double?
    let charger: Charger?

    struct Charger: Decodable, Sendable {
        let fast: Bool?
        let brand: String?
        let type: String?
        let cable: String?
    }

    func chargePointDTO(id: Int) -> ChargePointDTO {
        ChargePointDTO(
            detailId: id,
            date: date.flatMap { FlexibleDate(FlexibleDateParser.date(from: $0)) },
            batteryLevel: batteryLevel,
            usableBatteryLevel: usableBatteryLevel,
            chargeEnergyAdded: energyAdded,
            chargerDetails: ChargerDetailsDTO(
                chargerActualCurrent: current,
                chargerPhases: phases,
                chargerPilotCurrent: nil,
                chargerPower: power,
                chargerVoltage: voltage
            ),
            outsideTemp: outsideTemperature,
            connChargeCable: charger?.cable,
            fastChargerInfo: FastChargerInfoDTO(
                fastChargerPresent: charger?.fast,
                fastChargerBrand: charger?.brand,
                fastChargerType: charger?.type
            ),
            batteryInfo: ChargeBatteryInfoDTO(
                idealBatteryRange: nil,
                ratedBatteryRange: range,
                batteryHeater: nil,
                batteryHeaterOn: nil
            )
        )
    }
}

// MARK: - Battery health

struct BackendBatteryWrapperDTO: Decodable, Sendable { let battery: BackendBattery }

struct BackendBattery: Decodable, Sendable {
    let capacity: Block?
    let range: Block?
    let ratedConsumption: Double?
    let observations: Int?

    struct Block: Decodable, Sendable {
        let whenNew: Double?
        let now: Double?
        let lost: Double?
        let retained: Double?
    }

    func healthDTO(units: BackendUnits?) -> BatteryHealthDTO {
        // The app's model wants kWh per 100 km, which is what its capacity
        // modelling divides by. The backend reports Wh per display unit.
        let perHundredKilometres: Double? = ratedConsumption.map { consumption in
            let perKilometre = units?.length?.lowercased() == "mi" ? consumption / 1.609_344 : consumption
            return perKilometre / 10
        }
        return BatteryHealthDTO(
            maxRange: range?.whenNew,
            currentRange: range?.now,
            maxCapacity: capacity?.whenNew,
            currentCapacity: capacity?.now,
            ratedEfficiency: perHundredKilometres,
            batteryHealthPercentage: (capacity?.retained ?? range?.retained).map { $0 * 100 }
        )
    }
}

// MARK: - Totals

struct BackendTotalsWrapperDTO: Decodable, Sendable { let totals: BackendTotals }

struct BackendTotals: Decodable, Sendable {
    let driving: Driving?
    let charging: Charging?
    let updates: Int?

    struct Driving: Decodable, Sendable {
        let drives: Int?
        let distanceLogged: Double?
        let odometer: Double?
        let distanceUnlogged: Double?
        let coverage: Double?
        let durationMinutes: Int?
        let firstDriveAt: String?
        let lastDriveAt: String?
    }

    struct Charging: Decodable, Sendable {
        let charges: Int?
        let energyAdded: Double?
        let energyUsed: Double?
        let efficiency: Double?
        let cycles: Double?
        let durationMinutes: Int?
        let costTotal: Double?
        let costPerKwh: Double?
        let pricedCharges: Int?
    }
}

// MARK: - Updates and settings

struct BackendUpdateListDTO: Decodable, Sendable { let updates: [BackendUpdate] }

struct BackendUpdate: Decodable, Sendable {
    let id: Int
    let version: String?
    let versionFull: String?
    let startDate: String?
    let endDate: String?

    var updateDTO: FirmwareUpdateDTO {
        FirmwareUpdateDTO(
            updateId: id,
            startDate: startDate.flatMap { FlexibleDate(FlexibleDateParser.date(from: $0)) },
            endDate: endDate.flatMap { FlexibleDate(FlexibleDateParser.date(from: $0)) },
            version: version ?? versionFull
        )
    }
}

struct BackendSettingsWrapperDTO: Decodable, Sendable { let settings: BackendSettings? }

struct BackendSettings: Decodable, Sendable {
    let units: BackendUnits?
    let language: String?
    let baseUrl: String?
    let grafanaUrl: String?
}

// MARK: - Track

/// Coordinate pairs rather than objects: the same path as keyed objects is
/// roughly four times the bytes for no added meaning.
struct BackendTrackDTO: Decodable, Sendable {
    struct Segment: Decodable, Sendable { let points: [[Double]] }
    let segments: [Segment]
}
