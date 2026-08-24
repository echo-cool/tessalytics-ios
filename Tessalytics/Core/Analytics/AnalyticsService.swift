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
    let coverage: AnalyticsCoverage
}

struct AnalyticsDashboardBuilder {
    var calendar = Calendar.current

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
            coverage: coverage(drives: selectedDrives, charges: selectedCharges)
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
                        destination: destinations[dayOffset % destinations.count]
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
                            destination: destinations[(dayOffset + 2) % destinations.count]
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
}
