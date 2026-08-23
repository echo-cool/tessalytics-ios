import Foundation

/// Where the battery will be, and when.
///
/// The question an owner standing at a charger is actually asking is "can I leave
/// in an hour, and with what?" — and the car answers a different one, giving a
/// single time to reach the limit and nothing in between.
///
/// Charging is not one shape, so this does not assume one. It picks between three,
/// on evidence:
///
/// - **A wall box holds its rate.** Below ten kilowatts the charger is the
///   constraint, not the pack: 7 kW at 20% and 7 kW at 79%. The line is straight
///   and the power is level, because that is what happens.
/// - **A fast charge tapers, and the car knows its own taper.** Above that, if the
///   app has watched this car fast-charge before, the shape comes from those
///   readings — real measurements of this pack — scaled to whatever the live
///   reading says it is doing now.
/// - **Otherwise, a fitted decay.** With no history to draw on, one parameter is
///   fitted to two things the car reports: the rate now, and the time it says it
///   needs. That was the whole model before there was a profile to learn from, and
///   it remains the fallback for a car the app has not seen fast-charge yet.
///
/// In every case the finishing time is anchored on the car's own estimate, which
/// is the one thing about the future the car is authoritative on.
struct ChargeProjection: Equatable, Sendable {
    /// How the rate behaves between here and the limit.
    enum Shape: Equatable, Sendable {
        /// Constant. A wall box, or a charge with nothing to suggest otherwise.
        case flat
        /// Flat below the knee, decaying above it. The fitted fallback.
        case knee(at: Double, decay: Double)
        /// Sampled from this car's own past charges, scaled to agree with the
        /// car's estimate for today.
        case learned(profile: ChargeCurveProfile, scale: Double)
    }

    /// Somewhere worth telling the owner about.
    struct Milestone: Identifiable, Equatable, Sendable {
        let percent: Double
        let date: Date
        var id: Double { percent }
    }

    /// One point on the forecast line.
    struct Point: Identifiable, Equatable, Sendable {
        let id: Int
        let date: Date
        let percent: Double
        /// kW, where the charger's current power is known.
        let power: Double?
    }

    /// When the projection was made. Everything is measured from here.
    let start: Date
    /// Charge now, percent.
    let level: Double
    /// Where charging stops, percent.
    let limit: Double
    /// Charge gained per hour at this instant, percent.
    let initialRate: Double
    let shape: Shape
    /// What the charger is delivering right now, kW. The power curve is anchored
    /// on this.
    var referencePower: Double?

    /// Below this the charger is the limit rather than the pack, and the rate holds
    /// for the whole session.
    static let wallBoxPowerKW: Double = 10
    /// Where a wall-box charge eases off, when one is modelled as bending at all.
    static let wallBoxKnee: Double = 90
    /// At or above this rate the pack is at a current the chemistry limits, so the
    /// taper has already begun. Percent per hour, which is a C-rate by another name.
    static let directCurrentRate: Double = 30

    /// Whether the rate is falling — worth saying out loud, because it is what
    /// makes a straight-line estimate wrong.
    var isTapering: Bool {
        switch shape {
        case .flat: false
        case .knee(_, let decay): decay < -0.0001
        case .learned: rate(at: min(limit, 100)) < initialRate * 0.97
        }
    }

    /// Whether the shape came from this car's own charging history.
    var isLearned: Bool {
        if case .learned = shape { return true }
        return false
    }

    /// The charge above which the rate starts falling, where that is meaningful.
    var knee: Double {
        if case .knee(let at, _) = shape { return at }
        return level
    }

    var isComplete: Bool { level >= limit - 0.001 }

    // MARK: - The curve

    /// The rate at a given charge, percent per hour.
    func rate(at percent: Double) -> Double {
        switch shape {
        case .flat:
            return initialRate
        case .knee(let at, let decay):
            guard percent > at else { return initialRate }
            return max(initialRate + decay * (percent - at), 0)
        case .learned(let profile, let scale):
            guard let relative = profile.relativeRate(at: percent, comparedWith: level) else {
                return initialRate
            }
            return max(initialRate * relative * scale, 0)
        }
    }

    /// The power the car will be drawing at a given charge, kW.
    ///
    /// Scaled from the power the charger reports *now*, in proportion to how the
    /// rate changes — not computed from pack size. Multiplying a percentage an hour
    /// by a capacity looks more principled and is worse: usable capacity is not
    /// rated capacity, and reported charger power includes losses the pack never
    /// sees. The two disagreed by tens of kilowatts, and the forecast line started
    /// nowhere near the measured line it was meant to continue.
    func power(at percent: Double) -> Double? {
        guard let referencePower, referencePower > 0, initialRate > 0 else { return nil }
        return referencePower * rate(at: percent) / initialRate
    }

