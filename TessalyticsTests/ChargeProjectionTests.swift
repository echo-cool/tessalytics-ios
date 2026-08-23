import XCTest
@testable import Tessalytics

/// The number this produces is one somebody plans an hour of their life around,
/// so the thing worth testing is not that it returns something — it is that it
/// refuses to promise a straight line when the car has told it otherwise.
final class ChargeProjectionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - A flat rate

    /// A wall box holds its rate: 7 kW at 20% and 7 kW at 79%. A straight line is
    /// not an approximation here, it is what happens.
    func testAWallBoxProjectsAsAStraightLine() throws {
        let projection = try XCTUnwrap(
            ChargeProjection.make(
                level: 40, limit: 80,
                observedRate: 10,          // %/h
                power: 7, usableCapacity: 75,
                hoursToFull: 4,            // 40 points at 10 %/h — the two agree
                now: now
            )
        )
        XCTAssertFalse(projection.isTapering)
        XCTAssertEqual(projection.level(after: 3_600), 50, accuracy: 0.01)
        XCTAssertEqual(projection.level(after: 2 * 3_600), 60, accuracy: 0.01)
    }

    func testTheHourlyFigureStopsAtTheChargeLimit() throws {
        // The car stops at the limit. Projecting through it would put a number on
        // screen that the car will not produce.
        let projection = try XCTUnwrap(
            ChargeProjection.make(
                level: 75, limit: 80,
                observedRate: 30, power: nil, usableCapacity: nil,
                hoursToFull: 5.0 / 30.0,
                now: now
            )
        )
        XCTAssertEqual(projection.level(after: 3_600), 80, accuracy: 0.01)
    }

    // MARK: - A taper

    /// The case that makes a naive projection dangerous. The car is drawing hard
    /// right now but says it needs far longer than that rate implies to reach the
    /// limit — that gap is the taper, and the projection has to bend.
    func testASuperchargerThatSaysItWillTakeLongerIsModelledAsTapering() throws {
        let projection = try XCTUnwrap(
            ChargeProjection.make(
                level: 30, limit: 80,
                observedRate: 100,   // 100 %/h right now
                power: 150, usableCapacity: 75,
                // A straight line would take half an hour. The car says it needs
                // an hour and a quarter.
                hoursToFull: 1.25,
                now: now
            )
        )
        XCTAssertTrue(projection.isTapering)

        let straightLine = 30 + 100 * 1.0
        let projected = projection.level(after: 3_600)
        XCTAssertLessThan(projected, straightLine, "A tapering charge must not promise the flat-rate figure")
        XCTAssertGreaterThan(projected, 30)
    }

    /// The fit has one job: agree with the car about when the limit arrives.
    func testTheFitLandsOnTheCarsOwnFinishingTime() throws {
        let projection = try XCTUnwrap(
            ChargeProjection.make(
                level: 20, limit: 90,
                observedRate: 120, power: nil, usableCapacity: nil,
                hoursToFull: 1.5,
                now: now
            )
        )
        let completes = try XCTUnwrap(projection.completesAt)
        XCTAssertEqual(
            completes.timeIntervalSince(now),
            1.5 * 3_600,
            accuracy: 60,
            "The model is anchored on the car's estimate; landing elsewhere means the fit is wrong"
        )
    }

    func testATaperingRateFallsAsThePackFills() throws {
        let projection = try XCTUnwrap(
            ChargeProjection.make(
                level: 20, limit: 90,
                observedRate: 120, power: nil, usableCapacity: nil,
                hoursToFull: 1.5,
                now: now
            )
        )
        XCTAssertGreaterThan(projection.rate(at: 30), projection.rate(at: 70))
        XCTAssertGreaterThan(projection.rate(at: 70), 0, "A rate that reaches zero never arrives")
    }

    /// If the car expects to do better than the rate measured this instant — a
    /// pack still warming, say — its estimate is the better evidence.
    func testWhenTheCarExpectsToSpeedUpItsOwnEstimateWins() throws {
        let projection = try XCTUnwrap(
            ChargeProjection.make(
                level: 20, limit: 80,
                observedRate: 20,     // a straight line would need three hours
                power: nil, usableCapacity: nil,
                hoursToFull: 1,       // the car says one
                now: now
            )
        )
        XCTAssertFalse(projection.isTapering)
        XCTAssertEqual(projection.level(after: 3_600), 80, accuracy: 0.5)
    }

    // MARK: - Where the taper belongs

    /// A wall box is the charger's limit, not the pack's. Ten kilowatts into any
    /// Tesla pack is under 0.15C — nothing about the chemistry is being asked for
    /// at that current, so the rate holds and the line is straight.
    func testAWallBoxHoldsItsRateForTheWholeSession() throws {
        let projection = try XCTUnwrap(
            ChargeProjection.make(
                level: 64, limit: 100,
                observedRate: 9.46,
                power: 7, usableCapacity: 74,
                hoursToFull: 4.7,        // longer than 36 / 9.46 = 3.8
                now: now
            )
        )
        XCTAssertFalse(projection.isTapering, "7 kW does not taper")
        for percent in [70.0, 85, 95, 99] {
            XCTAssertEqual(projection.rate(at: percent), 9.46, accuracy: 0.01)
        }

        // 80% arrives at the flat rate, not forty-five minutes later — which is
        // what smearing a taper across the whole charge produced.
        let eighty = try XCTUnwrap(projection.date(reaching: 80))
        XCTAssertEqual(
            eighty.timeIntervalSince(now) / 3_600,
            (80 - 64) / 9.46,
            accuracy: 0.05
        )
    }

    /// The power line for a slow charge has to be level, because the charger's
    /// output is.
    func testAWallBoxPowerForecastIsLevel() throws {
        let projection = try XCTUnwrap(
            ChargeProjection.make(
                level: 40, limit: 100,
                observedRate: 9.4, power: 7, usableCapacity: 74,
                hoursToFull: 8, now: now
            )
        )
        XCTAssertEqual(try XCTUnwrap(projection.power(at: 50)), 7, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(projection.power(at: 95)), 7, accuracy: 0.01)
    }

    /// A DC charge is already past the knee: it tapers from wherever it is.
    func testADirectCurrentChargeTapersFromWhereItIsNow() throws {
        let projection = try XCTUnwrap(
            ChargeProjection.make(
                level: 30, limit: 80,
                observedRate: 100, power: 150, usableCapacity: 75,
                hoursToFull: 1.25, now: now
            )
        )
        XCTAssertEqual(projection.knee, 30, "Nothing is flat on a Supercharger at 30%")
        XCTAssertLessThan(projection.rate(at: 45), projection.rate(at: 31))
    }

    /// A moderate DC charge with no history to draw on still gets the fitted
    /// knee, which is what the fallback is for.
    func testAFastChargeWithNoHistoryFallsBackToTheFittedKnee() throws {
        let projection = try XCTUnwrap(
            ChargeProjection.make(
                level: 50, limit: 100,
                observedRate: 25,           // under the DC rate threshold
                power: 22, usableCapacity: 74,
                hoursToFull: 3, now: now    // longer than 50 / 25 = 2
            )
        )
        XCTAssertFalse(projection.isLearned)
        XCTAssertTrue(projection.isTapering)
        XCTAssertEqual(projection.knee, ChargeProjection.wallBoxKnee)
    }

    /// Whatever the shape, the fit still has to land where the car says.
    func testAFittedShapeLandsOnTheCarsFinishingTime() throws {
        let projection = try XCTUnwrap(
            ChargeProjection.make(
                level: 50, limit: 100,
                observedRate: 25, power: 22, usableCapacity: 74,
                hoursToFull: 3, now: now
            )
        )
        let completes = try XCTUnwrap(projection.completesAt)
        XCTAssertEqual(completes.timeIntervalSince(now) / 3_600, 3, accuracy: 0.06)
    }

    // MARK: - A curve learned from the car

    /// A profile shaped like a real Supercharger taper: strong low down, easing
    /// steadily, well down by the top.
    private func superchargerProfile() -> ChargeCurveProfile {
        var profile = ChargeCurveProfile()
        for level in stride(from: 5.0, through: 97.0, by: 1) {
            let power = max(170 - 1.6 * level, 20)
            for _ in 0..<3 { profile.record(level: level, power: power) }
        }
        return profile
    }

    func testAFastChargeUsesTheShapeLearnedFromThisCar() throws {
        let projection = try XCTUnwrap(
            ChargeProjection.make(
                level: 30, limit: 80,
                observedRate: 100, power: 120, usableCapacity: 75,
                hoursToFull: 1.25,
                profile: superchargerProfile(),
                now: now
            )
        )
        XCTAssertTrue(projection.isLearned, "There is a measured curve; use it")
        XCTAssertTrue(projection.isTapering)
        XCTAssertGreaterThan(projection.rate(at: 35), projection.rate(at: 75))
    }

    /// The learned shape is still re-timed to agree with the car, because the
    /// profile knows the shape and the car knows today.
    func testALearnedShapeIsScaledToTheCarsFinishingTime() throws {
        let projection = try XCTUnwrap(
            ChargeProjection.make(
                level: 30, limit: 80,
                observedRate: 100, power: 120, usableCapacity: 75,
                hoursToFull: 1.25,
                profile: superchargerProfile(),
                now: now
            )
        )
        let completes = try XCTUnwrap(projection.completesAt)
        XCTAssertEqual(completes.timeIntervalSince(now) / 3_600, 1.25, accuracy: 0.06)
    }

    /// A profile that has only seen the bottom of the pack says nothing about the
    /// top, and must not be used as though it did.
    func testAProfileThatDoesNotCoverTheClimbIsNotUsed() throws {
        var profile = ChargeCurveProfile()
        for level in stride(from: 5.0, through: 25.0, by: 1) {
            for _ in 0..<3 { profile.record(level: level, power: 150) }
        }
        let projection = try XCTUnwrap(
            ChargeProjection.make(
                level: 60, limit: 90,
                observedRate: 60, power: 60, usableCapacity: 75,
                hoursToFull: 0.9, profile: profile, now: now
            )
        )
        XCTAssertFalse(projection.isLearned)
    }

    /// A wall box never consults the profile: its shape is flat whatever the
    /// history of fast charges says.
    func testAWallBoxIgnoresTheLearnedCurveEntirely() throws {
        let projection = try XCTUnwrap(
            ChargeProjection.make(
                level: 40, limit: 100,
                observedRate: 9.4, power: 7, usableCapacity: 74,
                hoursToFull: 8,
                profile: superchargerProfile(),
                now: now
            )
        )
        XCTAssertFalse(projection.isLearned)
        XCTAssertFalse(projection.isTapering)
    }

    // MARK: - Milestones

    func testMilestonesAreTheRoundNumbersStillAhead() throws {
        let projection = try XCTUnwrap(
            ChargeProjection.make(
                level: 42, limit: 80,
                observedRate: 20, power: nil, usableCapacity: nil,
                hoursToFull: 38.0 / 20.0,
                now: now
            )
        )
        XCTAssertEqual(projection.milestones().map(\.percent), [50, 60, 70, 80])
    }

    func testAMilestoneAboveTheLimitHasNoTimeRatherThanAnInventedOne() throws {
        // The car stops at 80. "When will it reach 90" has no answer, and a date
        // is worse than nothing because someone would wait for it.
        let projection = try XCTUnwrap(
            ChargeProjection.make(
                level: 50, limit: 80,
                observedRate: 30, power: nil, usableCapacity: nil,
                hoursToFull: 1, now: now
            )
        )
        XCTAssertNil(projection.date(reaching: 90))
        XCTAssertNotNil(projection.date(reaching: 80))
        XCTAssertFalse(projection.milestones().contains { $0.percent > 80 })
    }

    func testMilestonesRunInOrderAndInTheFuture() throws {
        let projection = try XCTUnwrap(
            ChargeProjection.make(
                level: 15, limit: 100,
                observedRate: 90, power: nil, usableCapacity: nil,
                hoursToFull: 2.4, now: now
            )
        )
        let milestones = projection.milestones()
        XCTAssertFalse(milestones.isEmpty)
        for (earlier, later) in zip(milestones, milestones.dropFirst()) {
            XCTAssertLessThan(earlier.date, later.date, "A later milestone cannot arrive sooner")
        }
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(milestones.first).date, now)
    }

    // MARK: - Nothing to say

    func testAChargeAlreadyAtItsLimitProjectsNothing() throws {
        let projection = try XCTUnwrap(
            ChargeProjection.make(
                level: 80, limit: 80,
                observedRate: 0, power: nil, usableCapacity: nil,
                hoursToFull: 0, now: now
            )
        )
        XCTAssertTrue(projection.isComplete)
        XCTAssertTrue(projection.milestones().isEmpty)
    }

    func testNoRateFromAnySourceIsNoProjection() {
        // Better a card with no forecast on it than a forecast of nothing
        // presented as a forecast.
        XCTAssertNil(
            ChargeProjection.make(
                level: 40, limit: 80,
                observedRate: nil, power: nil, usableCapacity: nil, hoursToFull: nil,
                now: now
            )
        )
    }

    func testPowerAndPackSizeCarryTheFirstMinutesBeforeARateCanBeMeasured() throws {
        let projection = try XCTUnwrap(
            ChargeProjection.make(
                level: 40, limit: 80,
                observedRate: nil,
                power: 11, usableCapacity: 75,
                hoursToFull: nil,
                now: now
            )
        )
        // 11 kW into 75 kWh is about 14.7 points an hour.
        XCTAssertEqual(projection.initialRate, 14.67, accuracy: 0.1)
    }

    // MARK: - Power

    /// The forecast power line has to start exactly where the measured one ends.
    ///
    /// It used to be computed as rate × pack capacity, which is arithmetically
    /// tidy and wrong: usable capacity is not rated capacity and the charger's
    /// reported power includes losses the pack never sees, so the two disagreed by
    /// tens of kilowatts and the chart showed a step at the join.
    func testTheForecastPowerContinuesFromTheReportedPowerRatherThanRestarting() throws {
        let projection = try XCTUnwrap(
            ChargeProjection.make(
                level: 41, limit: 80,
                observedRate: 87,
                power: 118, usableCapacity: 78,
                hoursToFull: 0.62,
                now: now
            )
        )
        XCTAssertEqual(
            try XCTUnwrap(projection.power(at: 41)),
            118,
            accuracy: 0.01,
            "The join between measured and forecast is where a reader is looking"
        )
    }

    func testForecastPowerFallsInStepWithTheRate() throws {
        let projection = try XCTUnwrap(
            ChargeProjection.make(
                level: 30, limit: 80,
                observedRate: 100, power: 120, usableCapacity: 75,
                hoursToFull: 1.25, now: now
            )
        )
        let early = try XCTUnwrap(projection.power(at: 35))
        let late = try XCTUnwrap(projection.power(at: 75))
        XCTAssertGreaterThan(early, late)
        // Power is the rate in different units, so the ratios must match.
        XCTAssertEqual(
            late / early,
            projection.rate(at: 75) / projection.rate(at: 35),
            accuracy: 0.001
        )
    }

    func testWithNoReportedPowerThereIsNoPowerForecast() throws {
        // Rather than deriving one from pack size, which is the thing that was
        // wrong before.
        let projection = try XCTUnwrap(
            ChargeProjection.make(
                level: 40, limit: 80,
                observedRate: 20, power: nil, usableCapacity: 75,
                hoursToFull: 2, now: now
            )
        )
        XCTAssertNil(projection.power(at: 60))
    }

    func testTheCurveStopsAtTheLimitRatherThanRunningOn() throws {
        let projection = try XCTUnwrap(
            ChargeProjection.make(
                level: 70, limit: 80,
                observedRate: 20, power: nil, usableCapacity: nil,
                hoursToFull: 0.5, now: now
            )
        )
        let curve = projection.curve(through: 6 * 3_600)
        XCTAssertEqual(try XCTUnwrap(curve.last).percent, 80, accuracy: 0.01)
        XCTAssertLessThan(
            try XCTUnwrap(curve.last).date.timeIntervalSince(now),
            3_600,
            "The curve should end when charging does"
        )
    }
}

