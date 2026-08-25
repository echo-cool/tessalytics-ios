import Foundation

/// One stretch the car spent parked between two recorded events.
///
/// TeslaMate's own vampire-drain panel measures the same thing the same way: it
/// has no "parked" table either, so the loss is what the level had fallen by the
/// next time the car did something.
struct StandbyPeriod: Identifiable, Equatable, Sendable {
    let id: Int
    let start: Date
    let end: Date
    /// Percentage points of charge lost while parked.
    let levelLost: Double
    /// Rated range lost, in the server's length unit.
    let rangeLost: Double?

    var hours: Double { max(end.timeIntervalSince(start) / 3600, 0) }
    var percentPerDay: Double { hours > 0 ? levelLost / hours * 24 : 0 }
    var rangePerDay: Double? { hours > 0 ? rangeLost.map { $0 / hours * 24 } : nil }
}

/// Standby loss, rebuilt from the gaps between drives and charges.
enum StandbyDrainModel {
    /// One end of a recorded activity, with what the car read at that moment.
    private struct Reading {
        let date: Date
        let level: Double
        let range: Double?
    }

    private struct Activity {
        let start: Reading
        let end: Reading
    }

    /// Parked stretches long enough to measure.
    ///
    /// - Short gaps are excluded: a 20-minute stop loses less charge than the
    ///   reported level's own resolution, and dividing that by the gap produces
    ///   double-digit daily rates out of rounding alone.
    /// - Gaps longer than the ceiling are excluded too, because they are usually
    ///   a logger that was down rather than a car that sat still.
    /// - A level that rose is dropped: it was charged somewhere TeslaMate did not
    ///   see, and calling that negative drain would flatter the average.
    static func periods(
        drives: [DriveRecord],
        charges: [ChargeRecord],
        minimumHours: Double = 6,
        maximumHours: Double = 24 * 14
    ) -> [StandbyPeriod] {
        var activities: [Activity] = []

        for drive in drives {
            guard let start = drive.startDate, let end = drive.endDate,
                  let startLevel = drive.startLevel, let endLevel = drive.endLevel else { continue }
            activities.append(
                Activity(
                    start: Reading(date: start, level: Double(startLevel), range: drive.startRatedRange),
                    end: Reading(date: end, level: Double(endLevel), range: drive.endRatedRange)
                )
            )
        }
        for charge in charges {
            guard let start = charge.startDate, let end = charge.endDate,
                  let startLevel = charge.startLevel, let endLevel = charge.endLevel else { continue }
            activities.append(
                Activity(
                    start: Reading(date: start, level: Double(startLevel), range: charge.startRatedRange),
                    end: Reading(date: end, level: Double(endLevel), range: charge.endRatedRange)
                )
            )
        }

        let ordered = activities.sorted { $0.start.date < $1.start.date }
        var periods: [StandbyPeriod] = []
        var index = 0
        for pair in zip(ordered, ordered.dropFirst()) {
            let parked = pair.0.end
            let woken = pair.1.start
            let hours = woken.date.timeIntervalSince(parked.date) / 3600
            guard hours >= minimumHours, hours <= maximumHours else { continue }
            let lost = parked.level - woken.level
            guard lost >= 0 else { continue }
            let rangeLost: Double? = {
                guard let before = parked.range, let after = woken.range, before >= after else { return nil }
                return before - after
            }()
            periods.append(
                StandbyPeriod(id: index, start: parked.date, end: woken.date, levelLost: lost, rangeLost: rangeLost)
            )
            index += 1
        }
        return periods
    }

    /// The typical daily loss.
    ///
    /// A median rather than a mean: one period spanning a cold week with Sentry
    /// on is an order of magnitude above the rest and would carry an average on
    /// its own.
    static func medianPercentPerDay(_ periods: [StandbyPeriod]) -> Double? {
        let values = periods.map(\.percentPerDay).sorted()
        guard !values.isEmpty else { return nil }
        let middle = values.count / 2
        return values.count.isMultiple(of: 2) ? (values[middle - 1] + values[middle]) / 2 : values[middle]
    }

    static func medianRangePerDay(_ periods: [StandbyPeriod]) -> Double? {
        let values = periods.compactMap(\.rangePerDay).sorted()
        guard !values.isEmpty else { return nil }
        let middle = values.count / 2
        return values.count.isMultiple(of: 2) ? (values[middle - 1] + values[middle]) / 2 : values[middle]
    }
}
