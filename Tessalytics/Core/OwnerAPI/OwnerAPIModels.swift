import Foundation

struct OwnerAPIEnvelope<Value: Decodable & Sendable>: Decodable, Sendable {
    let response: Value
}

struct OwnerVehicle: Decodable, Hashable, Identifiable, Sendable {
    let id: Int64
    let vehicleId: Int64?
    let vin: String
    let displayName: String?
    let state: String?
}

/// One entry from `/api/1/products`, which is a mixed list.
///
/// The account's cars come back alongside its Powerwalls, solar and energy
/// sites, and none of those carry a VIN or a vehicle id. Every field is optional
/// because the list is heterogeneous by design: decoding it into a type that
/// demanded a VIN would fail the whole request for an owner who also has a
/// battery on the wall.
struct OwnerProduct: Decodable, Sendable {
    let id: Int64?
    let vehicleId: Int64?
    let vin: String?
    let displayName: String?
    let state: String?

    /// The same product as a controllable car, or nil if it is not one.
    var vehicle: OwnerVehicle? {
        guard let id, let vin = vin?.trimmingCharacters(in: .whitespacesAndNewlines), !vin.isEmpty else {
            return nil
        }
        return OwnerVehicle(id: id, vehicleId: vehicleId, vin: vin, displayName: displayName, state: state)
    }
}

struct OwnerVehicleData: Decodable, Sendable {
    let id: Int64?
    let vin: String?
    let displayName: String?
    let state: String?
    let driveState: OwnerDriveState?
    let climateState: OwnerClimateState?
    let chargeState: OwnerChargeState?
    let vehicleState: OwnerVehicleState?
    let vehicleConfig: OwnerVehicleConfig?
    let guiSettings: OwnerGUISettings?

    var tessalyticsStatus: VehicleStatus {
        let windows = [vehicleState?.fd, vehicleState?.fp, vehicleState?.rd, vehicleState?.rp]
            .compactMap { $0 }.contains { $0 != 0 }
        let doors = [vehicleState?.df, vehicleState?.dr, vehicleState?.pf, vehicleState?.pr]
            .compactMap { $0 }.contains { $0 != 0 }
        let coordinate = driveState.flatMap { state -> CoordinateDTO? in
            guard let latitude = state.latitude, let longitude = state.longitude else { return nil }
            return CoordinateDTO(latitude: latitude, longitude: longitude)
        }
        let chargingState = chargeState?.chargingState
        let pluggedIn = chargingState?.lowercased() != "disconnected" && chargingState != nil
        let updateStatus = vehicleState?.softwareUpdate?.status?.lowercased()

        return VehicleStatus(
            displayName: displayName,
            state: state,
            stateSince: nil,
            odometer: vehicleState?.odometer,
            carStatus: CarStatusDTO(
                healthy: state != "offline",
                locked: vehicleState?.locked,
                sentryMode: vehicleState?.sentryMode,
                windowsOpen: windows,
                doorsOpen: doors,
                trunkOpen: (vehicleState?.rt ?? 0) != 0,
                frunkOpen: (vehicleState?.ft ?? 0) != 0
            ),
            carDetails: CarDetailsDTO(
                model: vehicleConfig?.carType,
                trimBadging: vehicleConfig?.trimBadging,
                efficiency: nil
            ),
            carGeodata: CarGeodataDTO(geofence: coordinate == nil ? nil : "Live location", location: coordinate),
            carVersions: CarVersionsDTO(
                version: vehicleState?.carVersion,
                updateAvailable: updateStatus == "available",
                updateVersion: vehicleState?.softwareUpdate?.version
            ),
            drivingDetails: DrivingDetailsDTO(
                shiftState: driveState?.shiftState,
                power: driveState?.power,
                speed: driveState?.speed,
                heading: driveState?.heading,
                elevation: nil
            ),
            climateDetails: ClimateDetailsDTO(
                isClimateOn: climateState?.isClimateOn,
                insideTemp: climateState?.insideTemp,
                outsideTemp: climateState?.outsideTemp,
                isPreconditioning: climateState?.isPreconditioning,
                climateKeeperMode: climateState?.climateKeeperMode
            ),
            batteryDetails: StatusBatteryDTO(
                estBatteryRange: chargeState?.estBatteryRange,
                ratedBatteryRange: chargeState?.batteryRange,
                idealBatteryRange: chargeState?.idealBatteryRange,
                batteryLevel: chargeState?.batteryLevel,
                usableBatteryLevel: chargeState?.usableBatteryLevel
            ),
            chargingDetails: StatusChargingDTO(
                pluggedIn: pluggedIn,
                chargingState: chargingState,
                chargeEnergyAdded: chargeState?.chargeEnergyAdded,
                chargeLimitSoc: chargeState?.chargeLimitSoc,
                chargePortDoorOpen: chargeState?.chargePortDoorOpen,
                chargerActualCurrent: chargeState?.chargerActualCurrent,
                chargerPhases: chargeState?.chargerPhases,
                chargerPower: chargeState?.chargerPower,
                chargerVoltage: chargeState?.chargerVoltage,
                scheduledChargingStartTime: nil,
                timeToFullCharge: chargeState?.timeToFullCharge
            ),
            tpmsDetails: TPMSDTO(
                tpmsPressureFl: vehicleState?.tpmsPressureFl,
                tpmsPressureFr: vehicleState?.tpmsPressureFr,
                tpmsPressureRl: vehicleState?.tpmsPressureRl,
                tpmsPressureRr: vehicleState?.tpmsPressureRr
            )
        )
    }