    /// How long it takes to climb between two charges, in hours.
    ///
    /// Integrated numerically. A learned curve has no closed form, and one
    /// integrator serving every shape is worth more than three analytic special
    /// cases that have to be kept agreeing with each other.
    private func hours(from: Double, to: Double) -> Double {
        guard to > from else { return 0 }
        let step = 0.05
        var total = 0.0
        var percent = from
        while percent < to {
            let width = min(step, to - percent)
            // Midpoint, so a monotone curve is not systematically over- or
            // under-counted.
            let current = rate(at: percent + width / 2)
            guard current > 0 else { return .infinity }
            total += width / current
            percent += width
        }
        return total
    }

    /// Where the charge will be after a given interval.
    func level(after interval: TimeInterval) -> Double {
        guard initialRate > 0, interval > 0 else { return min(level, limit) }
        let target = interval / 3_600
        if case .flat = shape {
            return min(level + initialRate * target, limit)
        }
        var elapsed = 0.0
        var percent = level
        let step = 0.05
        while percent < limit {
            let current = rate(at: percent + step / 2)
            guard current > 0 else { break }
            let cost = step / current
            if elapsed + cost > target {
                return min(percent + step * (target - elapsed) / cost, limit)
            }
            elapsed += cost
            percent += step
        }
        return limit
    }

    /// When the charge will reach a given percent, if it ever does.
    ///
    /// `nil` rather than a far-future date for anything above the limit: the car
    /// stops there, so "when will it reach 90%" with an 80% limit has no answer,
    /// and inventing one would put a time on screen that never arrives.
    func date(reaching percent: Double) -> Date? {
        guard percent > level else { return start }
        guard percent <= limit + 0.001, initialRate > 0 else { return nil }
        let taken = hours(from: level, to: percent)
        guard taken.isFinite, taken >= 0 else { return nil }
        return start.addingTimeInterval(taken * 3_600)
    }

    /// The round numbers between here and the limit, plus the limit itself.
    ///
    /// Milestones the car has already passed are not offered: a time in the past is
    /// not a plan.
    func milestones(every step: Double = 10) -> [Milestone] {
        guard initialRate > 0, !isComplete else { return [] }
        var percents: [Double] = []
        var next = (floor(level / step) + 1) * step
        while next < limit - 0.001 {
            percents.append(next)
            next += step
        }
        percents.append(limit)
        return percents.compactMap { percent in
            date(reaching: percent).map { Milestone(percent: percent, date: $0) }
        }
    }

    /// The projected curve, for drawing.
    func curve(through interval: TimeInterval, step: TimeInterval = 300) -> [Point] {
        guard initialRate > 0, step > 0 else { return [] }
        var points: [Point] = []
        var elapsed: TimeInterval = 0
        var index = 0
        while elapsed <= interval {
            let projected = level(after: elapsed)
            points.append(
                Point(
                    id: index,
                    date: start.addingTimeInterval(elapsed),
                    percent: projected,
                    power: power(at: projected)
                )
            )
            index += 1
            if projected >= limit - 0.001 { break }
            elapsed += step
        }
        return points
    }

    /// How long until the limit, if the car gets there.
    var completesAt: Date? { date(reaching: limit) }
}

