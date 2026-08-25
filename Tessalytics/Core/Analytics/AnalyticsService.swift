import Foundation

struct AnalyticsSnapshot: Sendable {
    let distance: Double?
    let drivingMinutes: Int
    let driveCount: Int
    let averageTripDistance: Double?
    let chargingEnergy: Double?
    let chargingCost: Double?
    let averagePricePerKWh: Double?
    let averageEfficiency: Double?
}

protocol AnalyticsServiceProtocol: Sendable {
    func snapshot(drives: [DriveRecord], charges: [ChargeRecord]) -> AnalyticsSnapshot
    func integratedEnergy(samples: [(date: Date, powerKW: Double)], maximumGap: TimeInterval) -> Double?
}

struct AnalyticsService: AnalyticsServiceProtocol {
    func snapshot(drives: [DriveRecord], charges: [ChargeRecord]) -> AnalyticsSnapshot {
        let distances = drives.compactMap(\.distance)
        let energies = charges.compactMap(\.energyAdded)
        let costs = charges.compactMap(\.cost)
        let efficiencies = drives.compactMap(\.efficiency)
        let distance = distances.isEmpty ? nil : distances.reduce(0, +)
        let energy = energies.isEmpty ? nil : energies.reduce(0, +)
        let cost = costs.isEmpty ? nil : costs.reduce(0, +)
        return AnalyticsSnapshot(
            distance: distance,
            drivingMinutes: drives.compactMap(\.durationMinutes).reduce(0, +),
            driveCount: drives.count,
            averageTripDistance: distance.map { $0 / Double(max(distances.count, 1)) },
            chargingEnergy: energy,
            chargingCost: cost,
            averagePricePerKWh: (cost != nil && energy != nil && energy! > 0) ? cost! / energy! : nil,
            averageEfficiency: efficiencies.isEmpty ? nil : efficiencies.reduce(0, +) / Double(efficiencies.count)
        )
    }

    func integratedEnergy(samples: [(date: Date, powerKW: Double)], maximumGap: TimeInterval = 900) -> Double? {
        let sorted = samples.sorted { $0.date < $1.date }
        guard sorted.count > 1 else { return nil }
        var total = 0.0
        var used = false
        for pair in zip(sorted, sorted.dropFirst()) {
            let seconds = pair.1.date.timeIntervalSince(pair.0.date)
            guard seconds > 0, seconds <= maximumGap else { continue }
            total += ((pair.0.powerKW + pair.1.powerKW) / 2) * seconds / 3600
            used = true
        }
        return used ? total : nil
    }
}

struct AnalyticsDriveSample: Identifiable, Sendable {
    let id: Int
    let date: Date
    let distance: Double?
    let durationMinutes: Int?
    let energy: Double?
    let efficiency: Double?
    let destination: String?
    /// Average outside temperature over the drive, in the server's unit.
    var temperature: Double?
    /// Odometer at the end of the drive, in the server's length unit.
    var odometer: Double?
}

struct AnalyticsChargeSample: Identifiable, Sendable {
    let id: Int
    let date: Date
    let energy: Double?
    let cost: Double?
    let durationMinutes: Int?
    let location: String?
}

struct AnalyticsTimeWindow: Sendable {
    let current: Range<Date>?
    let previous: Range<Date>?
    let label: String
    let comparisonLabel: String?

