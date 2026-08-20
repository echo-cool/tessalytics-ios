import Foundation

/// Fleet-wide figures derived from the complete cached history.
///
/// Every value here is computed in the app from the list endpoints, because
/// TeslaMateApi exposes no aggregate endpoint. The equivalent Grafana panels run
/// SQL over `drives`, `charging_processes` and `charges`; the arithmetic below is
/// the same arithmetic against the same data.
struct FleetStatistics: Equatable {
    struct BatteryHealth: Equatable {
        /// Pack capacity when new, kWh — the owner's figure when they gave one.
        let capacityNew: Double?
        /// Usable pack capacity now, kWh.
        let capacityNow: Double?
        /// Rated range at 100% when new, in the server's length unit.
        let maxRangeNew: Double?
        /// Rated range at 100% now, in the server's length unit.
        let maxRangeNow: Double?
        /// What the recorded history implies, before any owner override.
        ///
        /// Kept so the settings screen can show the derived figure next to the
        /// field, and so an override is visibly an override.
        var derivedCapacityNew: Double?
        var derivedMaxRangeNew: Double?
        var isSpecificationOverridden = false
        /// The server's own health figure, used only when nothing better exists.
        let reportedHealthPercent: Double?
        /// kWh per 100 km, needed to model capacity from a range reading.
        let ratedEfficiency: Double?
        let observedAt: Date?

        /// Share of the original capacity still usable.
        ///
        /// Computed from the two capacities rather than taken from the server, so
        /// an owner-supplied as-new figure actually changes the answer.
        var healthPercent: Double? {
            if let capacityNew, capacityNew > 0, let capacityNow {
                return min(capacityNow / capacityNew, 1) * 100
            }
            return reportedHealthPercent
        }

        /// Range no longer available at a full charge.
        var rangeLost: Double? {
            guard let maxRangeNew, let maxRangeNow else { return nil }
            return max(maxRangeNew - maxRangeNow, 0)
        }

        var capacityLost: Double? {
            guard let capacityNew, let capacityNow else { return nil }
            return max(capacityNew - capacityNow, 0)
        }

        /// Share of the original range still available.
        var rangeRetention: Double? {
            guard let maxRangeNew, maxRangeNew > 0, let maxRangeNow else { return nil }
            return maxRangeNow / maxRangeNew
        }
    }

    struct DriveStats: Equatable {
        /// Distance TeslaMate actually recorded, summed over every drive.
        let loggedDistance: Double
        /// Current odometer reading from the live status.
        let odometer: Double?
        /// Odometer at the start of the earliest recorded drive.
        let firstLoggedOdometer: Double?
        let driveCount: Int
        /// Supplied by Tessalytics Backend, which measures this over the whole
        /// history rather than over what this device happens to have cached.
        var serverUnloggedDistance: Double?
        var serverCoverage: Double?

        /// Distance the car covered while TeslaMate was not logging.
        ///
        /// The span from the first recorded drive to now, minus what was
        /// recorded. Mileage from before logging began is excluded — it was
        /// never a gap, it was just history the logger never saw.
        var unloggedDistance: Double? {
            if let serverUnloggedDistance { return serverUnloggedDistance }
            guard let odometer, let firstLoggedOdometer else { return nil }
            let span = odometer - firstLoggedOdometer
            guard span > 0 else { return nil }
            return max(span - loggedDistance, 0)
        }

        /// Share of the logging span that made it into the database.
        var coverage: Double? {
            if let serverCoverage { return serverCoverage }
            guard let odometer, let firstLoggedOdometer else { return nil }
            let span = odometer - firstLoggedOdometer
            guard span > 0 else { return nil }
            return min(loggedDistance / span, 1)
        }
    }

    struct ChargingStats: Equatable {
        let chargeCount: Int
        /// kWh that reached the pack.
        let energyAdded: Double
        /// kWh drawn from the outlet.
        let energyUsed: Double
        let costTotal: Double
        let pricedChargeCount: Int
        /// Supplied by Tessalytics Backend, which knows the pack capacity it
        /// divided by; the local figure has to infer one.
        var serverCycles: Double?

        /// Equivalent full charges: total energy added divided by nominal pack
        /// capacity. Uses the as-new capacity so the number does not drift as
        /// the pack ages.
        func cycles(capacityNew: Double?) -> Double? {
            if let serverCycles { return serverCycles }
            guard let capacityNew, capacityNew > 0, energyAdded > 0 else { return nil }
            return energyAdded / capacityNew
        }