/// The measured rate is what everything above is built on, so what it refuses to
/// measure matters as much as what it does.
final class LiveChargeSessionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func session(levels: [(minutes: Double, level: Double)]) -> LiveChargeSession {
        var session = LiveChargeSession()
        for point in levels {
            session.record(
                date: start.addingTimeInterval(point.minutes * 60),
                level: point.level,
                power: 11,
                energyAdded: nil,
                range: nil
            )
        }
        return session
    }

    func testARateIsMeasuredFromTheChargeActuallyGained() {
        let session = session(levels: [(0, 40), (5, 41), (10, 43)])
        let rate = session.observedRate(now: start.addingTimeInterval(10 * 60))
        // Three points in ten minutes is eighteen an hour.
        XCTAssertEqual(try XCTUnwrap(rate), 18, accuracy: 0.5)
    }

    func testTooShortASpanIsNoRateRatherThanAWildOne() {
        // A level reported in whole percent, divided by twenty seconds, is either
        // zero or enormous — and both would be put on screen as a plan.
        let session = session(levels: [(0, 40), (0.33, 41)])
        XCTAssertNil(session.observedRate(now: start.addingTimeInterval(20)))
    }

    func testALevelThatHasNotTickedOverYetIsNotAZeroRate() {
        // Between two whole percents the car reports the same number for minutes.
        // That is granularity, not a stalled charge.
        let session = session(levels: [(0, 40), (5, 40), (10, 40)])
        XCTAssertNil(session.observedRate(now: start.addingTimeInterval(10 * 60)))
    }

    func testOldReadingsFallOutOfTheWindowSoATaperIsFollowedDown() {
        var session = LiveChargeSession()
        // Fast early, slow now. Averaging across the whole session would report a
        // rate the charger stopped delivering half an hour ago.
        for minute in stride(from: 0.0, through: 30.0, by: 5) {
            session.record(
                date: start.addingTimeInterval(minute * 60),
                level: 20 + minute * 2,
                power: 150, energyAdded: nil, range: nil
            )
        }
        for minute in stride(from: 35.0, through: 60.0, by: 5) {
            session.record(
                date: start.addingTimeInterval(minute * 60),
                level: 80 + (minute - 30) * 0.2,
                power: 30, energyAdded: nil, range: nil
            )
        }
        let rate = try? XCTUnwrap(session.observedRate(now: start.addingTimeInterval(60 * 60)))
        XCTAssertEqual(try XCTUnwrap(rate), 12, accuracy: 2, "The recent window is what is happening now")
    }

    func testGainsAreMeasuredFromTheStartOfTheSession() {
        var session = LiveChargeSession()
        session.record(date: start, level: 30, power: 50, energyAdded: 0, range: 100)
        session.record(date: start.addingTimeInterval(600), level: 45, power: 50, energyAdded: 11.2, range: 155)
        XCTAssertEqual(session.levelGained, 15)
        XCTAssertEqual(session.rangeGained, 55)
        XCTAssertEqual(session.energyAdded, 11.2)
    }

    func testAResetLeavesNothingOfThePreviousCharge() {
        var session = LiveChargeSession()
        session.record(date: start, level: 30, power: 50, energyAdded: 1, range: 100)
        session.reset()
        XCTAssertTrue(session.isEmpty)
        XCTAssertNil(session.startedAt)
        XCTAssertNil(session.levelGained)
    }
}