    static func resolve(
        period: AnalyticsPeriod,
        customStart: Date,
        customEnd: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Self {
        let today = calendar.startOfDay(for: now)

        func days(_ count: Int) -> Self {
            let start = calendar.date(byAdding: .day, value: -(count - 1), to: today) ?? today
            let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
            let previousStart = calendar.date(byAdding: .day, value: -count, to: start) ?? start
            return Self(
                current: start..<end,
                previous: previousStart..<start,
                label: AppText.format("Last %@ days", "\(count)"),
                comparisonLabel: "prev. \(count)d"
            )
        }

        switch period {
        case .sevenDays:
            return days(7)
        case .thirtyDays:
            return days(30)
        case .currentMonth:
            let interval = calendar.dateInterval(of: .month, for: now)
            let start = interval?.start ?? today
            let previous = calendar.dateInterval(of: .month, for: calendar.date(byAdding: .month, value: -1, to: now) ?? now)
            let currentEnd = now.addingTimeInterval(1)
            let previousRange = previous.map { prior -> Range<Date> in
                let equivalentEnd = prior.start.addingTimeInterval(now.timeIntervalSince(start))
                return prior.start..<min(equivalentEnd, prior.end)
            }
            return Self(current: start..<currentEnd, previous: previousRange, label: "This month", comparisonLabel: "last month")
        case .previousMonth:
            let priorDate = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            let interval = calendar.dateInterval(of: .month, for: priorDate)
            let earlierDate = calendar.date(byAdding: .month, value: -2, to: now) ?? now
            let previous = calendar.dateInterval(of: .month, for: earlierDate)
            return Self(current: interval.map { $0.start..<$0.end }, previous: previous.map { $0.start..<$0.end }, label: "Last month", comparisonLabel: "prev. month")
        case .currentYear:
            let interval = calendar.dateInterval(of: .year, for: now)
            let priorDate = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            let previous = calendar.dateInterval(of: .year, for: priorDate)
            let currentStart = interval?.start ?? today
            let previousRange = previous.map { prior -> Range<Date> in
                let equivalentEnd = prior.start.addingTimeInterval(now.timeIntervalSince(currentStart))
                return prior.start..<min(equivalentEnd, prior.end)
            }
            return Self(current: currentStart..<now.addingTimeInterval(1), previous: previousRange, label: "This year", comparisonLabel: "last year")
        case .allTime:
            return Self(current: nil, previous: nil, label: "All synchronized data", comparisonLabel: nil)
        case .custom:
            let first = calendar.startOfDay(for: min(customStart, customEnd))
            let finalDay = calendar.startOfDay(for: max(customStart, customEnd))
            let end = calendar.date(byAdding: .day, value: 1, to: finalDay) ?? finalDay
            let duration = end.timeIntervalSince(first)
            let previousStart = first.addingTimeInterval(-duration)
            return Self(
                current: first..<end,
                previous: previousStart..<first,
                label: "Custom range",
                comparisonLabel: "prev. range"
            )
        }
    }
}

struct AnalyticsDailyDrivePoint: Identifiable, Sendable {
    let date: Date
    let distance: Double
    let energy: Double
    let trips: Int
    var id: Date { date }
}

struct AnalyticsDailyChargePoint: Identifiable, Sendable {
    let date: Date
    let energy: Double
    let cost: Double
    let sessions: Int
    var id: Date { date }
}

struct AnalyticsCategoryPoint: Identifiable, Sendable {
    let id: String
    let label: String
    let value: Double
    let count: Int
}

struct AnalyticsEfficiencyPoint: Identifiable, Sendable {
    let id: Int
    let date: Date
    let value: Double
    let distance: Double?
}

struct AnalyticsChargeRelationshipPoint: Identifiable, Sendable {
    let id: Int
    let energy: Double
    let cost: Double
    let location: String
}

/// Average consumption in one outside-temperature band.
struct AnalyticsTemperaturePoint: Identifiable, Sendable {
    let id: Int
    let label: String
    let lowerBound: Double
    let consumption: Double
    let distance: Double
    let drives: Int
}

/// One drive placed by how far it went and what it used.
struct AnalyticsConsumptionPoint: Identifiable, Sendable {
    let id: Int
    let distance: Double
    let consumption: Double
    let temperature: Double?
}

/// A calendar month's totals.
struct AnalyticsMonthlyPoint: Identifiable, Sendable {
    let month: Date
    let distance: Double
    let chargingEnergy: Double
    let chargingCost: Double
    let consumption: Double?
    let drives: Int
    let charges: Int
    var id: Date { month }
}

struct AnalyticsOdometerPoint: Identifiable, Sendable {
    let id: Int
    let date: Date
    let odometer: Double
}

/// Where the period went: driving, charging, or standing still.
struct AnalyticsTimeSplit: Sendable {
    let drivingMinutes: Int
    let chargingMinutes: Int
    let spanMinutes: Int

    var idleMinutes: Int { max(spanMinutes - drivingMinutes - chargingMinutes, 0) }
    var isMeasurable: Bool { spanMinutes > 0 }