        /// Share of drawn energy that reached the pack. The rest is charging
        /// loss — cabling, rectification, and battery conditioning.
        var efficiency: Double? {
            guard energyUsed > 0, energyAdded > 0 else { return nil }
            return min(energyAdded / energyUsed, 1)
        }

        var averagePricePerKWh: Double? {
            guard costTotal > 0, energyAdded > 0 else { return nil }
            return costTotal / energyAdded
        }
    }

    var battery: BatteryHealth?
    var drives = DriveStats(loggedDistance: 0, odometer: nil, firstLoggedOdometer: nil, driveCount: 0)
    var charging = ChargingStats(chargeCount: 0, energyAdded: 0, energyUsed: 0, costTotal: 0, pricedChargeCount: 0)
    var lastFullSync: Date?
    /// True when the whole history has been paged at least once, so the totals
    /// are complete rather than a partial sum.
    var isComplete = false
}

extension FleetStatistics {
    /// Replaces the locally summed figures with the server's.
    ///
    /// The local sums are only as complete as the history this device has paged;
    /// the server sees all of it. Anything the server does not report is left as
    /// computed rather than blanked, so a partial response never loses data.
    mutating func applyServerTotals(_ totals: BackendTotals) {
        if let driving = totals.driving {
            drives = DriveStats(
                loggedDistance: driving.distanceLogged ?? drives.loggedDistance,
                odometer: driving.odometer ?? drives.odometer,
                firstLoggedOdometer: drives.firstLoggedOdometer,
                driveCount: driving.drives ?? drives.driveCount,
                serverUnloggedDistance: driving.distanceUnlogged,
                serverCoverage: driving.coverage
            )
        }
        if let charging = totals.charging {
            self.charging = ChargingStats(
                chargeCount: charging.charges ?? self.charging.chargeCount,
                energyAdded: charging.energyAdded ?? self.charging.energyAdded,
                energyUsed: charging.energyUsed ?? self.charging.energyUsed,
                costTotal: charging.costTotal ?? self.charging.costTotal,
                pricedChargeCount: charging.pricedCharges ?? self.charging.pricedChargeCount,
                serverCycles: charging.cycles
            )
        }
        // Server-reported totals are complete by construction, so the "still
        // syncing" caveat no longer applies.
        isComplete = true
    }
}

/// Derives `FleetStatistics` and the modelled capacity series from cached rows.
enum FleetStatisticsBuilder {
    static func build(
        drives: [DriveRecord],
        charges: [ChargeRecord],
        batteryHealth: BatteryHealthRecord?,
        odometer: Double?,
        lastFullSync: Date?,
        isComplete: Bool,
        specification: VehicleSpecification = .empty
    ) -> FleetStatistics {
        var statistics = FleetStatistics()
        statistics.lastFullSync = lastFullSync
        statistics.isComplete = isComplete

        if let batteryHealth {
            statistics.battery = FleetStatistics.BatteryHealth(
                capacityNew: specification.capacityNew ?? batteryHealth.maxCapacity,
                capacityNow: batteryHealth.currentCapacity,
                maxRangeNew: specification.maxRangeNew ?? batteryHealth.maxRange,
                maxRangeNow: batteryHealth.currentRange,
                derivedCapacityNew: batteryHealth.maxCapacity,
                derivedMaxRangeNew: batteryHealth.maxRange,
                isSpecificationOverridden: specification.isEmpty == false,
                reportedHealthPercent: batteryHealth.healthPercent,
                ratedEfficiency: batteryHealth.ratedEfficiency,
                observedAt: batteryHealth.observedAt
            )
        } else if specification.isEmpty == false {
            // An owner who supplied the pack size deserves to see it even before
            // any health estimate has synchronized.
            statistics.battery = FleetStatistics.BatteryHealth(
                capacityNew: specification.capacityNew,
                capacityNow: nil,
                maxRangeNew: specification.maxRangeNew,
                maxRangeNow: nil,
                isSpecificationOverridden: true,
                reportedHealthPercent: nil,
                ratedEfficiency: nil,
                observedAt: nil
            )
        }

        let distances = drives.compactMap(\.distance).filter { $0 > 0 }
        statistics.drives = FleetStatistics.DriveStats(
            loggedDistance: distances.reduce(0, +),
            odometer: odometer,
            firstLoggedOdometer: drives.compactMap(\.odometerStart).min(),
            driveCount: drives.count
        )

        let costs = charges.compactMap(\.cost).filter { $0 > 0 }
        statistics.charging = FleetStatistics.ChargingStats(
            chargeCount: charges.count,
            energyAdded: charges.compactMap(\.energyAdded).filter { $0 > 0 }.reduce(0, +),
            energyUsed: charges.compactMap(\.energyUsed).filter { $0 > 0 }.reduce(0, +),
            costTotal: costs.reduce(0, +),
            pricedChargeCount: costs.count
        )

        return statistics
    }
}

