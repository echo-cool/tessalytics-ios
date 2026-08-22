import Foundation

/// The figures for the whole journey, kept apart from the charts' window.
///
/// `LiveTelemetryBuffer` is a rolling window: fifteen minutes, or twelve hundred
/// readings, whichever comes first. On a streaming drive that is about eight
/// minutes. Deriving "this drive" from it therefore made the figure quietly
/// become "this eight minutes" on any journey longer than that — a forty-mile
/// motorway run reporting twelve, under a label that said otherwise, with no
/// indication that anything had been dropped.
///
/// So the totals accumulate here as readings arrive and are never pruned. The
/// buffer keeps its window, because a chart of the last few minutes is what a
/// chart of a drive should be; the numbers beside it are about the drive.
///
/// One honest limitation, and it is inherent: this can only account for the part
/// of the drive the app was awake for. A drive joined halfway through starts
/// counting from where it was joined, which `startedAt` records so a view can say
/// so rather than overclaim.
struct LiveDriveTotals: Equatable, Sendable {
    /// The first reading of this drive.
    private(set) var startedAt: Date?
    /// The newest, so a view can say how long has been accounted for.
    private(set) var updatedAt: Date?

    private var firstOdometer: Double?
    private var lastOdometer: Double?
    /// Running integral of pack power, in kWh. Signed: regeneration reduces it.
    private var energy: Double?
    /// The previous power reading, for the trapezium step. A named type rather
    /// than a tuple so the whole value can stay `Equatable`, which is what lets
    /// Observation skip a redraw when nothing changed.
    private var lastPower: PowerReading?

    private struct PowerReading: Equatable, Sendable {
        let date: Date
        let value: Double
    }

    private(set) var maximumSpeed: Double?
    private(set) var maximumPower: Double?
    /// The deepest regeneration seen, as a positive number.
    private(set) var minimumPower: Double?

    /// The longest gap that is treated as continuous driving, in seconds.
    ///
    /// A stream that drops through a tunnel resumes with a reading minutes later.
    /// Integrating power across that gap would invent energy the car never drew;
    /// the distance is still correct, because the odometer counted it whether or
    /// not the phone was listening.
    static let maximumIntegrationGap: TimeInterval = 120

    var isEmpty: Bool { startedAt == nil }

    /// How long the app has been watching this drive.
    var elapsed: TimeInterval? {
        guard let startedAt, let updatedAt, updatedAt > startedAt else { return nil }
        return updatedAt.timeIntervalSince(startedAt)
    }

    /// Distance covered, in the server's length unit.
    ///
    /// Zero rather than nil once two odometer readings have arrived: two equal
    /// readings are a measurement of standing still, not an absence of one.
    var distance: Double? {
        guard let firstOdometer, let lastOdometer, lastOdometer >= firstOdometer else { return nil }
        return lastOdometer - firstOdometer
    }

    var energyUsed: Double? { energy }

    /// Regeneration peak, as a positive number.
    var maximumRegeneration: Double? {
        guard let minimumPower else { return nil }
        return abs(min(minimumPower, 0))
    }

    /// Net consumption, in Wh per unit of distance.
    var consumption: Double? {
        guard let distance, distance > 0.05, let energy, energy > 0 else { return nil }
        return energy * 1_000 / distance
    }

    /// Folds one reading in.
    mutating func record(
        odometer: Double?,
        speed: Double?,
        power: Double?,
        at date: Date = .now
    ) {
        if startedAt == nil { startedAt = date }
        updatedAt = date

        if let odometer {
            // Guards against a server that reports the odometer as 0 while it has
            // no reading, which would otherwise fix the start of the drive at
            // zero and report the whole odometer as this journey's distance.
            if odometer > 0 {
                if firstOdometer == nil { firstOdometer = odometer }
                // Monotonic: a reading that goes backwards is a bad sample, not a
                // car reversing forty miles.
                lastOdometer = max(lastOdometer ?? odometer, odometer)
            }
        }

        if let speed { maximumSpeed = max(maximumSpeed ?? speed, speed) }

        if let power {
            maximumPower = max(maximumPower ?? power, power)
            minimumPower = min(minimumPower ?? power, power)
            integrate(power: power, at: date)
        }
    }

    /// Trapezium rule over the reported power, which is the only way to get
    /// energy from a state stream: TeslaMate publishes instantaneous power and no
    /// running total.
    private mutating func integrate(power: Double, at date: Date) {
        defer { lastPower = PowerReading(date: date, value: power) }
        guard let previous = lastPower else { return }
        let seconds = date.timeIntervalSince(previous.date)
        guard seconds > 0, seconds <= Self.maximumIntegrationGap else { return }
        energy = (energy ?? 0) + (previous.value + power) / 2 * (seconds / 3_600)
    }

    mutating func reset() {
        self = LiveDriveTotals()
    }
}
