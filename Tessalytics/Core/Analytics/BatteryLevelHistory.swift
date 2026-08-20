import Foundation

/// One reading of the battery level, and when it was taken.
struct BatteryLevelPoint: Identifiable, Equatable, Sendable {
    let id: Int
    let date: Date
    let level: Double
    /// True while the level was rising, which is what colours a charge apart from
    /// a drive on the chart.
    var isCharging = false
}

/// Battery level over time, rebuilt from drives and charges.
///
/// TeslaMate records no standalone level series, but every drive and charge notes
/// the level at each end. Interleaving those by time reconstructs the sawtooth an
/// owner recognises — the slow slide of a week's driving and the sharp climb of
/// each charge — without a single extra request.
enum BatteryLevelHistory {
    static func points(
        drives: [DriveRecord],
        charges: [ChargeRecord],
        since cutoff: Date,
        currentLevel: Int? = nil,
        now: Date = .now
    ) -> [BatteryLevelPoint] {
        var readings: [(date: Date, level: Double, charging: Bool)] = []

        for drive in drives {
            guard let start = drive.startDate, start >= cutoff else { continue }
            if let level = drive.startLevel { readings.append((start, Double(level), false)) }
            if let level = drive.endLevel, let end = drive.endDate {
                readings.append((end, Double(level), false))
            }
        }
        for charge in charges {
            guard let start = charge.startDate, start >= cutoff else { continue }
            if let level = charge.startLevel { readings.append((start, Double(level), true)) }
            if let level = charge.endLevel {
                // A charge's end level belongs at its end; without a recorded end
                // the start is the best anchor there is.
                readings.append((charge.endDate ?? start, Double(level), true))
            }
        }
        // The live reading closes the series, so the chart reaches "now" instead of
        // stopping at whatever happened last.
        if let currentLevel { readings.append((now, Double(currentLevel), false)) }

        let ordered = readings
            .filter { (0...100).contains($0.level) }
            .sorted { $0.date < $1.date }

        // Collapse readings that share an instant, which happens where a charge
        // ends and a drive begins: two points on one x position draw as a spike.
        var collapsed: [(date: Date, level: Double, charging: Bool)] = []
        for reading in ordered {
            if let last = collapsed.last, abs(last.date.timeIntervalSince(reading.date)) < 30 {
                collapsed[collapsed.count - 1] = reading
            } else {
                collapsed.append(reading)
            }
        }

        return collapsed.enumerated().map { index, reading in
            BatteryLevelPoint(id: index, date: reading.date, level: reading.level, isCharging: reading.charging)
        }
    }
}
