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
            // A real, check-digit-valid VIN for a car that does not exist:
            // Shanghai-built Model Y, 2023 model year. It is what makes the
            // pack lookup visible in demo mode and testable without a car.
            vin: "LRWYGCEK9PC123456",
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
            drivingDetails: DrivingDetailsDTO(
                shiftState: "D",
                power: 34,
                speed: 63,
                heading: 118,
                elevation: 42,
                autopilotState: "Full Self-Driving",
                isAutopilotEngaged: true
            ),
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
            // Curved rather than a straight diagonal: the hero map draws this as
            // the route driven, and no road runs in a perfect line for eight miles.
            // Tapered to nothing at both ends, so the route still starts and
            // finishes where the parked and driving snapshots say the car is.
            let sway = (sin(progress * .pi * 1.6) * 0.0022 + sin(progress * .pi * 4.4) * 0.0006)
                * sin(progress * .pi)
            buffer.append(
                date: now.addingTimeInterval(seconds),
                speed: speed,
                power: power,
                level: 78 - progress * 7,
                odometer: 18_642 + progress * 12.2,
                latitude: 37.3861 + progress * 0.020 - sway * 0.55,
                longitude: -122.0839 + progress * 0.0116 + sway,
                elevation: 28 + sin(progress * .pi * 1.3) * 34
            )
        }
        return buffer
    }

    /// The whole-journey figures for the generated drive.
    ///
    /// Built by walking the same samples the buffer holds, so the demo's
    /// "this drive" figures are the ones its own readings imply.
    static func drivingTotals(now: Date = .now) -> LiveDriveTotals {
        var totals = LiveDriveTotals()
        for sample in drivingTelemetry(now: now).samples {
            totals.record(
                odometer: sample.odometer,
                speed: sample.speed,
                power: sample.power,
                at: sample.date
            )
        }
        return totals
    }

    /// A car part-way through a DC fast charge.
    ///
    /// Deliberately a *tapering* one: still drawing hard, but with the car itself
    /// saying it needs longer to reach 80 than that rate implies. A demo that
    /// charged at a flat rate would exercise the easy half of the forecast and
    /// hide the half that matters.
    ///
    /// The figures are kept consistent with each other on purpose. An earlier
    /// version claimed 118 kW beside a level climbing at 60 %/h, which on a 78 kWh
    /// pack is arithmetically impossible — and it showed, as a power line and a
    /// charge line telling two different stories in the same frame.
    static let chargingPackKWh: Double = 78
    /// Where the session began.
    static let chargingStartLevel: Double = 22
    static let chargingNowLevel: Double = 41
    static let chargingElapsed: TimeInterval = 17 * 60

    /// Percent per hour at a given charge: fast at the bottom, easing as it fills.
    private static func chargingRate(at percent: Double) -> Double {
        max(105 - 0.85 * (percent - chargingStartLevel), 12)
    }

    private static func chargingPower(at percent: Double) -> Double {
        chargingRate(at: percent) / 100 * chargingPackKWh
    }

    static func chargingStatus(now: Date = .now) -> VehicleStatus {
        let parked = status(now: now)
        let limit: Double = 80
        // Integrating 1/rate from here to the limit, which is what the car's own
        // estimate would be if the car agreed with this curve.
        var hours = 0.0
        var level = chargingNowLevel
        while level < limit {
            hours += 0.25 / chargingRate(at: level)
            level += 0.25
        }
        return VehicleStatus(
            displayName: parked.displayName,
            state: "charging",
            stateSince: FlexibleDate(now.addingTimeInterval(-chargingElapsed)),
            odometer: parked.odometer,
            carStatus: parked.carStatus,
            carDetails: parked.carDetails,
            carGeodata: parked.carGeodata,
            carVersions: parked.carVersions,
            drivingDetails: parked.drivingDetails,
            climateDetails: parked.climateDetails,
            batteryDetails: StatusBatteryDTO(
                estBatteryRange: 125.4,
                ratedBatteryRange: 120.6,
                idealBatteryRange: 129,
                batteryLevel: Int(chargingNowLevel),
                usableBatteryLevel: Int(chargingNowLevel)
            ),
            chargingDetails: StatusChargingDTO(
                pluggedIn: true,
                chargingState: "Charging",
                chargeEnergyAdded: chargingSession(now: now).energyAdded ?? 0,
                chargeLimitSoc: Int(limit),
                chargePortDoorOpen: true,
                chargerActualCurrent: 190,
                chargerPhases: nil,
                chargerPower: chargingPower(at: chargingNowLevel).rounded(),
                chargerVoltage: 394,
                scheduledChargingStartTime: nil,
                timeToFullCharge: hours
            ),
            tpmsDetails: parked.tpmsDetails
        )
    }

    /// Readings from the minutes of this charge already elapsed, so the measured
    /// rate and the solid half of the forecast chart have something real behind
    /// them.
    ///
    /// Integrated *backwards* from the level the status reports, not forwards from
    /// where the session began. Forwards, the walk ended wherever the arithmetic
    /// took it — nine points above the reading — and the measured line climbed
    /// past the current charge and then dropped to meet it, drawing a charge that
    /// went down while the car was plugged in.
    static func chargingSession(now: Date = .now) -> LiveChargeSession {
        let step: TimeInterval = 60
        var levels: [Double] = []
        var level = chargingNowLevel
        var offset: TimeInterval = 0
        while offset <= chargingElapsed {
            levels.append(level)
            level -= chargingRate(at: level) * (step / 3_600)
            offset += step
        }

        var session = LiveChargeSession()
        for (index, level) in levels.reversed().enumerated() {
            let elapsed = Double(index) * step
            session.record(
                date: now.addingTimeInterval(elapsed - chargingElapsed),
                level: level.rounded(),
                power: chargingPower(at: level).rounded(),
                energyAdded: ((level - levels.last!) / 100 * chargingPackKWh).rounded(),
                range: 67 + (level - levels.last!) * 3.07
            )
        }
        return session
    }

    /// A car on a wall box that the app has only just been opened on.
    ///
    /// The case the DC demo hides: the charge began seventy minutes ago and the
    /// app has three minutes of readings, so the axis has to come from the car
    /// rather than from the buffer. Also 7 kW rather than 70, which is what
    /// exposed a right-hand axis ticking at 2.5 kW and rounding the labels to
    /// whole numbers.
    static let wallBoxKW: Double = 7
    static let wallBoxElapsed: TimeInterval = 70 * 60
    static let wallBoxObserved: TimeInterval = 3 * 60
    static let wallBoxNowLevel: Double = 64

    static func wallBoxChargingStatus(now: Date = .now) -> VehicleStatus {
        let parked = status(now: now)
        let limit: Double = 100
        let capacity = chargingPackKWh
        // A flat rate to 95, then the balancing at the top the car allows for.
        let flatHours = max(95 - wallBoxNowLevel, 0) / (wallBoxKW / capacity * 100)
        let topHours = 5.0 / (wallBoxKW * 0.45 / capacity * 100)
        return VehicleStatus(
            displayName: parked.displayName,
            state: "charging",
            stateSince: FlexibleDate(now.addingTimeInterval(-wallBoxElapsed)),
            odometer: parked.odometer,
            carStatus: parked.carStatus,
            carDetails: parked.carDetails,
            carGeodata: parked.carGeodata,
            carVersions: parked.carVersions,
            drivingDetails: parked.drivingDetails,
            climateDetails: parked.climateDetails,
            batteryDetails: StatusBatteryDTO(
                estBatteryRange: 211.42,
                ratedBatteryRange: 205,
                idealBatteryRange: 218,
                batteryLevel: Int(wallBoxNowLevel),
                usableBatteryLevel: Int(wallBoxNowLevel)
            ),
            chargingDetails: StatusChargingDTO(
                pluggedIn: true,
                chargingState: "Charging",
                chargeEnergyAdded: wallBoxKW * (wallBoxElapsed / 3_600),
                chargeLimitSoc: Int(limit),
                chargePortDoorOpen: true,
                chargerActualCurrent: 30,
                chargerPhases: 1,
                chargerPower: wallBoxKW,
                chargerVoltage: 240,
                scheduledChargingStartTime: nil,
                timeToFullCharge: flatHours + topHours
            ),
            tpmsDetails: parked.tpmsDetails
        )
    }

    /// Only the last few minutes, because that is all the app has seen.
    static func wallBoxSession(now: Date = .now) -> LiveChargeSession {
        var session = LiveChargeSession()
        let rate = wallBoxKW / chargingPackKWh * 100
        var offset: TimeInterval = 0
        while offset <= wallBoxObserved {
            let level = wallBoxNowLevel - rate * ((wallBoxObserved - offset) / 3_600)
            session.record(
                date: now.addingTimeInterval(offset - wallBoxObserved),
                level: level.rounded(),
                power: wallBoxKW,
                energyAdded: wallBoxKW * ((wallBoxElapsed - wallBoxObserved + offset) / 3_600),
                range: 205 + level - wallBoxNowLevel
            )
            offset += 30
        }
        return session
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
            // A position and no geofence: where the car is comes from geocoding
            // the coordinate, and the server's geofence is deliberately unused —
            // it names the last place a drive ended inside one, which is an
            // address the car may have left days ago.
            carGeodata: CarGeodataDTO(
                geofence: nil,
                location: CoordinateDTO(latitude: 37.4062, longitude: -122.0723)
            ),
            carVersions: CarVersionsDTO(version: "2026.20.3", updateAvailable: false, updateVersion: nil),
            // A parked car reports P, and the hero shows the gear the car is
            // actually in rather than only the app's word for it.
            drivingDetails: DrivingDetailsDTO(shiftState: "P", power: 0, speed: 0, heading: nil, elevation: nil),
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

    /// Demo mode never reaches a network, so the reverse geocoder does not
    /// either. The names are the ones the generated route actually runs along.
    static let placeNames = FixedPlaceNames(
        street: "El Camino Real, Mountain View",
        address: "1350 El Camino Real, Mountain View"
    )

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
        let ledger = batteryLedger(now: now)
        for sample in samples {
            let fixture = driveFixture(sample, now: now, ledger: ledger)
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

        let ledger = batteryLedger(now: now)
        let segments = DemoAnalyticsFactory.samples(now: now).drives
            .map { driveFixture($0, now: now, ledger: ledger).detail.driveDetails.map(\.coordinate) }
            .filter { $0.count > 1 }
        guard !segments.isEmpty else { return }
        context.insert(
            TrackRecord(serverID: profileID, carID: carID, segments: segments, coversUntil: now)
        )
    }

    @MainActor
    private static func seedCharges(in context: ModelContext, now: Date) {
        let samples = DemoAnalyticsFactory.samples(now: now).charges
        let ledger = batteryLedger(now: now)
        for sample in samples {
            let fixture = chargeFixture(sample, now: now, ledger: ledger)
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
            // The newest install is three weeks old, not this instant: a car that
            // updated a moment ago has run its current version for zero days,
            // which draws as a missing bar on the timeline rather than a short one.
            let installed = Calendar.current.date(byAdding: .day, value: -21, to: now) ?? now
            let end = Calendar.current.date(byAdding: .month, value: -(index * 2), to: installed) ?? installed
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

    /// One event's battery level at each end.
    private struct DemoLevelWindow: Sendable {
        let start: Int
        let end: Int
    }

    /// Battery levels that join up across the whole demo history.
    ///
    /// They used to be generated per event from its own id, so a drive could end
    /// at 70% and the charge an hour later begin at 26%. Anything that reads the
    /// gap *between* two events then saw a car losing half its charge overnight —
    /// which is exactly what the standby-drain panel measures.
    private static func batteryLedger(now: Date) -> [Int: DemoLevelWindow] {
        enum Event {
            case drive(AnalyticsDriveSample)
            case charge(AnalyticsChargeSample)
        }
        let samples = DemoAnalyticsFactory.samples(now: now)
        let events: [(start: Date, minutes: Int, event: Event)] =
            (samples.drives.map { (start: $0.date, minutes: $0.durationMinutes ?? 28, event: Event.drive($0)) }
                + samples.charges.map { (start: $0.date, minutes: $0.durationMinutes ?? 90, event: Event.charge($0)) })
            .sorted { $0.start < $1.start }

        // A percentage point of pack per 0.784 kWh, which is the demo car's.
        let kilowattHoursPerPoint = 0.784
        var ledger: [Int: DemoLevelWindow] = [:]
        var level = 74.0
        var previousEnd: Date?

        for entry in events {
            if let previousEnd, entry.start > previousEnd {
                // Just over a point a day, which is what a healthy car with
                // Sentry off actually loses while parked.
                level = max(level - entry.start.timeIntervalSince(previousEnd) / 86_400 * 1.2, 8)
            }
            previousEnd = entry.start.addingTimeInterval(Double(entry.minutes) * 60)

            switch entry.event {
            case .drive(let drive):
                let start = min(max(level, 14), 96)
                let used = max((drive.energy ?? 3) / kilowattHoursPerPoint, 2)
                let end = max(start - used, 8)
                ledger[drive.id] = DemoLevelWindow(start: Int(start.rounded()), end: Int(end.rounded()))
                level = end
            case .charge(let charge):
                let start = min(max(level, 8), 88)
                let added = max((charge.energy ?? 24) / kilowattHoursPerPoint, 5)
                let end = min(start + added, 90)
                ledger[charge.id] = DemoLevelWindow(start: Int(start.rounded()), end: Int(end.rounded()))
                level = end
            }
        }
        return ledger
    }

    private static func driveFixture(
        _ sample: AnalyticsDriveSample,
        now: Date,
        ledger: [Int: DemoLevelWindow]
    ) -> (summary: DriveSummaryDTO, detail: DriveDetailDTO) {
        let startName = sample.id.isMultiple(of: 2) ? "Home" : "Office"
        let endName = sample.destination ?? "Downtown"
        let startCoordinate = coordinate(for: startName)
        let endCoordinate = coordinate(for: endName)
        let duration = sample.durationMinutes ?? 28
        let endDate = sample.date.addingTimeInterval(Double(duration) * 60)
        let distance = sample.distance ?? 12
        let odometerStart = odometer(at: sample.date, now: now) - distance
        let window = ledger[sample.id]
            ?? DemoLevelWindow(start: 74, end: max(12, 74 - Int(max(2, distance / 5))))
        let startLevel = window.start
        let endLevel = window.end
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

    private static func chargeFixture(
        _ sample: AnalyticsChargeSample,
        now: Date,
        ledger: [Int: DemoLevelWindow]
    ) -> (summary: ChargeSummaryDTO, detail: ChargeDetailDTO) {
        let duration = sample.durationMinutes ?? 90
        let endDate = sample.date.addingTimeInterval(Double(duration) * 60)
        let energy = sample.energy ?? 24
        let chargeOdometer = odometer(at: sample.date, now: now)
        let window = ledger[sample.id]
            ?? DemoLevelWindow(start: 34, end: min(90, 34 + max(6, Int(energy / 0.784))))
        let startLevel = window.start
        let endLevel = window.end
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
                batteryLevel: startLevel + Int(progress * Double(endLevel - startLevel)),
                usableBatteryLevel: max(startLevel - 1 + Int(progress * Double(endLevel - startLevel)), 0),
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