/// The profile is the app's memory of how this car charges, so what it declines
/// to learn matters as much as what it does.
final class ChargeCurveProfileTests: XCTestCase {
    func testAWallBoxIsNotLearnedFrom() {
        // Its readings are flat and would drag a taper towards a straight line.
        var profile = ChargeCurveProfile()
        for level in stride(from: 20.0, through: 90.0, by: 1) {
            profile.record(level: level, power: 7)
        }
        XCTAssertTrue(profile.isEmpty)
    }

    func testABucketIsNotTrustedUntilItHasBeenSeenSeveralTimes() {
        var profile = ChargeCurveProfile()
        profile.record(level: 50, power: 100)
        XCTAssertNil(profile.power(at: 50), "One reading is an anecdote")
        profile.record(level: 50, power: 100)
        profile.record(level: 50, power: 100)
        XCTAssertEqual(try XCTUnwrap(profile.power(at: 50)), 100, accuracy: 0.01)
    }

    func testTheShapeIsRelativeRatherThanAbsolute() throws {
        // Scale belongs to the live reading: a cold pack changes the height of the
        // curve without changing its shape.
        var profile = ChargeCurveProfile()
        for _ in 0..<3 {
            profile.record(level: 32, power: 150)
            profile.record(level: 72, power: 75)
        }
        let relative = try XCTUnwrap(profile.relativeRate(at: 72, comparedWith: 32))
        XCTAssertEqual(relative, 0.5, accuracy: 0.05)
    }

