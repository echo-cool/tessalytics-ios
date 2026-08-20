import Foundation

/// One live reading, kept in memory for the duration of a drive.
struct LiveTelemetrySample: Identifiable, Equatable, Sendable {
    let id: Int
    let date: Date
    let speed: Double?
    let power: Double?
    let level: Double?
    let odometer: Double?
    let latitude: Double?
    let longitude: Double?
}

/// A rolling window of live readings, for the charts shown while driving.
///
/// Deliberately memory-only. These are seconds-resolution samples that matter for
/// the length of a journey and never again, and writing them to SwiftData would
/// mean thousands of rows per drive competing with the history sync for the same
/// store — to redraw a chart that is discarded when the car parks.
struct LiveTelemetryBuffer: Equatable, Sendable {
    /// How much of the recent past the charts show.
    static let window: TimeInterval = 15 * 60
    /// A hard ceiling, so a fault that pushes readings in a tight loop cannot grow
    /// this without bound.
    static let capacity = 1_200

    private(set) var samples: [LiveTelemetrySample] = []
    private var nextID = 0

    mutating func append(
        date: Date = .now,
        speed: Double?,
        power: Double?,
        level: Double?,
        odometer: Double?,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        // Nothing to plot and nothing to integrate: an event that carried no
        // driving reading would otherwise pad the buffer with blanks.
        guard speed != nil || power != nil || level != nil else { return }

        let sample = LiveTelemetrySample(
            id: samples.last.map { abs($0.date.timeIntervalSince(date)) < 0.25 ? $0.id : nextID } ?? nextID,
            date: date,
            speed: speed,
            power: power,
            level: level,
            odometer: odometer,
            latitude: latitude,
            longitude: longitude
        )
        // A repeated instant would put two marks on one x position.
        if let last = samples.last, abs(last.date.timeIntervalSince(date)) < 0.25 {
            samples[samples.count - 1] = sample
            return
        }

        samples.append(sample)
        nextID += 1
        prune(now: date)
    }

    mutating func reset() {
        samples.removeAll()
        nextID = 0
    }

    private mutating func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.window)
        if let first = samples.first, first.date < cutoff {
            samples.removeAll { $0.date < cutoff }
        }
        if samples.count > Self.capacity {
            samples.removeFirst(samples.count - Self.capacity)
        }
    }

    // MARK: - Derived figures

    var latest: LiveTelemetrySample? { samples.last }

    var maximumSpeed: Double? { samples.compactMap(\.speed).max() }

    var maximumPower: Double? { samples.compactMap(\.power).max() }

    /// Regeneration peak, as a positive number.
    var maximumRegeneration: Double? {
        samples.compactMap(\.power).min().map { min($0, 0) }.map(abs).flatMap { $0 > 0 ? $0 : nil }
    }

    /// Distance covered within the window, from the odometer's own readings.
    var distance: Double? {
        let readings = samples.compactMap(\.odometer)
        guard let first = readings.first, let last = readings.last, last > first else { return nil }
        return last - first
    }

    /// Energy through the pack over the window, kWh.
    ///
    /// Integrated with the trapezium rule over the reported power, which is the
    /// only way to get this from a state stream: TeslaMate publishes instantaneous
    /// power and no running total. Regeneration counts against the figure, so this
    /// is net energy rather than energy drawn.
    var energyUsed: Double? {
        let readings = samples.compactMap { sample in sample.power.map { (sample.date, $0) } }
        guard readings.count > 1 else { return nil }
        var total = 0.0
        for (previous, current) in zip(readings, readings.dropFirst()) {
            let hours = current.0.timeIntervalSince(previous.0) / 3_600
            // A gap means the stream dropped, not that the car drew power for the
            // whole interval; anything over two minutes is not integrated.
            guard hours > 0, hours < 2.0 / 60 else { continue }
            total += (previous.1 + current.1) / 2 * hours
        }
        return total != 0 ? total : nil
    }

    /// Net consumption over the window, in Wh per unit of distance.
    func consumption(distanceUnitIsMiles _: Bool = true) -> Double? {
        guard let distance, distance > 0.05, let energyUsed, energyUsed > 0 else { return nil }
        return energyUsed * 1_000 / distance
    }

    /// The positions seen, oldest first, for the live map's trail.
    var trail: [(latitude: Double, longitude: Double)] {
        samples.compactMap { sample in
            guard let latitude = sample.latitude, let longitude = sample.longitude,
                  abs(latitude) > 0.0001 || abs(longitude) > 0.0001 else { return nil }
            return (latitude, longitude)
        }
    }

    var span: TimeInterval? {
        guard let first = samples.first?.date, let last = samples.last?.date, last > first else { return nil }
        return last.timeIntervalSince(first)
    }
}