    func share(_ minutes: Int) -> Double {
        spanMinutes > 0 ? Double(minutes) / Double(spanMinutes) : 0
    }
}

struct AnalyticsCoverage: Sendable {
    let drives: Int
    let drivesWithDistance: Int
    let drivesWithEfficiency: Int
    let charges: Int
    let chargesWithEnergy: Int
    let chargesWithCost: Int
    let latestActivity: Date?
}

struct AnalyticsDashboardSnapshot: Sendable {
    let summary: AnalyticsSnapshot
    let previousSummary: AnalyticsSnapshot?
    let dailyDriving: [AnalyticsDailyDrivePoint]
    let dailyCharging: [AnalyticsDailyChargePoint]
    let weekdayActivity: [AnalyticsCategoryPoint]
    let timeOfDayMix: [AnalyticsCategoryPoint]
    let destinations: [AnalyticsCategoryPoint]
    let chargingLocations: [AnalyticsCategoryPoint]
    let efficiencyTrend: [AnalyticsEfficiencyPoint]
    let chargeRelationships: [AnalyticsChargeRelationshipPoint]
    let efficiencyByTemperature: [AnalyticsTemperaturePoint]
    let consumptionByDistance: [AnalyticsConsumptionPoint]
    let monthly: [AnalyticsMonthlyPoint]
    let odometerTrail: [AnalyticsOdometerPoint]
    let timeSplit: AnalyticsTimeSplit
    let coverage: AnalyticsCoverage
}

struct AnalyticsDashboardBuilder {
    var calendar = Calendar.current
    /// How wide an outside-temperature band is, in the server's unit. Five
    /// degrees is a readable band in Celsius and far too narrow in Fahrenheit.
    var temperatureBucketWidth: Double = 5

    func make(
        drives: [AnalyticsDriveSample],
        charges: [AnalyticsChargeSample],
        window: AnalyticsTimeWindow
    ) -> AnalyticsDashboardSnapshot {
        let selectedDrives = drives.filter { includes($0.date, in: window.current) }
        let selectedCharges = charges.filter { includes($0.date, in: window.current) }
        let previousDrives = window.previous.map { range in drives.filter { range.contains($0.date) } }
        let previousCharges = window.previous.map { range in charges.filter { range.contains($0.date) } }

        return AnalyticsDashboardSnapshot(
            summary: summary(drives: selectedDrives, charges: selectedCharges),
            previousSummary: previousDrives.map { priorDrives in
                summary(drives: priorDrives, charges: previousCharges ?? [])
            },
            dailyDriving: dailyDriving(selectedDrives),
            dailyCharging: dailyCharging(selectedCharges),
            weekdayActivity: weekdayActivity(selectedDrives),
            timeOfDayMix: timeOfDayMix(selectedDrives),
            destinations: rankedPlaces(selectedDrives.compactMap(\.destination)),
            chargingLocations: rankedChargingLocations(selectedCharges),
            efficiencyTrend: selectedDrives.compactMap { drive in
                drive.efficiency.map { AnalyticsEfficiencyPoint(id: drive.id, date: drive.date, value: $0, distance: drive.distance) }
            }.sorted { $0.date < $1.date },
            chargeRelationships: selectedCharges.compactMap { charge in
                guard let energy = charge.energy, energy > 0, let cost = charge.cost else { return nil }
                return AnalyticsChargeRelationshipPoint(
                    id: charge.id,
                    energy: energy,
                    cost: cost,
                    location: shortPlace(charge.location)
                )
            },
            efficiencyByTemperature: efficiencyByTemperature(selectedDrives),
            consumptionByDistance: selectedDrives.compactMap { drive in
                guard let distance = drive.distance, distance > 0, let consumption = drive.efficiency,
                      consumption > 0 else { return nil }
                return AnalyticsConsumptionPoint(
                    id: drive.id, distance: distance, consumption: consumption, temperature: drive.temperature
                )
            },
            monthly: monthly(drives: selectedDrives, charges: selectedCharges),
            odometerTrail: odometerTrail(selectedDrives),
            timeSplit: timeSplit(drives: selectedDrives, charges: selectedCharges, window: window),
            coverage: coverage(drives: selectedDrives, charges: selectedCharges)
        )
    }

