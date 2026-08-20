import Foundation
import SwiftData

enum DemoExperience {
    static let profileID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let carID = 1
    static let units = UnitsDTO(unitOfLength: "mi", unitOfPressure: "psi", unitOfTemperature: "C")

    static var profile: ServerProfile {
        ServerProfile(
            id: profileID,
            name: "Demo data",
            baseURL: URL(string: "https://demo.invalid")!,
            authenticationMethod: .none,
            allowsLocalHTTP: false,
            isSelected: true
        )
    }

    static var vehicle: Vehicle {
        Vehicle(
            serverID: profileID,
            id: carID,
            name: "Aurora",
            model: "Model Y",
            trim: "Long Range",
            totalDrives: 248,
            totalCharges: 61,
            totalUpdates: 12
        )
    }

    /// A sleeping car, shaped exactly like TeslaMateApi's real offline payload:
    /// zero-valued live telemetry and an empty charging state. Used to exercise
    /// the dashboard's history-first presentation.
    static func offlineStatus(now: Date = .now) -> VehicleStatus {
        let live = status(now: now)
        return VehicleStatus(
            displayName: live.displayName,
            state: "offline",
            stateSince: FlexibleDate(now.addingTimeInterval(-13_080)),
            odometer: live.odometer,
            carStatus: CarStatusDTO(
                healthy: true,
                locked: false,
                sentryMode: false,
                windowsOpen: false,
                doorsOpen: false,
                trunkOpen: false,
                frunkOpen: false
            ),
            carDetails: live.carDetails,
            carGeodata: live.carGeodata,
            carVersions: live.carVersions,
            drivingDetails: DrivingDetailsDTO(shiftState: "", power: 0, speed: 0, heading: 0, elevation: 0),
            climateDetails: live.climateDetails,
            batteryDetails: StatusBatteryDTO(
                estBatteryRange: 0,
                ratedBatteryRange: 229,
                idealBatteryRange: 245,
                batteryLevel: 78,
                usableBatteryLevel: 78
            ),
            chargingDetails: StatusChargingDTO(
                pluggedIn: false,
                chargingState: "",
                chargeEnergyAdded: 0,
                chargeLimitSoc: 0,
                chargePortDoorOpen: false,
                chargerActualCurrent: 0,
                chargerPhases: 0,
                chargerPower: 0,
                chargerVoltage: 0,
                scheduledChargingStartTime: nil,
                timeToFullCharge: 0
            ),
            tpmsDetails: TPMSDTO(tpmsPressureFl: 0, tpmsPressureFr: 0, tpmsPressureRl: 0, tpmsPressureRr: 0)
        )
    }

    /// A car mid-journey, for exercising and reviewing live mode.
    ///
    /// Live mode is the hardest part of the app to see: it needs a car that
    /// happens to be moving. A generated drive makes it reviewable on demand.
    static func drivingStatus(now: Date = .now) -> VehicleStatus {
        VehicleStatus(
            displayName: "Aurora",
            state: "driving",
            stateSince: FlexibleDate(now.addingTimeInterval(-1_020)),
            odometer: 18_654.2,
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
            carGeodata: CarGeodataDTO(
                geofence: nil,
                location: CoordinateDTO(latitude: 37.4062, longitude: -122.0723)
            ),
            carVersions: CarVersionsDTO(version: "2026.20.3", updateAvailable: false, updateVersion: nil),
            drivingDetails: DrivingDetailsDTO(shiftState: "D", power: 34, speed: 63, heading: 118, elevation: 42),
            climateDetails: ClimateDetailsDTO(
                isClimateOn: true,
                insideTemp: 21.5,
                outsideTemp: 18,
                isPreconditioning: false,
                climateKeeperMode: nil
            ),
            batteryDetails: StatusBatteryDTO(
                estBatteryRange: 214,
                ratedBatteryRange: 214,
                idealBatteryRange: 214,
                batteryLevel: 71,
                usableBatteryLevel: 70
            ),
            chargingDetails: nil,
            tpmsDetails: TPMSDTO(tpmsPressureFl: 42.1, tpmsPressureFr: 42.1, tpmsPressureRl: 42.4, tpmsPressureRr: 41.7)
        )
    }