    func testCoverageIsJudgedAboveTheCurrentChargeNotBelowIt() {
        var profile = ChargeCurveProfile()
        for level in stride(from: 5.0, through: 30.0, by: 1) {
            for _ in 0..<3 { profile.record(level: level, power: 150) }
        }
        XCTAssertFalse(
            profile.covers(from: 60, to: 90),
            "Readings from the bottom of the pack say nothing about the top"
        )
        XCTAssertTrue(profile.covers(from: 10, to: 30))
    }

    func testBeyondTheReadingsTheCurveHoldsRatherThanHeadingForZero() throws {
        // A taper extrapolated past the evidence predicts a charge that never
        // finishes.
        var profile = ChargeCurveProfile()
        for _ in 0..<3 {
            profile.record(level: 30, power: 120)
            profile.record(level: 50, power: 80)
        }
        let beyond = try XCTUnwrap(profile.relativeRate(at: 95, comparedWith: 30))
        XCTAssertGreaterThan(beyond, 0)
    }

    func testItSurvivesBeingWrittenDownAndReadBack() throws {
        var profile = ChargeCurveProfile()
        for _ in 0..<3 { profile.record(level: 45, power: 110) }
        let restored = try XCTUnwrap(ChargeCurveProfile.decoded(from: profile.encoded()))
        XCTAssertEqual(restored, profile)
        XCTAssertEqual(try XCTUnwrap(restored.power(at: 45)), 110, accuracy: 0.01)
    }
}
