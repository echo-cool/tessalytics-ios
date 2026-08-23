import Foundation

/// One reading taken while the car is charging.
struct LiveChargeSample: Identifiable, Equatable, Sendable {
    let id: Int
    let date: Date
    let level: Double
    let power: Double?
    let energyAdded: Double?
    let range: Double?
}

/// What has happened so far at this charger.
///
/// The counterpart of `LiveTelemetryBuffer` for a car that is standing still.
/// Memory-only for the same reason: these readings matter for the length of one
/// session and never again.
///
/// Its real job is to measure the charging rate. Everything else on the charging
/// card is a projection, and a projection built on the charger's nameplate power
/// is a guess — it ignores charging losses, a cold pack, a shared cabinet, and a
/// car that has decided to draw less than it could. A rate measured from the
/// car's own reported charge over the last few minutes has all of that in it
/// already.
struct LiveChargeSession: Equatable, Sendable {
    /// How far back the measured rate looks.
    ///
    /// Long enough that the 1% granularity of a reported charge level is not the
    /// dominant term — at 30 %/h a percent lands every two minutes — and short
    /// enough to follow a taper down rather than averaging across it.
    static let ratewindow: TimeInterval = 12 * 60
    /// A hard ceiling on samples held, so a fault that pushes readings in a tight
    /// loop cannot grow this without bound.
    static let capacity = 1_200
    /// The least spread of readings that can produce a rate worth showing.
    static let minimumSpan: TimeInterval = 3 * 60

    private(set) var samples: [LiveChargeSample] = []
    private(set) var startedAt: Date?
    private var nextID = 0

    var isEmpty: Bool { samples.isEmpty }

    mutating func record(
        date: Date = .now,
        level: Double?,
        power: Double?,
        energyAdded: Double?,
        range: Double?
    ) {
        guard let level else { return }
        if startedAt == nil { startedAt = date }

        let sample = LiveChargeSample(
            id: nextID,
            date: date,
            level: level,
            power: power,
            energyAdded: energyAdded,
            range: range
        )
        // A repeated instant would put two marks on one x position.
        if let last = samples.last, abs(last.date.timeIntervalSince(date)) < 0.25 {
            samples[samples.count - 1] = LiveChargeSample(
                id: last.id,
                date: date,
                level: level,
                power: power,
                energyAdded: energyAdded,
                range: range
            )
            return
        }
        nextID += 1
        samples.append(sample)
        if samples.count > Self.capacity { samples.removeFirst(samples.count - Self.capacity) }
    }

    mutating func reset() {
        samples = []
        startedAt = nil
        nextID = 0
    }

    /// Charge gained per hour, measured over the recent window.
    ///
    /// `nil` until there is enough spread to divide by. A rate computed across
    /// twenty seconds of a level reported in whole percent is either zero or
    /// enormous, and both would be shown to somebody as a plan.
    func observedRate(now: Date = .now) -> Double? {
        let window = samples.filter { now.timeIntervalSince($0.date) <= Self.ratewindow }
        guard let first = window.first, let last = window.last else { return nil }
        let seconds = last.date.timeIntervalSince(first.date)
        guard seconds >= Self.minimumSpan else { return nil }
        let gained = last.level - first.level
        // A level that has not moved yet is not evidence of a zero rate; it is
        // the reported percent not having ticked over.
        guard gained > 0 else { return nil }
        return gained / (seconds / 3_600)
    }

    /// Energy put in since the session began, kWh.
    var energyAdded: Double? { samples.last?.energyAdded }

    /// Charge gained since the session began, percentage points.
    var levelGained: Double? {
        guard let first = samples.first, let last = samples.last else { return nil }
        return max(last.level - first.level, 0)
    }

    /// Range gained since the session began, in the server's units.
    var rangeGained: Double? {
        guard let first = samples.first?.range, let last = samples.last?.range else { return nil }
        return max(last - first, 0)
    }

    /// Where the charge began, worked back from the energy the car says it has
    /// taken.
    ///
    /// The app only sees readings from the moment it is opened, so a car that has
    /// been on a charger for an hour arrives with a session that started a second
    /// ago. The car, though, reports how much energy it has put in since the cable
    /// went in — so the level at the start is recoverable even though the readings
    /// are not.
    ///
    /// Approximate, and knowingly so: reported energy includes charging losses the
    /// pack never received, so this reads a little low. It is drawn as an inferred
    /// segment rather than as measurement.
    static func inferredStartLevel(
        currentLevel: Double,
        energyAdded: Double?,
        usableCapacity: Double?
    ) -> Double? {
        guard let energyAdded, energyAdded > 0,
              let usableCapacity, usableCapacity > 0 else { return nil }
        let gained = energyAdded / usableCapacity * 100
        // More than the whole pack, or none of it, means one of the two figures is
        // not what it claims to be — and a start level below zero drawn on a chart
        // is worse than no line at all.
        guard gained > 0.5, gained < 100 else { return nil }
        return max(currentLevel - gained, 0)
    }

    var duration: TimeInterval? {
        guard let first = samples.first, let last = samples.last else { return nil }
        return last.date.timeIntervalSince(first.date)
    }
}
