import Foundation

/// Where the battery will be, and when.
///
/// The question an owner standing at a charger is actually asking is "can I leave
/// in an hour, and with what?" — and the car answers a different one, giving a
/// single time to reach the limit and nothing in between.
///
/// The hard part is that charging is not one shape. On a wall box the rate is
/// flat: 7 kW at 20% and 7 kW at 79%, and a straight line is the truth. On a
/// Supercharger the rate falls away as the pack fills, and a straight line drawn
/// from the current rate promises an hour that will not happen — which is worse
/// than saying nothing, because someone plans around it.
///
/// So this does not invent a taper curve per model or per supplier. It fits one
/// number to two measurements the car itself provides: the rate right now, and
/// the time the car says it needs to reach the limit. If those two agree, the
/// rate is flat and the projection is a straight line. If the car says it needs
/// longer than the current rate implies, the difference *is* the taper, and the
/// rate is modelled as falling linearly with charge until the two agree.
struct ChargeProjection: Equatable, Sendable {
    /// Somewhere worth telling the owner about.
    struct Milestone: Identifiable, Equatable, Sendable {
        let percent: Double
        let date: Date
        var id: Double { percent }
    }

    /// When the projection was made. Everything is measured from here.
    let start: Date
    /// Charge now, percent.
    let level: Double
    /// Where charging stops, percent.
    let limit: Double
    /// Charge gained per hour at this instant, percent.
    let initialRate: Double
    /// How the rate changes per percent of charge added. Zero is a flat rate;
    /// negative is a taper.
    let decay: Double
    /// What the charger is delivering right now, kW. The forecast power curve is
    /// anchored on this.
    var referencePower: Double?

    /// Whether the rate is falling — which is what makes a straight-line estimate
    /// wrong, and worth saying out loud on screen.
    var isTapering: Bool { decay < -0.0001 }

    var isComplete: Bool { level >= limit - 0.001 }

    /// The rate at a given charge, percent per hour.
    func rate(at percent: Double) -> Double {
        max(initialRate + decay * (percent - level), 0)
    }

    /// The power the car will be drawing at a given charge, kW.
    ///
    /// Scaled from the power the charger reports *now*, in proportion to how the
    /// rate changes — not computed from pack size. Multiplying a percentage an
    /// hour by a capacity looks more principled and is worse: the pack's usable
    /// capacity is not its rated one, the charger's reported power includes
    /// losses the pack never sees, and the two disagree by tens of kilowatts. The
    /// result was a forecast line that started nowhere near the measured line it
    /// was supposed to continue — a visible discontinuity, at the exact point the
    /// reader is looking.
    ///
    /// Anchoring on the reading makes the two meet by construction, and reduces
    /// the claim to the one actually being made: power falls in the same
    /// proportion the rate does.
    func power(at percent: Double) -> Double? {
        guard let referencePower, referencePower > 0, initialRate > 0 else { return nil }
        return referencePower * rate(at: percent) / initialRate
    }

    /// Where the charge will be after a given interval.
    ///
    /// `s(t) = s0 + (r0 / k)(e^{kt} − 1)`, which is the integral of a rate that
    /// changes linearly with charge. With `k` at zero it degenerates to
    /// `s0 + r0·t`, the straight line.
    func level(after interval: TimeInterval) -> Double {
        guard initialRate > 0, interval > 0 else { return min(level, limit) }
        let hours = interval / 3_600
        let projected: Double
        if abs(decay) < 1e-9 {
            projected = level + initialRate * hours
        } else {
            projected = level + (initialRate / decay) * (exp(decay * hours) - 1)
        }
        return min(max(projected, level), limit)
    }

