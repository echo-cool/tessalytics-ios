import Foundation

/// How this particular car charges, learned from watching it charge.
///
/// A fast charge tapers, and the shape of that taper is a property of the pack,
/// its chemistry, its age and how the car chooses to treat it. No table anyone
/// could ship would be right for every one of those, and the earlier model — a
/// rate falling linearly with charge — was a placeholder for a curve nobody had.
///
/// The car has that curve. It drives it every time it fast-charges, and the app
/// is already watching. So this accumulates mean charging power against state of
/// charge, in buckets, across every DC session it sees, and hands back a *shape*:
/// how the rate at one charge compares with the rate at another. Scale is not its
/// business — the live reading supplies that, because a cold pack or a shared
/// cabinet changes the height of the curve without changing its shape.
struct ChargeCurveProfile: Codable, Equatable, Sendable {
    /// Percent of charge per bucket. Five keeps twenty buckets across the pack,
    /// which is fine enough to see a taper and coarse enough to fill up quickly.
    static let bucketWidth = 5
    /// Below this the samples are a wall box, whose shape is flat and which would
    /// drag the learned curve towards a straight line it does not have.
    static let minimumPowerKW: Double = 10
    /// Readings a bucket needs before it is trusted.
    static let minimumSamples = 3
    /// Buckets above the current charge needed before the profile is preferred
    /// over the fitted fallback.
    static let minimumCoverage = 3

    private(set) var buckets: [Int: Bucket] = [:]

    struct Bucket: Codable, Equatable, Sendable {
        var total: Double
        var count: Int
        var mean: Double { count > 0 ? total / Double(count) : 0 }
    }

    static func bucket(for level: Double) -> Int {
        Int((level / Double(bucketWidth)).rounded(.down))
    }

    /// Folds one reading in.
    mutating func record(level: Double, power: Double) {
        guard power >= Self.minimumPowerKW, level >= 0, level <= 100 else { return }
        let key = Self.bucket(for: level)
        var bucket = buckets[key] ?? Bucket(total: 0, count: 0)
        bucket.total += power
        bucket.count += 1
        buckets[key] = bucket
    }

    mutating func record(samples: [(level: Double, power: Double?)]) {
        for sample in samples {
            guard let power = sample.power else { continue }
            record(level: sample.level, power: power)
        }
    }

    /// Mean power seen at a charge, kW, where enough has been seen to say.
    func power(at level: Double) -> Double? {
        guard let bucket = buckets[Self.bucket(for: level)],
              bucket.count >= Self.minimumSamples else { return nil }
        return bucket.mean
    }

    /// Whether this profile has enough above a given charge to describe the rest
    /// of the session.
    ///
    /// Coverage below where the car is now is no use: the question is what happens
    /// between here and the limit, and a profile full of readings from the bottom
    /// of the pack says nothing about the top.
    func covers(from level: Double, to limit: Double) -> Bool {
        guard power(at: level) != nil else { return false }
        let first = Self.bucket(for: level) + 1
        let last = Self.bucket(for: min(limit, 100) - 0.001)
        guard last >= first else { return true }
        let filled = (first...last).filter { key in
            (buckets[key]?.count ?? 0) >= Self.minimumSamples
        }.count
        return filled >= min(Self.minimumCoverage, last - first + 1)
    }

    /// The rate at one charge relative to the rate at another, from the shape.
    ///
    /// `nil` where either end is unknown. Interpolated between bucket centres so
    /// a forecast does not step down in five-percent slabs, and held flat beyond
    /// the last bucket that has readings rather than extrapolated — a taper
    /// extended past the evidence heads for zero and predicts a charge that never
    /// finishes.
    func relativeRate(at level: Double, comparedWith reference: Double) -> Double? {
        guard let base = interpolatedPower(at: reference), base > 0,
              let value = interpolatedPower(at: level), value > 0 else { return nil }
        return value / base
    }

    private func interpolatedPower(at level: Double) -> Double? {
        let usable = buckets.filter { $0.value.count >= Self.minimumSamples }
        guard !usable.isEmpty else { return nil }
        let centre = level / Double(Self.bucketWidth) - 0.5
        let lower = Int(centre.rounded(.down))
        let upper = lower + 1

        switch (usable[lower]?.mean, usable[upper]?.mean) {
        case let (low?, high?):
            let fraction = centre - Double(lower)
            return low + (high - low) * fraction
        case let (low?, nil):
            return low
        case let (nil, high?):
            return high
        default:
            // Outside the readings entirely: hold the nearest known bucket rather
            // than extrapolate a taper towards zero.
            guard let nearest = usable.min(by: { abs($0.key - lower) < abs($1.key - lower) }) else { return nil }
            return nearest.value.mean
        }
    }

    /// How many readings this profile is built from, for the screen that explains
    /// where a forecast came from.
    var sampleCount: Int { buckets.values.reduce(0) { $0 + $1.count } }

    var isEmpty: Bool { buckets.isEmpty }

    // MARK: - Storage

    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    static func decoded(from data: Data?) -> ChargeCurveProfile? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(ChargeCurveProfile.self, from: data)
    }
}