/// One modelled pack-capacity observation, taken at the end of a charge.
struct CapacityObservation: Identifiable, Equatable {
    let id: Int
    let date: Date
    /// Odometer at the charging location, in the server's length unit.
    let odometer: Double
    /// Modelled usable pack capacity, kWh.
    let capacity: Double

    var chargeID: Int { id }
}

/// Models pack capacity from the range and charge level at the end of a charge.
///
/// This is the app-side equivalent of the TeslaMate "Projected Range" panel:
///
///     rated_battery_range_km * RatedEfficiency / usable_battery_level
///
/// `RatedEfficiency` is kWh per 100 km, and dividing by the level (a percentage)
/// scales the reading to a notional 100%. Ranges come back in the server's
/// display unit, so they are converted to kilometres first.
///
/// One caveat, stated because it affects the numbers: charge *summaries* report
/// `battery_level`, not `usable_battery_level`. The usable level excludes the
/// cold buffer and is typically a point lower, which biases modelled capacity
/// low by roughly one percent. Charge detail samples do carry the usable level;
/// the summary is used here so the whole series costs one request instead of one
/// per charge.
enum CapacityModel {
    static func observations(
        charges: [ChargeRecord],
        ratedEfficiency: Double?,
        units: UnitsDTO?
    ) -> [CapacityObservation] {
        guard let ratedEfficiency, ratedEfficiency > 0 else { return [] }
        let perKilometre = (units ?? .metricDefaults).lengthSymbol == "mi" ? 1.609_344 : 1.0

        return charges.compactMap { charge -> CapacityObservation? in
            guard let date = charge.endDate ?? charge.startDate,
                  let odometer = charge.odometer, odometer > 0,
                  let range = charge.endRatedRange, range > 0,
                  let level = charge.endLevel, level > 0,
                  // A trickle top-up moves the range too little to model from.
                  (charge.energyAdded ?? 0) >= ratedEfficiency / 100
            else { return nil }

            let rangeKilometres = range * perKilometre
            let capacity = rangeKilometres * ratedEfficiency / Double(level)
            // Reject physically implausible results rather than plotting them.
            guard capacity > 5, capacity < 250 else { return nil }

            return CapacityObservation(
                id: charge.chargeID,
                date: date,
                odometer: odometer,
                capacity: capacity
            )
        }
        .sorted { $0.odometer < $1.odometer }
    }

    /// Semi-monthly medians, mirroring the TeslaMate median panel's grouping
    /// (year-month plus a first/second-half-of-month marker). A median is far
    /// more readable than the raw scatter, which is noisy by nature.
    static func semiMonthlyMedians(_ observations: [CapacityObservation]) -> [CapacityObservation] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: observations) { observation -> String in
            let parts = calendar.dateComponents([.year, .month, .day], from: observation.date)
            let half = (parts.day ?? 1) <= 15 ? "1" : "2"
            return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(half)"
        }

        return grouped.values.compactMap { bucket -> CapacityObservation? in
            guard let representative = bucket.min(by: { $0.odometer < $1.odometer }) else { return nil }
            return CapacityObservation(
                id: representative.id,
                date: representative.date,
                odometer: bucket.map(\.odometer).reduce(0, +) / Double(bucket.count),
                capacity: median(bucket.map(\.capacity))
            )
        }
        .sorted { $0.odometer < $1.odometer }
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
}

/// A charging location weighted by the energy delivered there.
struct ChargingSite: Identifiable, Equatable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let energyAdded: Double
    let sessions: Int
    /// Share of all charging energy delivered at this site, 0...1.
    let share: Double
}