    /// When the charge will reach a given percent, if it ever does.
    ///
    /// `nil` rather than a far-future date for anything above the limit: the car
    /// stops there, so "when will it reach 90%" with an 80% limit has no answer,
    /// and inventing one would put a time on screen that never arrives.
    func date(reaching percent: Double) -> Date? {
        guard percent > level else { return start }
        guard percent <= limit + 0.001, initialRate > 0 else { return nil }
        let delta = percent - level
        let hours: Double
        if abs(decay) < 1e-9 {
            hours = delta / initialRate
        } else {
            let ratio = 1 + decay * delta / initialRate
            // The rate would reach zero before this charge does, so it never
            // arrives. Only reachable with a fit that has gone wrong.
            guard ratio > 0 else { return nil }
            hours = log(ratio) / decay
        }
        guard hours.isFinite, hours >= 0 else { return nil }
        return start.addingTimeInterval(hours * 3_600)
    }

    /// The round numbers between here and the limit, plus the limit itself.
    ///
    /// Milestones the car has already passed are not offered: a time in the past
    /// is not a plan.
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

    /// One point on the forecast line.
    struct Point: Identifiable, Equatable, Sendable {
        let id: Int
        let date: Date
        let percent: Double
        /// kW, where the pack size is known.
        let power: Double?
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
    ///   - observedRate: percent per hour measured from readings taken during
    ///     this session. Preferred over anything derived, because it is the only
    ///     figure that reflects what is actually happening at this charger, on
    ///     this pack, at this temperature.
    ///   - power: the charger's reported power, used only when there are not yet
    ///     enough readings to measure a rate.
    ///   - usableCapacity: the pack's usable capacity in kWh, for that fallback.
    ///   - hoursToFull: the car's own estimate of time to the limit. This is what
    ///     anchors the taper — Tesla computes it knowing its own charging curve.
    static func make(
        level: Double,
        limit: Double,
        observedRate: Double?,
        power: Double?,
        usableCapacity: Double?,
        hoursToFull: Double?,
        now: Date = .now
    ) -> ChargeProjection? {
        let limit = min(max(limit, 0), 100)
        let level = min(max(level, 0), 100)
        guard level < limit else {
            return ChargeProjection(
                start: now, level: level, limit: limit,
                initialRate: 0, decay: 0, referencePower: power
            )
        }

        let delta = limit - level
        let fromPower = derivedRate(power: power, usableCapacity: usableCapacity)
        // The car's estimate is a rate too, and a usable one when nothing has
        // been measured yet.
        let fromEstimate = (hoursToFull ?? 0) > 0 ? delta / (hoursToFull ?? 1) : nil
        guard let rate = observedRate ?? fromPower ?? fromEstimate, rate > 0 else { return nil }

        // Nothing to anchor a taper on: report the flat rate and let the screen
        // say that is what it is.
        guard let hours = hoursToFull, hours > 0 else {
            return ChargeProjection(
                start: now, level: level, limit: limit,
                initialRate: rate, decay: 0, referencePower: power
            )
        }

        let averageRate = delta / hours
        // The car expects to keep up, or to do better than, the current rate.
        // Trusting its endpoint is the honest move; there is no taper to model.
        guard averageRate < rate * 0.98 else {
            return ChargeProjection(
                start: now,
                level: level,
                limit: limit,
                initialRate: max(rate, averageRate),
                decay: 0,
                referencePower: power
            )
        }

        let decay = fitDecay(rate: rate, delta: delta, hours: hours)
        return ChargeProjection(
            start: now, level: level, limit: limit,
            initialRate: rate, decay: decay, referencePower: power
        )
    }

    /// Percent per hour implied by charger power against pack size.
    ///
    /// A rough figure — it ignores charging losses, which run about 10% on AC —
    /// and only used until real readings exist to measure instead.
    private static func derivedRate(power: Double?, usableCapacity: Double?) -> Double? {
        guard let power, power > 0, let usableCapacity, usableCapacity > 0 else { return nil }
        return (power / usableCapacity) * 100
    }

    /// Finds the rate decay that makes the model agree with the car's own
    /// estimate of when it will finish.
    ///
    /// Bisection rather than algebra: `t(k) = ln(1 + kΔ/r₀) / k` cannot be
    /// inverted in closed form, but it is continuous and strictly increasing as
    /// `k` falls, so twenty halvings put it well inside a second.
    private static func fitDecay(rate: Double, delta: Double, hours: Double) -> Double {
        // Below this the rate would hit zero before the limit did, and the charge
        // would never arrive.
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