    /// Consumption averaged inside fixed temperature bands.
    ///
    /// Weighted by distance rather than by drive, because a two-mile trip from
    /// cold and a hundred-mile motorway run are not one observation each: the
    /// short one is nearly all warm-up and would drag a plain mean with it.
    private func efficiencyByTemperature(_ drives: [AnalyticsDriveSample]) -> [AnalyticsTemperaturePoint] {
        let width = max(temperatureBucketWidth, 1)
        let usable = drives.filter { $0.temperature != nil && ($0.efficiency ?? 0) > 0 && ($0.distance ?? 0) > 0 }
        let groups = Dictionary(grouping: usable) { drive in
            Int((drive.temperature! / width).rounded(.down))
        }
        return groups.map { band, values in
            let distance = values.compactMap(\.distance).reduce(0, +)
            let energy = values.reduce(0.0) { total, drive in
                total + (drive.efficiency ?? 0) * (drive.distance ?? 0)
            }
            let lower = Double(band) * width
            return AnalyticsTemperaturePoint(
                id: band,
                label: "\(Int(lower))–\(Int(lower + width))°",
                lowerBound: lower,
                consumption: distance > 0 ? energy / distance : 0,
                distance: distance,
                drives: values.count
            )
        }
        .sorted { $0.lowerBound < $1.lowerBound }
    }

    private func monthly(drives: [AnalyticsDriveSample], charges: [AnalyticsChargeSample]) -> [AnalyticsMonthlyPoint] {
        func month(_ date: Date) -> Date {
            calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        }
        let driveGroups = Dictionary(grouping: drives) { month($0.date) }
        let chargeGroups = Dictionary(grouping: charges) { month($0.date) }
        let months = Set(driveGroups.keys).union(chargeGroups.keys)
        return months.map { start in
            let monthDrives = driveGroups[start] ?? []
            let monthCharges = chargeGroups[start] ?? []
            let distance = monthDrives.compactMap(\.distance).reduce(0, +)
            let weighted = monthDrives.reduce(0.0) { total, drive in
                guard let consumption = drive.efficiency, let travelled = drive.distance else { return total }
                return total + consumption * travelled
            }
            let measured = monthDrives
                .filter { $0.efficiency != nil }
                .compactMap(\.distance)
                .reduce(0, +)
            return AnalyticsMonthlyPoint(
                month: start,
                distance: distance,
                chargingEnergy: monthCharges.compactMap(\.energy).reduce(0, +),
                chargingCost: monthCharges.compactMap(\.cost).reduce(0, +),
                consumption: measured > 0 ? weighted / measured : nil,
                drives: monthDrives.count,
                charges: monthCharges.count
            )
        }
        .sorted { $0.month < $1.month }
    }

    /// The odometer as it read at the end of each drive that reported one.
    private func odometerTrail(_ drives: [AnalyticsDriveSample]) -> [AnalyticsOdometerPoint] {
        drives
            .compactMap { drive in
                drive.odometer.map { AnalyticsOdometerPoint(id: drive.id, date: drive.date, odometer: $0) }
            }
            .sorted { $0.date < $1.date }
    }

    /// How the period divided between driving, charging and standing still.
    ///
    /// The span is the selected window, clipped to now so a month that has not
    /// finished is not reported as mostly idle before it happens.
    private func timeSplit(
        drives: [AnalyticsDriveSample],
        charges: [AnalyticsChargeSample],
        window: AnalyticsTimeWindow,
        now: Date = .now
    ) -> AnalyticsTimeSplit {
        let dates = drives.map(\.date) + charges.map(\.date)
        let start = window.current?.lowerBound ?? dates.min()
        let end = min(window.current?.upperBound ?? now, now)
        let span: Int = {
            guard let start, end > start else { return 0 }
            return Int(end.timeIntervalSince(start) / 60)
        }()
        return AnalyticsTimeSplit(
            drivingMinutes: drives.compactMap(\.durationMinutes).reduce(0, +),
            chargingMinutes: charges.compactMap(\.durationMinutes).reduce(0, +),
            spanMinutes: span
        )
    }

    private func includes(_ date: Date, in range: Range<Date>?) -> Bool {
        range?.contains(date) ?? true
    }