extension ChargeProjection {
    /// Builds a projection from what the car is reporting.
    ///
    /// - Parameters:
    ///   - observedRate: percent per hour measured from readings taken during this
    ///     session. Preferred over anything derived, because it is the only figure
    ///     reflecting what is happening at this charger, on this pack, at this
    ///     temperature.
    ///   - power: the charger's reported power. Tells a wall box from a fast
    ///     charge, anchors the power curve, and stands in for a rate before one can
    ///     be measured.
    ///   - usableCapacity: the pack's usable capacity in kWh, for that last
    ///     fallback only.
    ///   - hoursToFull: the car's own estimate of time to the limit. Anchors every
    ///     shape that bends.
    ///   - profile: what the app has learned about how this car fast-charges.
    static func make(
        level: Double,
        limit: Double,
        observedRate: Double?,
        power: Double?,
        usableCapacity: Double?,
        hoursToFull: Double?,
        profile: ChargeCurveProfile? = nil,
        now: Date = .now
    ) -> ChargeProjection? {
        let limit = min(max(limit, 0), 100)
        let level = min(max(level, 0), 100)
        guard level < limit else {
            return ChargeProjection(
                start: now, level: level, limit: limit,
                initialRate: 0, shape: .flat, referencePower: power
            )
        }

        let delta = limit - level
        let fromPower = derivedRate(power: power, usableCapacity: usableCapacity)
        let fromEstimate = (hoursToFull ?? 0) > 0 ? delta / (hoursToFull ?? 1) : nil
        guard let rate = observedRate ?? fromPower ?? fromEstimate, rate > 0 else { return nil }

        func flat(_ value: Double) -> ChargeProjection {
            ChargeProjection(
                start: now, level: level, limit: limit,
                initialRate: value, shape: .flat, referencePower: power
            )
        }

        // A wall box is the charger's limit, not the pack's, and it holds. Ten
        // kilowatts into any Tesla pack is under 0.15C — nothing about the
        // chemistry is being asked for at that current, so nothing tapers, and a
        // forecast that bends is inventing a slowdown the owner will not see.
        if let power, power > 0, power < wallBoxPowerKW {
            return flat(rate)
        }

        // Nothing to anchor a bend on: report the flat rate and let the screen say
        // that is what it is.
        guard let hours = hoursToFull, hours > 0 else { return flat(rate) }

        let averageRate = delta / hours
        // The car expects to keep up, or better. Trusting its endpoint is the
        // honest move, and there is no taper to model.
        guard averageRate < rate * 0.98 else { return flat(max(rate, averageRate)) }

        // This car's own taper, where the app has watched enough of one.
        if let profile, profile.covers(from: level, to: limit),
           let scale = fitLearnedScale(
               profile: profile, level: level, limit: limit, rate: rate, hours: hours
           ) {
            return ChargeProjection(
                start: now, level: level, limit: limit,
                initialRate: rate, shape: .learned(profile: profile, scale: scale),
                referencePower: power
            )
        }

        // No profile yet. Fit a decay, above a knee where the rate says the taper
        // has not begun.
        let knee = rate >= directCurrentRate ? level : max(level, wallBoxKnee)
        let effectiveKnee = knee >= limit ? level : knee
        let flatHours = max(effectiveKnee - level, 0) / rate
        guard flatHours < hours else { return flat(delta / hours) }

        let decay = fitDecay(rate: rate, delta: limit - effectiveKnee, hours: hours - flatHours)
        return ChargeProjection(
            start: now, level: level, limit: limit,
            initialRate: rate, shape: .knee(at: effectiveKnee, decay: decay),
            referencePower: power
        )
    }

    /// Percent per hour implied by charger power against pack size.
    ///
    /// Rough — it ignores charging losses, about 10% on AC — and used only until
    /// real readings exist to measure instead.
    private static func derivedRate(power: Double?, usableCapacity: Double?) -> Double? {
        guard let power, power > 0, let usableCapacity, usableCapacity > 0 else { return nil }
        return (power / usableCapacity) * 100
    }

    /// Scales a learned shape so its total time matches the car's estimate.
    ///
    /// The profile knows the shape of this car's taper. It does not know that today
    /// the pack is cold, or the cabinet is shared with the stall next door. One
    /// factor across the whole curve absorbs that without disturbing the shape.
    ///
    /// Returns `nil` when no factor in a sane range fits — which means the profile
    /// disagrees with today by more than conditions explain, and stretching it to
    /// fit would be using the wrong car's curve.
    private static func fitLearnedScale(
        profile: ChargeCurveProfile,
        level: Double,
        limit: Double,
        rate: Double,
        hours: Double
    ) -> Double? {
        func hoursTaken(_ scale: Double) -> Double {
            var total = 0.0
            var percent = level
            let step = 0.05
            while percent < limit {
                let width = min(step, limit - percent)
                guard let relative = profile.relativeRate(
                    at: percent + width / 2, comparedWith: level
                ) else { return .infinity }
                let current = rate * relative * scale
                guard current > 0 else { return .infinity }
                total += width / current
                percent += width
            }
            return total
        }

        let low = 0.4
        let high = 2.5
        guard hoursTaken(low) > hours, hoursTaken(high) < hours else { return nil }
        var lower = low
        var upper = high
        for _ in 0..<40 {
            let middle = (lower + upper) / 2
            if hoursTaken(middle) > hours { lower = middle } else { upper = middle }
        }
        return (lower + upper) / 2
    }

    /// Finds the rate decay that makes the model agree with the car's own estimate
    /// of when it will finish.
    ///
    /// Bisection rather than algebra: `t(k) = ln(1 + kD/r0)/k` cannot be inverted in
    /// closed form, but it is continuous and strictly increasing as `k` falls.
    private static func fitDecay(rate: Double, delta: Double, hours: Double) -> Double {
        let floorDecay = -rate / delta
        var low = floorDecay * 0.999
        var high = 0.0

        func hoursTaken(_ decay: Double) -> Double {
            guard abs(decay) > 1e-9 else { return delta / rate }
            let ratio = 1 + decay * delta / rate
            guard ratio > 0 else { return .infinity }
            return log(ratio) / decay
        }

        for _ in 0..<60 {
            let middle = (low + high) / 2
            if hoursTaken(middle) > hours { low = middle } else { high = middle }
        }
        return (low + high) / 2
    }
}
