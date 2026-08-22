import Foundation

/// Turns the synced history into the handful of numbers an achievement is judged
/// on.
///
/// Kept separate from `FleetStatistics` on purpose: those figures exist to be
/// displayed and are in the server's own units, and an achievement measured in a
/// display unit would move when the owner changed a preference.
enum AchievementFactsBuilder {
    /// Drives that begin in this window count as night drives.
    static let nightHours: Range<Int> = 0..<4

    static func build(
        drives: [DriveRecord],
        charges: [ChargeRecord],
        battery: FleetStatistics.BatteryHealth?,
        placesVisited: Int,
        softwareVersions: Int,
        units: UnitsDTO?,
        calendar: Calendar = .current
    ) -> AchievementFacts {
        let toKilometres = Self.kilometreFactor(for: units)
        let distances = drives.compactMap(\.distance).filter { $0 > 0 }
        let startDates = drives.compactMap(\.startDate)

        var facts = AchievementFacts()
        facts.driveCount = drives.count
        facts.chargeCount = charges.count
        facts.distanceKilometres = distances.reduce(0, +) * toKilometres
        facts.longestDriveKilometres = (distances.max() ?? 0) * toKilometres
        facts.energyAddedKilowattHours = charges.compactMap(\.energyAdded).filter { $0 > 0 }.reduce(0, +)
        facts.batteryHealthPercent = battery?.healthPercent
        facts.placesVisited = placesVisited
        facts.softwareVersions = softwareVersions
        facts.nightDrives = startDates.count { nightHours.contains(calendar.component(.hour, from: $0)) }

        let days = Set(startDates.map { calendar.startOfDay(for: $0) })
        facts.daysDriven = days.count
        facts.longestDrivingStreak = longestStreak(ofDays: days, calendar: calendar)
        return facts
    }

    /// How many of the server's length units make a kilometre.
    ///
    /// TeslaMate stores distances in the unit the owner configured, and every
    /// achievement is measured in kilometres so a target cannot move when a
    /// preference does.
    static func kilometreFactor(for units: UnitsDTO?) -> Double {
        (units ?? .metricDefaults).lengthSymbol == "mi" ? 1.609_344 : 1
    }

    /// The longest run of consecutive calendar days in a set.
    ///
    /// Days rather than drives: four trips on Tuesday are one day of driving, and
    /// a streak that counted them as four would be a streak about errands.
    static func longestStreak(ofDays days: Set<Date>, calendar: Calendar = .current) -> Int {
        guard !days.isEmpty else { return 0 }
        let sorted = days.sorted()
        var longest = 1
        var current = 1
        for (previous, day) in zip(sorted, sorted.dropFirst()) {
            let gap = calendar.dateComponents([.day], from: previous, to: day).day ?? 0
            if gap == 1 {
                current += 1
                longest = max(longest, current)
            } else if gap > 1 {
                current = 1
            }
            // A gap of zero cannot happen — these are start-of-day values in a
            // set — but if it did, it is the same day and changes nothing.
        }
        return longest
    }
}