    private func summary(drives: [AnalyticsDriveSample], charges: [AnalyticsChargeSample]) -> AnalyticsSnapshot {
        let distances = drives.compactMap(\.distance)
        let energies = charges.compactMap(\.energy)
        let costs = charges.compactMap(\.cost)
        let efficiencies = drives.compactMap(\.efficiency)
        let distance = distances.isEmpty ? nil : distances.reduce(0, +)
        let energy = energies.isEmpty ? nil : energies.reduce(0, +)
        let cost = costs.isEmpty ? nil : costs.reduce(0, +)
        return AnalyticsSnapshot(
            distance: distance,
            drivingMinutes: drives.compactMap(\.durationMinutes).reduce(0, +),
            driveCount: drives.count,
            averageTripDistance: distance.map { $0 / Double(max(distances.count, 1)) },
            chargingEnergy: energy,
            chargingCost: cost,
            averagePricePerKWh: (cost != nil && energy != nil && energy! > 0) ? cost! / energy! : nil,
            averageEfficiency: efficiencies.isEmpty ? nil : efficiencies.reduce(0, +) / Double(efficiencies.count)
        )
    }

    private func dailyDriving(_ drives: [AnalyticsDriveSample]) -> [AnalyticsDailyDrivePoint] {
        Dictionary(grouping: drives) { calendar.startOfDay(for: $0.date) }
            .map { date, values in
                AnalyticsDailyDrivePoint(
                    date: date,
                    distance: values.compactMap(\.distance).reduce(0, +),
                    energy: values.compactMap(\.energy).reduce(0, +),
                    trips: values.count
                )
            }
            .sorted { $0.date < $1.date }
    }

    private func dailyCharging(_ charges: [AnalyticsChargeSample]) -> [AnalyticsDailyChargePoint] {
        Dictionary(grouping: charges) { calendar.startOfDay(for: $0.date) }
            .map { date, values in
                AnalyticsDailyChargePoint(
                    date: date,
                    energy: values.compactMap(\.energy).reduce(0, +),
                    cost: values.compactMap(\.cost).reduce(0, +),
                    sessions: values.count
                )
            }
            .sorted { $0.date < $1.date }
    }

    private func weekdayActivity(_ drives: [AnalyticsDriveSample]) -> [AnalyticsCategoryPoint] {
        let symbols = calendar.shortWeekdaySymbols
        let groups = Dictionary(grouping: drives) { calendar.component(.weekday, from: $0.date) }
        return (1...7).map { weekday in
            let values = groups[weekday] ?? []
            let label = symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : String(weekday)
            return AnalyticsCategoryPoint(
                id: "weekday-\(weekday)",
                label: label,
                value: values.compactMap(\.distance).reduce(0, +),
                count: values.count
            )
        }
    }

    private func timeOfDayMix(_ drives: [AnalyticsDriveSample]) -> [AnalyticsCategoryPoint] {
        let definitions: [(id: String, label: String, range: Range<Int>)] = [
            ("morning", "Morning", 5..<12),
            ("afternoon", "Afternoon", 12..<17),
            ("evening", "Evening", 17..<22),
            ("night", "Night", 22..<29)
        ]
        return definitions.map { definition in
            let values = drives.filter { drive in
                let hour = calendar.component(.hour, from: drive.date)
                let normalized = hour < 5 ? hour + 24 : hour
                return definition.range.contains(normalized)
            }
            return AnalyticsCategoryPoint(
                id: definition.id,
                label: definition.label,
                value: Double(values.count),
                count: values.count
            )
        }
    }

    private func rankedPlaces(_ places: [String]) -> [AnalyticsCategoryPoint] {
        let normalized = places.map { shortPlace($0) }
        let groups = Dictionary(grouping: normalized, by: { $0 })
        let values = groups.map { label, matches in
            AnalyticsCategoryPoint(id: label, label: label, value: Double(matches.count), count: matches.count)
        }
        let sorted = values.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.label < rhs.label : lhs.value > rhs.value
        }
        return Array(sorted.prefix(6))
    }