/// Groups charges by location for the charging map.
///
/// The app-side equivalent of the TeslaMate charging heat map, which groups by
/// geofence name falling back to a composed street address. TeslaMateApi already
/// returns a resolved `address` per charge along with its coordinates, so the
/// grouping key is that address.
enum ChargingSiteBuilder {
    static func sites(from charges: [ChargeRecord]) -> [ChargingSite] {
        let usable = charges.filter {
            $0.latitude != nil && $0.longitude != nil && ($0.energyAdded ?? 0) > 0
        }
        let total = usable.compactMap(\.energyAdded).reduce(0, +)
        guard total > 0 else { return [] }

        let grouped = Dictionary(grouping: usable) { charge in
            charge.address?.nilIfEmpty ?? "Unnamed location"
        }

        return grouped.map { name, group in
            let energy = group.compactMap(\.energyAdded).reduce(0, +)
            let count = Double(group.count)
            return ChargingSite(
                id: name,
                name: name,
                // Sessions at one site scatter across a car park, so the
                // centroid represents the site better than any single fix.
                latitude: group.compactMap(\.latitude).reduce(0, +) / count,
                longitude: group.compactMap(\.longitude).reduce(0, +) / count,
                energyAdded: energy,
                sessions: group.count,
                share: energy / total
            )
        }
        .sorted { $0.energyAdded > $1.energyAdded }
    }
}

/// One projected-range reading over time.
struct ProjectedRangePoint: Identifiable, Equatable {
    let id: Date
    let date: Date
    /// Rated range extrapolated to a 100% charge, in the server's length unit.
    let projectedRange: Double
}

/// Extrapolates rated range to a full charge across the history.
///
/// The TeslaMate panel unions the `positions` and `charges` tables. Positions
/// have no endpoint, so this uses the range and level readings at each end of
/// every drive and charge — coarser in time, same quantity:
///
///     rated_range / usable_level * 100
enum ProjectedRangeModel {
    private struct Sample {
        let date: Date
        let range: Double
        let level: Int
    }

    static func points(
        drives: [DriveRecord],
        charges: [ChargeRecord],
        interval: Calendar.Component = .weekOfYear
    ) -> [ProjectedRangePoint] {
        var samples: [Sample] = []

        for drive in drives {
            if let date = drive.startDate, let range = drive.startRatedRange, let level = drive.startLevel {
                samples.append(Sample(date: date, range: range, level: level))
            }
            if let date = drive.endDate, let range = drive.endRatedRange, let level = drive.endLevel {
                samples.append(Sample(date: date, range: range, level: level))
            }
        }
        for charge in charges {
            if let date = charge.endDate, let range = charge.endRatedRange, let level = charge.endLevel {
                samples.append(Sample(date: date, range: range, level: level))
            }
        }

        let calendar = Calendar.current
        // Bucketed and summed rather than averaged per reading: summing range and
        // level before dividing is what the SQL does, and it weights a nearly
        // full pack more heavily than a nearly empty one, where the extrapolation
        // is least reliable.
        let grouped = Dictionary(grouping: samples.filter { $0.level > 0 && $0.range > 0 }) { sample in
            calendar.dateInterval(of: interval, for: sample.date)?.start ?? sample.date
        }

        return grouped.compactMap { start, bucket -> ProjectedRangePoint? in
            let levels = bucket.map { Double($0.level) }.reduce(0, +)
            guard levels > 0 else { return nil }
            let ranges = bucket.map(\.range).reduce(0, +)
            return ProjectedRangePoint(id: start, date: start, projectedRange: ranges / levels * 100)
        }
        .sorted { $0.date < $1.date }
    }
}

/// What the owner told us about the car, as opposed to what its history shows.
///
/// The derived as-new figures are the best the recorded data can support, and
/// that is wrong whenever logging started after the pack had already aged. A
/// Model 3 rated 84 kWh new reads as 74 if TeslaMate began recording at 15,000
/// miles, and every figure computed from it — health, capacity lost, range lost,
/// equivalent cycles — inherits the error.
struct VehicleSpecification: Equatable, Sendable {
    /// Pack capacity when new, kWh.
    var capacityNew: Double?
    /// Rated range at 100% when new, in the server's length unit.
    var maxRangeNew: Double?

    static let empty = VehicleSpecification()

    var isEmpty: Bool { capacityNew == nil && maxRangeNew == nil }

    /// Rejects values that cannot be a pack or a range, so a typo cannot poison
    /// every derived figure.
    static func sanitised(capacityNew: Double?, maxRangeNew: Double?) -> VehicleSpecification {
        VehicleSpecification(
            capacityNew: capacityNew.flatMap { (1...400).contains($0) ? $0 : nil },
            maxRangeNew: maxRangeNew.flatMap { (1...2000).contains($0) ? $0 : nil }
        )
    }
}