    var tessalyticsUnits: UnitsDTO {
        let distance = guiSettings?.guiDistanceUnits?.lowercased().contains("mi") == true ? "mi" : "km"
        let temperature = guiSettings?.guiTemperatureUnits?.uppercased().contains("F") == true ? "F" : "C"
        return UnitsDTO(unitOfLength: distance, unitOfPressure: "bar", unitOfTemperature: temperature)
    }
}

struct OwnerDriveState: Decodable, Sendable {
    let latitude: Double?
    let longitude: Double?
    let heading: Double?
    let power: Double?
    let shiftState: String?
    let speed: Double?
}

struct OwnerClimateState: Decodable, Sendable {
    let insideTemp: Double?
    let outsideTemp: Double?
    let isClimateOn: Bool?
    let isPreconditioning: Bool?
    let climateKeeperMode: String?
}

struct OwnerChargeState: Decodable, Sendable {
    let batteryLevel: Int?
    let usableBatteryLevel: Int?
    let batteryRange: Double?
    let estBatteryRange: Double?
    let idealBatteryRange: Double?
    let chargingState: String?
    let chargeEnergyAdded: Double?
    let chargeLimitSoc: Int?
    let chargePortDoorOpen: Bool?
    let chargerActualCurrent: Double?
    let chargerPhases: Int?
    let chargerPower: Double?
    let chargerVoltage: Int?
    let timeToFullCharge: Double?
}

struct OwnerVehicleState: Decodable, Sendable {
    let locked: Bool?
    let sentryMode: Bool?
    let odometer: Double?
    let carVersion: String?
    let df: Int?
    let dr: Int?
    let pf: Int?
    let pr: Int?
    let fd: Int?
    let fp: Int?
    let rd: Int?
    let rp: Int?
    let ft: Int?
    let rt: Int?
    let tpmsPressureFl: Double?
    let tpmsPressureFr: Double?
    let tpmsPressureRl: Double?
    let tpmsPressureRr: Double?
    let softwareUpdate: OwnerSoftwareUpdate?
}

struct OwnerSoftwareUpdate: Decodable, Sendable {
    let status: String?
    let version: String?
}

struct OwnerVehicleConfig: Decodable, Sendable {
    let carType: String?
    let trimBadging: String?
}

struct OwnerGUISettings: Decodable, Sendable {
    let guiDistanceUnits: String?
    let guiTemperatureUnits: String?
}

struct OwnerTokenResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
}

struct OwnerCommandResponse: Decodable, Sendable {
    let result: Bool
    let reason: String?
}
