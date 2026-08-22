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
    var elevation: Double?
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
        longitude: Double? = nil,
        elevation: Double? = nil
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
            longitude: longitude,
            elevation: elevation
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

    /// The samples thinned for a chart, with the newest always among them.
    ///
    /// A chart here is a few hundred points wide, and the buffer holds thousands
    /// of readings by the end of a drive. Drawing all of them puts several marks
    /// in every pixel and re-lays out every one of them on every reading, two or
    /// three times a second — which is how a live chart ends up costing the live
    /// numbers beside it the responsiveness they exist for.
    func plotted(limit: Int = 180) -> [LiveTelemetrySample] {
        Self.thinned(samples, limit: limit)
    }

    /// The readings from the last `window` seconds, measured back from the newest
    /// one rather than from now: a stream that has gone quiet should leave the
    /// last minute of a drive on screen, not empty the chart.
    func samples(within window: TimeInterval) -> [LiveTelemetrySample] {
        guard let newest = samples.last?.date else { return [] }
        let cutoff = newest.addingTimeInterval(-window)
        return samples.filter { $0.date >= cutoff }
    }

    /// The same, thinned for a chart of the chosen length.
    func plotted(within window: TimeInterval, limit: Int = 180) -> [LiveTelemetrySample] {
        Self.thinned(samples(within: window), limit: limit)
    }

    private static func thinned(_ samples: [LiveTelemetrySample], limit: Int) -> [LiveTelemetrySample] {
        guard limit > 1, samples.count > limit else { return samples }
        let step = Int((Double(samples.count) / Double(limit)).rounded(.up))
        var thinned = samples.enumerated().compactMap { $0.offset.isMultiple(of: step) ? $0.element : nil }
        // The right-hand edge of a live chart has to be the newest reading, which
        // an even stride only lands on by luck.
        if let last = samples.last, thinned.last?.id != last.id { thinned.append(last) }
        return thinned
    }

    var maximumSpeed: Double? { samples.compactMap(\.speed).max() }

    var maximumPower: Double? { samples.compactMap(\.power).max() }

    /// Regeneration peak, as a positive number.
    ///
    /// Zero when the car never regenerated but power was being read. A drive with
    /// no regeneration in it is a fact; "unavailable" would say the app could not
    /// tell, which is a different and wrong claim.
    var maximumRegeneration: Double? {
        guard let lowest = samples.compactMap(\.power).min() else { return nil }
        return abs(min(lowest, 0))
    }

    /// Distance covered within the window, from the odometer's own readings.
    ///
    /// Zero while the car has not moved yet, rather than unknown: two odometer
    /// readings the same is a measurement of standing still.
    var distance: Double? {
        let readings = samples.compactMap(\.odometer)
        guard let first = readings.first, let last = readings.last, last >= first else { return nil }
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
        // A window that was all gaps has nothing to report; a window that was
        // integrated and came to nothing reports nothing used, which is zero.
        var integrated = false
        for (previous, current) in zip(readings, readings.dropFirst()) {
            let hours = current.0.timeIntervalSince(previous.0) / 3_600
            // A gap means the stream dropped, not that the car drew power for the
            // whole interval; anything over two minutes is not integrated.
            guard hours > 0, hours < 2.0 / 60 else { continue }
            integrated = true
            total += (previous.1 + current.1) / 2 * hours
        }
        return integrated ? total : nil
    }

    /// Net consumption over the window, in Wh per unit of distance.
    func consumption(distanceUnitIsMiles _: Bool = true) -> Double? {
        guard let distance, distance > 0.05, let energyUsed, energyUsed > 0 else { return nil }
        return energyUsed * 1_000 / distance
    }

    /// The positions seen, oldest first, for the live map's route.
    var trail: [(latitude: Double, longitude: Double)] {
        routePath.map { ($0.latitude, $0.longitude) }
    }

    /// The same as coordinates, which is what the route is assembled from.
    ///
    /// Not thinned here. Thinning by index changes which points survive every
    /// time the buffer grows past a multiple of the limit, which redraws the whole
    /// line rather than extending it; `LiveRouteTrail` thins by distance instead,
    /// where a point once drawn stays where it was put.
    var routePath: [CoordinateDTO] {
        samples.compactMap { sample in
            guard let latitude = sample.latitude, let longitude = sample.longitude,
                  abs(latitude) > 0.0001 || abs(longitude) > 0.0001 else { return nil }
            return CoordinateDTO(latitude: latitude, longitude: longitude)
        }
    }

    var span: TimeInterval? {
        guard let first = samples.first?.date, let last = samples.last?.date, last > first else { return nil }
        return last.timeIntervalSince(first)
    }
}