    /// A plausible few minutes of readings, so the live charts have something to
    /// draw without waiting for a real journey.
    static func drivingTelemetry(now: Date = .now) -> LiveTelemetryBuffer {
        var buffer = LiveTelemetryBuffer()
        let samples = 150
        for index in 0..<samples {
            let progress = Double(index) / Double(samples - 1)
            let seconds = -Double(samples - index) * 4
            // Two accelerations with a slow section between them, which is what a
            // suburban run into a dual carriageway looks like.
            let speed = max(0, 34 + sin(progress * .pi * 2.4) * 28 + progress * 12)
            let power = speed > 3 ? (14 + sin(progress * .pi * 3.1) * 42) : -18
            buffer.append(
                date: now.addingTimeInterval(seconds),
                speed: speed,
                power: power,
                level: 78 - progress * 7,
                odometer: 18_642 + progress * 12.2,
                latitude: 37.3861 + progress * 0.020,
                longitude: -122.0839 + progress * 0.0116
            )
        }
        return buffer
    }

    static func status(now: Date = .now) -> VehicleStatus {
        VehicleStatus(
            displayName: "Aurora",
            state: "online",
            stateSince: FlexibleDate(now.addingTimeInterval(-1_800)),
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
            climateDetails: ClimateDetailsDTO(
                isClimateOn: false,
                insideTemp: 21.5,
                outsideTemp: 18,
                isPreconditioning: false,
                climateKeeperMode: "off"
            ),
            batteryDetails: StatusBatteryDTO(
                estBatteryRange: 238,
                ratedBatteryRange: 229,
                idealBatteryRange: 245,
                batteryLevel: 78,
                usableBatteryLevel: 77
            ),
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
            tpmsDetails: TPMSDTO(
                tpmsPressureFl: 42.1,
                tpmsPressureFr: 42.1,
                tpmsPressureRl: 43.5,
                tpmsPressureRr: 43.5
            )
        )
    }

    /// Health for a Model Y Long Range with a little age on it. Demo units are
    /// miles; rated efficiency is kWh per 100 km, as TeslaMateApi reports it.
    static let batteryHealth = BatteryHealthDTO(
        maxRange: 310,
        currentRange: 296,
        maxCapacity: 78.4,
        currentCapacity: 74.9,
        ratedEfficiency: 15.7,
        batteryHealthPercentage: 95.5
    )

    @MainActor
    static func seed(in context: ModelContext, now: Date = .now, offline: Bool = false) {
        clearPreviouslyGeneratedData(in: context)
        seedVehicle(in: context)
        seedSettings(in: context)
        seedDrives(in: context, now: now)
        seedTrack(in: context, now: now)
        seedCharges(in: context, now: now)
        seedSoftwareUpdates(in: context, now: now)
        seedBatteryHealth(in: context, now: now)
        seedSyncMarker(in: context, now: now)
        VehicleStatusCache(context: context).save(
            status: offline ? offlineStatus(now: now) : status(now: now),
            units: units,
            serverID: profileID,
            carID: carID,
            fetchedAt: now
        )
        try? context.save()
    }