    private func rankedChargingLocations(_ charges: [AnalyticsChargeSample]) -> [AnalyticsCategoryPoint] {
        let groups = Dictionary(grouping: charges) { charge in shortPlace(charge.location) }
        let values = groups.map { label, matches in
            let energy = matches.compactMap(\.energy).reduce(0, +)
            return AnalyticsCategoryPoint(id: label, label: label, value: energy, count: matches.count)
        }
        let sorted = values.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.label < rhs.label : lhs.value > rhs.value
        }
        return Array(sorted.prefix(6))
    }

    private func coverage(drives: [AnalyticsDriveSample], charges: [AnalyticsChargeSample]) -> AnalyticsCoverage {
        AnalyticsCoverage(
            drives: drives.count,
            drivesWithDistance: drives.compactMap(\.distance).count,
            drivesWithEfficiency: drives.compactMap(\.efficiency).count,
            charges: charges.count,
            chargesWithEnergy: charges.compactMap(\.energy).count,
            chargesWithCost: charges.compactMap(\.cost).count,
            latestActivity: (drives.map(\.date) + charges.map(\.date)).max()
        )
    }

    private func shortPlace(_ value: String?) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return "Unreported" }
        return value.split(separator: ",", maxSplits: 1).first.map(String.init) ?? value
    }
}

enum DemoAnalyticsFactory {
    static func samples(now: Date = .now, calendar: Calendar = .current) -> (drives: [AnalyticsDriveSample], charges: [AnalyticsChargeSample]) {
        let destinations = ["Downtown", "Trailhead", "Airport", "Office", "Grocery"]
        let chargingLocations = ["Home", "Office garage", "Tesla Supercharger"]
        var drives: [AnalyticsDriveSample] = []
        var charges: [AnalyticsChargeSample] = []

        for dayOffset in 0..<62 {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
            if dayOffset % 5 != 0 {
                let hour = 7 + (dayOffset * 3) % 15
                let date = calendar.date(bySettingHour: hour, minute: 20, second: 0, of: day) ?? day
                let distance = 7.0 + Double((dayOffset * 11) % 39)
                drives.append(
                    AnalyticsDriveSample(
                        id: dayOffset * 10,
                        date: date,
                        distance: distance,
                        durationMinutes: Int(distance * 1.7) + 5,
                        energy: distance * (0.15 + Double(dayOffset % 5) * 0.006),
                        efficiency: 148 + Double((dayOffset * 7) % 34),
                        destination: destinations[dayOffset % destinations.count],
                        temperature: temperature(dayOffset: dayOffset),
                        odometer: odometer(dayOffset: dayOffset)
                    )
                )
                if dayOffset % 4 == 1 {
                    let secondDate = calendar.date(bySettingHour: 18, minute: 10, second: 0, of: day) ?? day
                    drives.append(
                        AnalyticsDriveSample(
                            id: dayOffset * 10 + 1,
                            date: secondDate,
                            distance: 5 + Double(dayOffset % 9),
                            durationMinutes: 18 + dayOffset % 12,
                            energy: 1.4 + Double(dayOffset % 4) * 0.3,
                            efficiency: 154 + Double((dayOffset * 5) % 27),
                            destination: destinations[(dayOffset + 2) % destinations.count],
                            temperature: temperature(dayOffset: dayOffset) + 2,
                            odometer: odometer(dayOffset: dayOffset) + 6
                        )
                    )
                }
            }

            if dayOffset % 2 == 0 {
                let energy = 14.0 + Double((dayOffset * 3) % 29)
                let locationIndex = dayOffset % chargingLocations.count
                let rate = locationIndex == 0 ? 0.17 : locationIndex == 1 ? 0.23 : 0.39
                charges.append(
                    AnalyticsChargeSample(
                        id: 10_000 + dayOffset,
                        date: calendar.date(bySettingHour: 21, minute: 30, second: 0, of: day) ?? day,
                        energy: energy,
                        cost: energy * rate,
                        durationMinutes: 42 + (dayOffset * 7) % 190,
                        location: chargingLocations[locationIndex]
                    )
                )
            }
        }

        return (drives.sorted { $0.date > $1.date }, charges.sorted { $0.date > $1.date })
    }

    /// A seasonal swing, so the consumption-against-temperature panel has a shape
    /// to show rather than one band.
    private static func temperature(dayOffset: Int) -> Double {
        14 + 12 * sin(Double(dayOffset) / 62 * 2 * .pi)
    }

    /// Counts up towards the demo car's odometer as the days approach today.
    private static func odometer(dayOffset: Int) -> Double {
        18_642 - Double(dayOffset) * 21
    }
}