    @MainActor
    private static func clearPreviouslyGeneratedData(in context: ModelContext) {
        let serverID = profileID.uuidString
        let drives = (try? context.fetch(FetchDescriptor<DriveRecord>(predicate: #Predicate { $0.serverID == serverID }))) ?? []
        let charges = (try? context.fetch(FetchDescriptor<ChargeRecord>(predicate: #Predicate { $0.serverID == serverID }))) ?? []
        let details = (try? context.fetch(FetchDescriptor<DetailCacheRecord>(predicate: #Predicate { $0.serverID == serverID }))) ?? []
        let updates = (try? context.fetch(FetchDescriptor<FirmwareUpdateRecord>(predicate: #Predicate { $0.serverID == serverID }))) ?? []
        let tracks = (try? context.fetch(FetchDescriptor<TrackRecord>(predicate: #Predicate { $0.serverID == serverID }))) ?? []
        drives.forEach(context.delete)
        charges.forEach(context.delete)
        details.forEach(context.delete)
        updates.forEach(context.delete)
        tracks.forEach(context.delete)
    }

    @MainActor
    private static func seedVehicle(in context: ModelContext) {
        let key = VehicleRecord.key(serverID: profileID, carID: carID)
        let descriptor = FetchDescriptor<VehicleRecord>(predicate: #Predicate { $0.cacheKey == key })
        if let record = try? context.fetch(descriptor).first {
            record.update(vehicle)
        } else {
            context.insert(VehicleRecord(vehicle: vehicle))
        }
    }

    @MainActor
    private static func seedSettings(in context: ModelContext) {
        let serverID = profileID.uuidString
        let descriptor = FetchDescriptor<GlobalSettingsRecord>(predicate: #Predicate { $0.serverID == serverID })
        guard (try? context.fetch(descriptor).first) == nil else { return }
        context.insert(GlobalSettingsRecord(serverID: profileID, units: units))
    }

    @MainActor
    private static func seedDrives(in context: ModelContext, now: Date) {
        let samples = DemoAnalyticsFactory.samples(now: now).drives
        for sample in samples {
            let fixture = driveFixture(sample, now: now)
            let key = DriveRecord.key(serverID: profileID, carID: carID, id: sample.id)
            let recordDescriptor = FetchDescriptor<DriveRecord>(predicate: #Predicate { $0.cacheKey == key })
            if (try? context.fetch(recordDescriptor).first) == nil {
                context.insert(DriveRecord(serverID: profileID, carID: carID, dto: fixture.summary))
            }
            let detailDescriptor = FetchDescriptor<DetailCacheRecord>(predicate: #Predicate { $0.cacheKey == key })
            if (try? context.fetch(detailDescriptor).first) == nil,
               let payload = try? JSONEncoder().encode(fixture.detail) {
                context.insert(
                    DetailCacheRecord(
                        key: key,
                        serverID: profileID,
                        carID: carID,
                        kind: "drive",
                        backendID: sample.id,
                        payload: payload,
                        completed: true
                    )
                )
            }
        }
    }

    /// A driven path for the places map.
    ///
    /// The real one is aggregated by the server from a million position rows;
    /// demo mode has no server, so it is assembled from the same synthetic drive
    /// routes the detail screens use. One segment per drive, which is what the
    /// map expects — a single polyline would draw the gaps between trips as
    /// travel.
    @MainActor
    private static func seedTrack(in context: ModelContext, now: Date) {
        let key = TrackRecord.key(serverID: profileID, carID: carID)
        let descriptor = FetchDescriptor<TrackRecord>(predicate: #Predicate { $0.cacheKey == key })
        guard (try? context.fetch(descriptor).first) == nil else { return }

        let segments = DemoAnalyticsFactory.samples(now: now).drives
            .map { driveFixture($0, now: now).detail.driveDetails.map(\.coordinate) }
            .filter { $0.count > 1 }
        guard !segments.isEmpty else { return }
        context.insert(
            TrackRecord(serverID: profileID, carID: carID, segments: segments, coversUntil: now)
        )
    }

    @MainActor
    private static func seedCharges(in context: ModelContext, now: Date) {
        let samples = DemoAnalyticsFactory.samples(now: now).charges
        for sample in samples {
            let fixture = chargeFixture(sample, now: now)
            let key = ChargeRecord.key(serverID: profileID, carID: carID, id: sample.id)
            let recordDescriptor = FetchDescriptor<ChargeRecord>(predicate: #Predicate { $0.cacheKey == key })
            if (try? context.fetch(recordDescriptor).first) == nil {
                context.insert(ChargeRecord(serverID: profileID, carID: carID, dto: fixture.summary))
            }
            let detailDescriptor = FetchDescriptor<DetailCacheRecord>(predicate: #Predicate { $0.cacheKey == key })
            if (try? context.fetch(detailDescriptor).first) == nil,
               let payload = try? JSONEncoder().encode(fixture.detail) {
                context.insert(
                    DetailCacheRecord(
                        key: key,
                        serverID: profileID,
                        carID: carID,
                        kind: "charge",
                        backendID: sample.id,
                        payload: payload,
                        completed: true
                    )
                )
            }
        }
    }

    @MainActor
    private static func seedBatteryHealth(in context: ModelContext, now: Date) {
        // A year of observations so the health trend has a shape.
        let calendar = Calendar.current
        for index in 0..<12 {
            guard let date = calendar.date(byAdding: .month, value: index - 11, to: now) else { continue }
            let fade = Double(11 - index) * 0.35
            let record = BatteryHealthRecord(
                serverID: profileID,
                carID: carID,
                dto: BatteryHealthDTO(
                    maxRange: batteryHealth.maxRange,
                    currentRange: (batteryHealth.currentRange ?? 296) + fade,
                    maxCapacity: batteryHealth.maxCapacity,
                    currentCapacity: (batteryHealth.currentCapacity ?? 74.9) + fade * 0.25,
                    ratedEfficiency: batteryHealth.ratedEfficiency,
                    batteryHealthPercentage: (batteryHealth.batteryHealthPercentage ?? 95.5) + fade * 0.12
                ),
                date: date
            )
            let key = record.cacheKey
            let descriptor = FetchDescriptor<BatteryHealthRecord>(predicate: #Predicate { $0.cacheKey == key })
            if (try? context.fetch(descriptor).first) == nil { context.insert(record) }
        }
    }

    /// Demo data is a complete synthetic history, so the fleet totals should not
    /// claim to be mid-sync.
    @MainActor
    private static func seedSyncMarker(in context: ModelContext, now: Date) {
        let key = FleetHistorySync.metadataKey(serverID: profileID, carID: carID)
        let descriptor = FetchDescriptor<SyncMetadataRecord>(predicate: #Predicate { $0.cacheKey == key })
        if let existing = try? context.fetch(descriptor).first {
            existing.lastSuccess = now
        } else {
            context.insert(SyncMetadataRecord(key: key, lastSuccess: now))
        }
    }

    @MainActor
    private static func seedSoftwareUpdates(in context: ModelContext, now: Date) {
        let versions = ["2026.20.3", "2026.14.7", "2026.8.4", "2025.44.25"]
        for (index, version) in versions.enumerated() {
            let id = 20_000 + index
            let key = "\(profileID.uuidString):\(carID):update:\(id)"
            let descriptor = FetchDescriptor<FirmwareUpdateRecord>(predicate: #Predicate { $0.cacheKey == key })
            guard (try? context.fetch(descriptor).first) == nil else { continue }
            let end = Calendar.current.date(byAdding: .month, value: -(index * 2), to: now) ?? now
            let start = end.addingTimeInterval(-2_700)
            context.insert(
                FirmwareUpdateRecord(
                    serverID: profileID,
                    carID: carID,
                    dto: FirmwareUpdateDTO(
                        updateId: id,
                        startDate: FlexibleDate(start),
                        endDate: FlexibleDate(end),
                        version: version
                    )
                )
            )
        }
    }

    /// Miles a demo car adds per day. Two months of history then spans a
    /// believable stretch of odometer instead of a few hundred metres.
    private static let demoMilesPerDay = 31.0
    private static let demoLatestOdometer = 18_642.0

    /// The odometer as it would have read then, from how long ago it was.
    private static func odometer(at date: Date, now: Date) -> Double {
        let days = max(now.timeIntervalSince(date) / 86_400, 0)
        return max(demoLatestOdometer - days * demoMilesPerDay, 500)
    }

    private static func driveFixture(_ sample: AnalyticsDriveSample, now: Date) -> (summary: DriveSummaryDTO, detail: DriveDetailDTO) {
        let startName = sample.id.isMultiple(of: 2) ? "Home" : "Office"
        let endName = sample.destination ?? "Downtown"
        let startCoordinate = coordinate(for: startName)
        let endCoordinate = coordinate(for: endName)
        let duration = sample.durationMinutes ?? 28
        let endDate = sample.date.addingTimeInterval(Double(duration) * 60)
        let distance = sample.distance ?? 12
        let odometerStart = odometer(at: sample.date, now: now) - distance
        let startLevel = 62 + abs(sample.id) % 24
        let endLevel = max(12, startLevel - Int(max(2, distance / 5)))
        let summary = DriveSummaryDTO(
            driveId: sample.id,
            startDate: FlexibleDate(sample.date),
            endDate: FlexibleDate(endDate),
            startAddress: startName,
            endAddress: endName,
            odometerDetails: OdometerDetailsDTO(
                odometerStart: odometerStart,
                odometerEnd: odometerStart + distance,
                odometerDistance: distance
            ),
            durationMin: duration,
            durationStr: "\(duration) min",
            speedMax: 52 + Double(abs(sample.id) % 18),
            speedAvg: max(18, distance / max(Double(duration) / 60, 0.25)),
            powerMax: 78,
            powerMin: -24,
            outsideTempAvg: 17 + Double(abs(sample.id) % 8),
            insideTempAvg: 21,
            energyConsumedNet: sample.energy,
            consumptionNet: sample.efficiency,
            batteryDetails: LevelWindowDTO(
                startBatteryLevel: startLevel,
                endBatteryLevel: endLevel,
                startUsableBatteryLevel: startLevel - 1,
                endUsableBatteryLevel: endLevel - 1
            ),
            rangeRated: RangeWindowDTO(
                startRange: ratedRange(atLevel: startLevel, odometer: odometerStart),
                endRange: ratedRange(atLevel: endLevel, odometer: odometerStart + distance),
                rangeDiff: nil
            ),
            rangeIdeal: nil,
            startCoordinate: startCoordinate,
            endCoordinate: endCoordinate
        )
        let points = (0..<7).map { index in
            let progress = Double(index) / 6
            let curve = sin(progress * .pi) * 0.012 * (sample.id.isMultiple(of: 2) ? 1 : -1)
            return DrivePointDTO(
                detailId: sample.id * 100 + index,
                date: FlexibleDate(sample.date.addingTimeInterval(Double(duration * 60) * progress)),
                latitude: startCoordinate.latitude + (endCoordinate.latitude - startCoordinate.latitude) * progress + curve,
                longitude: startCoordinate.longitude + (endCoordinate.longitude - startCoordinate.longitude) * progress - curve * 0.4,
                speed: index == 0 || index == 6 ? 0 : 24 + Double((index * 9 + abs(sample.id)) % 38),
                power: index == 0 || index == 6 ? 0 : 12 + Double(index * 8),
                odometer: odometerStart + distance * progress,
                batteryLevel: 78 - Int(progress * max(2, distance / 5)),
                elevation: 12 + Double(index * 5),
                climateInfo: DriveClimateDTO(insideTemp: 21, outsideTemp: summary.outsideTempAvg)
            )
        }
        let detail = DriveDetailDTO(
            driveId: sample.id,
            startDate: summary.startDate,
            endDate: summary.endDate,
            startAddress: summary.startAddress,
            endAddress: summary.endAddress,
            odometerDetails: summary.odometerDetails,
            durationMin: summary.durationMin,
            durationStr: summary.durationStr,
            speedMax: summary.speedMax,
            speedAvg: summary.speedAvg,
            energyConsumedNet: summary.energyConsumedNet,
            consumptionNet: summary.consumptionNet,
            driveDetails: points
        )
        return (summary, detail)
    }

    private static func chargeFixture(_ sample: AnalyticsChargeSample, now: Date) -> (summary: ChargeSummaryDTO, detail: ChargeDetailDTO) {
        let duration = sample.durationMinutes ?? 90
        let endDate = sample.date.addingTimeInterval(Double(duration) * 60)
        let energy = sample.energy ?? 24
        let chargeOdometer = odometer(at: sample.date, now: now)
        let startLevel = 24 + abs(sample.id) % 18
        let endLevel = min(92, startLevel + max(6, Int(energy / 0.75)))
        let summary = ChargeSummaryDTO(
            chargeId: sample.id,
            startDate: FlexibleDate(sample.date),
            endDate: FlexibleDate(endDate),
            address: sample.location,
            chargeEnergyAdded: energy,
            chargeEnergyUsed: energy * 1.07,
            cost: sample.cost,
            durationMin: duration,
            durationStr: "\(duration) min",
            outsideTempAvg: 18,
            odometer: chargeOdometer,
            latitude: coordinate(for: sample.location ?? "Home").latitude,
            longitude: coordinate(for: sample.location ?? "Home").longitude,
            batteryDetails: LevelWindowDTO(
                startBatteryLevel: startLevel,
                endBatteryLevel: endLevel,
                startUsableBatteryLevel: nil,
                endUsableBatteryLevel: nil
            ),
            rangeRated: RangeWindowDTO(
                startRange: ratedRange(atLevel: startLevel, odometer: chargeOdometer),
                endRange: ratedRange(atLevel: endLevel, odometer: chargeOdometer),
                rangeDiff: nil
            ),
            rangeIdeal: nil
        )
        let isFastCharge = sample.location?.localizedCaseInsensitiveContains("Supercharger") == true
        let points = (0..<8).map { index in
            let progress = Double(index) / 7
            return ChargePointDTO(
                detailId: sample.id * 100 + index,
                date: FlexibleDate(sample.date.addingTimeInterval(Double(duration * 60) * progress)),
                batteryLevel: 22 + Int(progress * 58),
                usableBatteryLevel: 21 + Int(progress * 58),
                chargeEnergyAdded: energy * progress,
                chargerDetails: ChargerDetailsDTO(
                    chargerActualCurrent: isFastCharge ? 180 - progress * 90 : 32,
                    chargerPhases: isFastCharge ? nil : 1,
                    chargerPilotCurrent: isFastCharge ? 250 : 32,
                    chargerPower: isFastCharge ? 145 - progress * 75 : 7.6,
                    chargerVoltage: isFastCharge ? 410 : 240
                ),
                outsideTemp: 18,
                connChargeCable: isFastCharge ? nil : "SAE",
                fastChargerInfo: FastChargerInfoDTO(
                    fastChargerPresent: isFastCharge,
                    fastChargerBrand: isFastCharge ? "Tesla" : nil,
                    fastChargerType: isFastCharge ? "Supercharger" : nil
                ),
                batteryInfo: ChargeBatteryInfoDTO(
                    idealBatteryRange: nil,
                    ratedBatteryRange: ratedRange(
                        atLevel: 22 + Int(progress * 58),
                        odometer: chargeOdometer
                    ),
                    batteryHeater: false,
                    batteryHeaterOn: false
                )
            )
        }
        let detail = ChargeDetailDTO(
            chargeId: sample.id,
            startDate: summary.startDate,
            endDate: summary.endDate,
            isCharging: false,
            address: summary.address,
            chargeEnergyAdded: summary.chargeEnergyAdded,
            chargeEnergyUsed: summary.chargeEnergyUsed,
            cost: summary.cost,
            durationMin: summary.durationMin,
            outsideTempAvg: summary.outsideTempAvg,
            chargeDetails: points,
            odometer: summary.odometer,
            latitude: summary.latitude,
            longitude: summary.longitude,
            batteryDetails: summary.batteryDetails,
            rangeRated: summary.rangeRated
        )
        return (summary, detail)
    }

    /// Rated range for a charge level, faded gently with mileage so the modelled
    /// capacity series slopes the way a real pack does.
    ///
    /// Demo units are miles; 310 mi at 100% when new, losing about 4% by 20,000
    /// miles.
    private static func ratedRange(atLevel level: Int, odometer: Double) -> Double {
        let fade = 1 - min(max(odometer, 0) / 20_000 * 0.04, 0.12)
        return 310 * fade * Double(level) / 100
    }

    private static func coordinate(for location: String) -> CoordinateDTO {
        switch location.lowercased() {
        case let value where value.contains("airport"):
            CoordinateDTO(latitude: 37.6213, longitude: -122.3790)
        case let value where value.contains("trail"):
            CoordinateDTO(latitude: 37.3861, longitude: -122.0839)
        case let value where value.contains("office"):
            CoordinateDTO(latitude: 37.4220, longitude: -122.0841)
        case let value where value.contains("grocery"):
            CoordinateDTO(latitude: 37.4419, longitude: -122.1430)
        case let value where value.contains("downtown"):
            CoordinateDTO(latitude: 37.3382, longitude: -121.8863)
        case let value where value.contains("supercharger"):
            CoordinateDTO(latitude: 37.3947, longitude: -122.1503)
        default:
            CoordinateDTO(latitude: 37.3349, longitude: -122.0090)
        }
    }
}
